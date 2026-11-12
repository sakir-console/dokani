import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../../core/money/exact.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/sync/sync_engine.dart';
import '../../customers/data/customer_repository.dart';
import '../data/sale_models.dart';
import '../data/sales_repository.dart';

/// What the phone needs to show a sale before the server has confirmed it.
class SaleDisplay {
  const SaleDisplay({required this.lines, required this.subtotal, required this.paid, required this.change, this.customerName});

  /// Product titles in the same order as the draft's items.
  final List<String> lines;
  final String subtotal;
  final String paid;
  final String change;
  final String? customerName;
}

/// The outcome of completing a sale.
class SubmittedSale {
  const SubmittedSale.confirmed(Sale this.sale) : pendingUuid = null;

  const SubmittedSale.pending(String this.pendingUuid) : sale = null;

  /// Set when the server has the sale.
  final Sale? sale;

  /// Set when the sale is saved on the phone and waiting for a connection.
  final String? pendingUuid;

  bool get isPending => pendingUuid != null;
}

/// Completes sales and due collections so that they cannot be lost.
///
///  1. The record is written to the phone's queue.
///  2. Only then is it sent to the server.
///  3. No answer (no internet, a timeout, a server fault, the app being
///     closed)? It stays in the queue and is sent later with the same id, so
///     it is never recorded twice.
///  4. The server refuses it while the cashier is still on the screen (the
///     total changed, stock ran out)? It is taken out of the queue again and
///     the reason is shown, so the cashier can correct the bill.
class SaleSubmitter {
  SaleSubmitter(this._ref);

  final Ref _ref;

  Future<SubmittedSale> submit(SaleDraft draft, SaleDisplay display) async {
    final database = _ref.read(localDatabaseProvider);
    final sales = _ref.read(salesRepositoryProvider);
    final soldAt = DateTime.now();
    // A short reference the cashier can read out; the full id is what makes the sale unique.
    final compact = draft.clientUuid.replaceAll('-', '').toUpperCase();
    final offlineRef = 'OFF-${compact.length > 8 ? compact.substring(0, 8) : compact}';

    if (database == null) {
      return SubmittedSale.confirmed(await sales.createSale(draft, soldAt: soldAt));
    }

    await database.enqueue(
      clientUuid: draft.clientUuid,
      kind: 'sale',
      payload: {...draft.toJson(), 'sold_at': soldAt.toUtc().toIso8601String(), 'offline_ref': offlineRef},
      display: _displayJson(draft, display, soldAt, offlineRef),
      createdAt: soldAt,
    );
    // The counter on this phone should stop offering what was just sold.
    await _moveStock(database, draft.toJson(), sold: true);

    try {
      final sale = await sales.createSale(draft, soldAt: soldAt, offlineRef: offlineRef);
      await database.markSynced(draft.clientUuid, {'id': sale.id, 'invoice_no': sale.invoiceNo, 'invoice_url': sale.invoiceUrl});
      return SubmittedSale.confirmed(sale);
    } on ApiException catch (error) {
      if (_refusedByServer(error)) {
        await database.discard(draft.clientUuid);
        await _moveStock(database, draft.toJson(), sold: false);
        rethrow;
      }

      // No answer: the sale is safe in the queue.
      await _rememberDue(database, draft);
      unawaited(_ref.read(syncEngineProvider.notifier).sync());
      return SubmittedSale.pending(draft.clientUuid);
    }
  }

  /// A clear "no" from the server (a rule was broken, or this user may not do
  /// this), as opposed to no answer, an expired login, rate limiting or a
  /// server fault, after which the record must be kept and retried.
  bool _refusedByServer(ApiException error) {
    final status = error.statusCode ?? 0;
    return error.kind == ApiErrorKind.server && status >= 400 && status < 500 && status != 408 && status != 429;
  }

  Future<void> _moveStock(LocalDatabase database, Map<String, dynamic> payload, {required bool sold}) async {
    for (final item in (payload['items'] as List? ?? const [])) {
      final milli = Exact.milli('${(item as Map)['quantity']}');
      await database.adjustLocalStock(item['variant_id'] as int, sold ? -milli : milli);
    }
  }

  /// A due sale made offline raises what this phone shows the customer owes,
  /// so a second offline lookup is not misleading. The next sync replaces it.
  Future<void> _rememberDue(LocalDatabase database, SaleDraft draft) async {
    final phone = draft.customerPhone;
    final due = Exact.paisa(draft.dueAmount);
    if (phone == null || due <= 0) return;

    final saved = await database.customerByPhone(phone);
    if (saved == null) return;
    saved['current_due'] = Exact.money(Exact.paisa('${saved['current_due'] ?? '0.00'}') + due);
    await database.upsertCustomers([saved]);
  }

  /// The sale in the same shape the server returns, so the same receipt can
  /// draw it before the server has seen it.
  Map<String, dynamic> _displayJson(SaleDraft draft, SaleDisplay display, DateTime soldAt, String offlineRef) => {
        'id': 0,
        'invoice_no': offlineRef,
        'sold_at': soldAt.toUtc().toIso8601String(),
        'status': 'completed',
        'subtotal': display.subtotal,
        'discount_amount': draft.discountAmount,
        'additional_charge': draft.additionalCharge,
        'grand_total': draft.grandTotal,
        'paid_amount': display.paid,
        'due_amount': draft.dueAmount,
        'change_amount': display.change,
        'customer': draft.customerPhone == null
            ? null
            : {'id': 0, 'name': display.customerName ?? draft.customerName ?? draft.customerPhone, 'phone': draft.customerPhone},
        'items': [
          for (final (index, item) in draft.items.indexed)
            {
              'product_name': index < display.lines.length ? display.lines[index] : '',
              'quantity': item.quantity,
              'unit_price': item.unitPrice,
              'line_total': Exact.money(Exact.lineTotal(Exact.paisa(item.unitPrice), Exact.milli(item.quantity))),
            },
        ],
        'payments': [
          for (final payment in draft.payments)
            {'type': 'sale', 'method': payment.method.name, 'amount': payment.amount, 'transaction_id': payment.transactionId},
        ],
      };

  /// Records a payment against a customer's due, with the same guarantees as
  /// a sale. Returns the customer's balance as far as this phone knows it.
  Future<({Customer customer, bool pending})> collectDue({
    required Customer customer,
    required String clientUuid,
    required String amount,
    required PaymentMethod method,
    String? transactionId,
  }) async {
    final database = _ref.read(localDatabaseProvider);
    final customers = _ref.read(customerRepositoryProvider);

    Future<Customer> online() => customers.collectDue(
          customerId: customer.id,
          clientUuid: clientUuid,
          amount: amount,
          method: method,
          transactionId: transactionId,
        );

    if (database == null) return (customer: await online(), pending: false);

    final paidAt = DateTime.now();
    await database.enqueue(
      clientUuid: clientUuid,
      kind: 'due_collection',
      payload: {
        'client_uuid': clientUuid,
        'customer_id': customer.id,
        'amount': amount,
        'method': method.name,
        'transaction_id': ?transactionId,
        'paid_at': paidAt.toUtc().toIso8601String(),
      },
      display: {'customer_name': customer.name, 'customer_phone': customer.phone, 'amount': amount, 'method': method.name},
      createdAt: paidAt,
    );

    try {
      final updated = await online();
      await database.markSynced(clientUuid, {'customer_id': updated.id, 'current_due': updated.currentDue});
      await database.upsertCustomers([updated.toJson()]);
      return (customer: updated, pending: false);
    } on ApiException catch (error) {
      if (_refusedByServer(error)) {
        await database.discard(clientUuid);
        rethrow;
      }
      unawaited(_ref.read(syncEngineProvider.notifier).sync());

      // Show the balance this payment leaves, and remember it for the next offline lookup.
      final reduced = Customer(
        id: customer.id,
        name: customer.name,
        phone: customer.phone,
        address: customer.address,
        notes: customer.notes,
        currentDue: Exact.money(Exact.paisa(customer.currentDue) - Exact.paisa(amount)),
        totalPurchases: customer.totalPurchases,
        totalPaid: Exact.money(Exact.paisa(customer.totalPaid) + Exact.paisa(amount)),
      );
      await database.upsertCustomers([reduced.toJson()]);
      return (customer: reduced, pending: true);
    }
  }

  /// Deletes a record the server has refused, at the user's explicit request.
  /// A sale's stock is put back on this phone's copy.
  Future<void> discardFailed(OutboxEntry entry) async {
    final database = _ref.read(localDatabaseProvider);
    if (database == null || entry.status != 'failed') return;

    await database.discard(entry.clientUuid);
    if (entry.kind == 'sale') {
      await _moveStock(database, (jsonDecode(entry.payload) as Map).cast<String, dynamic>(), sold: false);
    }
  }
}

final saleSubmitterProvider = Provider(SaleSubmitter.new);

/// What a queued record stored for display.
Map<String, dynamic> outboxDisplay(OutboxEntry entry) => (jsonDecode(entry.display) as Map).cast<String, dynamic>();

/// What the server answered for a confirmed record, or an empty map.
Map<String, dynamic> outboxServer(OutboxEntry entry) =>
    entry.server == null ? const {} : (jsonDecode(entry.server!) as Map).cast<String, dynamic>();
