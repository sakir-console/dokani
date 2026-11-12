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

/// Completes a sale so that it cannot be lost.
///
///  1. The sale is written to the phone's queue.
///  2. Only then is it sent to the server.
///  3. No answer (no internet, a timeout, the app being closed)? It stays in
///     the queue and is sent later, with the same id so it is never doubled.
///  4. The server refuses it while the cashier is still at the checkout
///     (the total changed, stock ran out)? It is taken out of the queue again
///     and the reason is shown, so the cashier can fix the bill.
class SaleSubmitter {
  SaleSubmitter(this._ref);

  final Ref _ref;

  Future<SubmittedSale> submit(SaleDraft draft, SaleDisplay display) async {
    final database = _ref.read(localDatabaseProvider);
    final sales = _ref.read(salesRepositoryProvider);
    final soldAt = DateTime.now();
    final offlineRef = 'OFF-${draft.clientUuid.substring(0, 8).toUpperCase()}';

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
    for (final item in draft.items) {
      await database.adjustLocalStock(item.variantId, -Exact.milli(item.quantity));
    }

    try {
      final sale = await sales.createSale(draft, soldAt: soldAt, offlineRef: offlineRef);
      await database.markSynced(draft.clientUuid, {'id': sale.id, 'invoice_no': sale.invoiceNo, 'invoice_url': sale.invoiceUrl});
      return SubmittedSale.confirmed(sale);
    } on ApiException catch (error) {
      if (_refusedByServer(error)) {
        await _undo(database, draft);
        rethrow;
      }
      // No answer: the sale is safe in the queue. Try again in the background.
      unawaited(_ref.read(syncEngineProvider.notifier).sync());
      return SubmittedSale.pending(draft.clientUuid);
    }
  }

  /// A clear "no" from the server, as opposed to no answer at all.
  bool _refusedByServer(ApiException error) =>
      error.kind == ApiErrorKind.server && (error.statusCode ?? 500) >= 400 && (error.statusCode ?? 500) < 500;

  Future<void> _undo(LocalDatabase database, SaleDraft draft) async {
    await database.discard(draft.clientUuid);
    for (final item in draft.items) {
      await database.adjustLocalStock(item.variantId, Exact.milli(item.quantity));
    }
  }

  Map<String, dynamic> _displayJson(SaleDraft draft, SaleDisplay display, DateTime soldAt, String offlineRef) => {
        'offline_ref': offlineRef,
        'sold_at': soldAt.toIso8601String(),
        'items': [
          for (final (index, item) in draft.items.indexed)
            {
              'title': index < display.lines.length ? display.lines[index] : '',
              'quantity': item.quantity,
              'unit_price': item.unitPrice,
              'line_total': Exact.money(Exact.lineTotal(Exact.paisa(item.unitPrice), Exact.milli(item.quantity))),
            },
        ],
        'subtotal': display.subtotal,
        'discount_amount': draft.discountAmount,
        'additional_charge': draft.additionalCharge,
        'grand_total': draft.grandTotal,
        'paid_amount': display.paid,
        'due_amount': draft.dueAmount,
        'change_amount': display.change,
        'payments': [for (final payment in draft.payments) {'method': payment.method.name, 'amount': payment.amount}],
        'customer_name': display.customerName,
        'customer_phone': draft.customerPhone,
      };

  /// Records a payment against a customer's due, with the same guarantees as a sale.
  /// Returns the customer's balance as far as this phone knows it.
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
        currentDue: Exact.money(Exact.paisa(customer.currentDue) - Exact.paisa(amount)),
        totalPurchases: customer.totalPurchases,
        totalPaid: Exact.money(Exact.paisa(customer.totalPaid) + Exact.paisa(amount)),
      );
      await database.upsertCustomers([reduced.toJson()]);
      return (customer: reduced, pending: true);
    }
  }
}

final saleSubmitterProvider = Provider(SaleSubmitter.new);

/// A queued record decoded for display.
Map<String, dynamic> outboxDisplay(OutboxEntry entry) => (jsonDecode(entry.display) as Map).cast<String, dynamic>();
