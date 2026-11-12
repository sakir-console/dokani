import 'package:dokani/core/money/exact.dart';
import 'package:dokani/core/network/api_exception.dart';
import 'package:dokani/features/catalog/data/models.dart';
import 'package:dokani/features/customers/data/customer_repository.dart';
import 'package:dokani/features/pos/data/sale_models.dart';
import 'package:dokani/features/pos/data/sales_repository.dart';

import 'catalog_fakes.dart';

ApiException _refusal(String code, String message, [int status = 422]) =>
    ApiException(kind: ApiErrorKind.server, statusCode: status, code: code, message: message);

/// In-memory customers with a ledger, following the server's rules.
class FakeCustomerRepository implements CustomerRepository {
  FakeCustomerRepository([List<Customer>? customers]) : _customers = [...?customers];

  final List<Customer> _customers;
  final Map<int, List<LedgerEntry>> _ledgers = {};
  int _nextId = 700;

  final List<String> collections = [];
  final Set<String> _seenUuids = {};
  final List<CustomerDraft> created = [];

  Customer _replace(Customer c, {String? due, String? purchases, String? paid, String? name, String? phone, String? address}) {
    final updated = Customer(
      id: c.id,
      name: name ?? c.name,
      phone: phone ?? c.phone,
      address: address ?? c.address,
      currentDue: due ?? c.currentDue,
      totalPurchases: purchases ?? c.totalPurchases,
      totalPaid: paid ?? c.totalPaid,
    );
    _customers[_customers.indexWhere((x) => x.id == c.id)] = updated;
    return updated;
  }

  void _entry(int customerId, String type, {String debit = '0.00', String credit = '0.00', required String balance, String? invoiceNo, PaymentMethod? method}) {
    _ledgers.putIfAbsent(customerId, () => []).insert(
          0,
          LedgerEntry(type: type, debit: debit, credit: credit, balanceAfter: balance, createdAt: DateTime(2026, 11, 12, 10), invoiceNo: invoiceNo, paymentMethod: method),
        );
  }

  /// Used by the fake sales repository: a sale put [duePaisa] on this customer's account.
  Customer recordSale(Customer customer, {required int totalPaisa, required int paidPaisa, required int duePaisa, required String invoiceNo}) {
    final balance = Exact.money(Exact.paisa(customer.currentDue) + duePaisa);
    if (duePaisa > 0) _entry(customer.id, 'sale_due', debit: Exact.money(duePaisa), balance: balance, invoiceNo: invoiceNo);
    return _replace(
      customer,
      due: balance,
      purchases: Exact.money(Exact.paisa(customer.totalPurchases) + totalPaisa),
      paid: Exact.money(Exact.paisa(customer.totalPaid) + paidPaisa),
    );
  }

  Customer findOrCreate(String phone, String? name) {
    final existing = _customers.where((c) => c.phone == phone).firstOrNull;
    if (existing != null) return existing;
    if (name == null || name.isEmpty) {
      throw _refusal('CUSTOMER_NAME_REQUIRED', "Enter the customer's name to create their account.");
    }
    final customer = Customer(id: _nextId++, name: name, phone: phone);
    _customers.add(customer);
    return customer;
  }

  @override
  Future<List<Customer>> customers({String query = '', bool hasDue = false}) async {
    final q = query.toLowerCase();
    final list = _customers
        .where((c) => (q.isEmpty || c.name.toLowerCase().contains(q) || c.phone.contains(q)) && (!hasDue || c.dueValue > 0))
        .toList();
    hasDue ? list.sort((a, b) => b.dueValue.compareTo(a.dueValue)) : list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  @override
  Future<Customer?> lookup(String phone) async => _customers.where((c) => c.phone == phone).firstOrNull;

  @override
  Future<Customer> customer(int id) async => _customers.firstWhere((c) => c.id == id);

  @override
  Future<Customer> create(CustomerDraft draft) async {
    if (_customers.any((c) => c.phone == draft.phone)) {
      throw _refusal('CUSTOMER_EXISTS', 'A customer with this mobile number already exists.');
    }
    created.add(draft);
    final opening = draft.openingDue == null ? 0 : Exact.paisa(draft.openingDue!);
    final customer = Customer(id: _nextId++, name: draft.name, phone: draft.phone, address: draft.address, currentDue: Exact.money(opening));
    _customers.add(customer);
    if (opening > 0) _entry(customer.id, 'opening', debit: Exact.money(opening), balance: Exact.money(opening));
    return customer;
  }

  @override
  Future<Customer> update(int id, CustomerDraft draft) async =>
      _replace(_customers.firstWhere((c) => c.id == id), name: draft.name, phone: draft.phone, address: draft.address);

  @override
  Future<List<LedgerEntry>> ledger(int customerId) async => [...?_ledgers[customerId]];

  @override
  Future<Customer> collectDue({
    required int customerId,
    required String clientUuid,
    required String amount,
    required PaymentMethod method,
    String? transactionId,
  }) async {
    final customer = _customers.firstWhere((c) => c.id == customerId);
    if (!_seenUuids.add(clientUuid)) return customer; // a repeat of the same request

    final paisa = Exact.paisa(amount);
    if (paisa > Exact.paisa(customer.currentDue)) {
      throw _refusal('AMOUNT_EXCEEDS_DUE', 'You cannot collect more than the customer owes.');
    }
    collections.add('$customerId $amount ${method.name} tx=$transactionId');
    final balance = Exact.money(Exact.paisa(customer.currentDue) - paisa);
    _entry(customerId, 'payment', credit: Exact.money(paisa), balance: balance, method: method);
    return _replace(customer, due: balance, paid: Exact.money(Exact.paisa(customer.totalPaid) + paisa));
  }
}

/// In-memory sales that apply the server's checks: totals, payments adding
/// up, the customer requirement for a due, and one sale per client id.
class FakeSalesRepository implements SalesRepository {
  FakeSalesRepository({required this.catalog, required this.customers, this.showProfit = true});

  final FakeCatalogRepository catalog;
  final FakeCustomerRepository customers;
  final bool showProfit;

  final List<Sale> _sales = [];
  final List<SaleDraft> received = [];
  final Map<String, Sale> _byUuid = {};
  final List<String> voided = [];
  ApiException? failNext;
  int _nextId = 1;

  List<Sale> get all => List.unmodifiable(_sales);

  @override
  Future<Sale> createSale(SaleDraft draft, {DateTime? soldAt, String? offlineRef}) async {
    received.add(draft);

    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    if (_byUuid[draft.clientUuid] case final existing?) return existing;

    // Totals from the lines, as the server computes them.
    var subtotal = 0;
    final items = <SaleItem>[];
    for (final line in draft.items) {
      final product = catalog.all.firstWhere((p) => p.variants.any((v) => v.id == line.variantId));
      final variant = product.variants.firstWhere((v) => v.id == line.variantId);
      if (Exact.paisa(line.unitPrice) != Exact.paisa(variant.sellingPrice)) {
        throw _refusal('PRICE_OVERRIDE_NOT_ALLOWED', 'The price has changed. Refresh and try again.', 403);
      }
      if (Exact.milli(line.quantity) > Exact.milli(variant.stockQuantity)) {
        throw _refusal('INSUFFICIENT_STOCK', 'Only ${variant.stockQuantity} left of "${product.name}".', 409);
      }
      final total = Exact.lineTotal(Exact.paisa(variant.sellingPrice), Exact.milli(line.quantity));
      subtotal += total;
      items.add(SaleItem(productName: product.name, variantName: variant.name, unitName: product.unit.name, quantity: line.quantity, unitPrice: variant.sellingPrice, lineTotal: Exact.money(total)));
    }

    final grand = subtotal - Exact.paisa(draft.discountAmount) + Exact.paisa(draft.additionalCharge);
    if (grand != Exact.paisa(draft.grandTotal)) {
      throw _refusal('TOTALS_MISMATCH', 'The total has changed to ${Exact.money(grand)}. Check the bill and try again.');
    }

    final paid = draft.payments.fold(0, (sum, p) => sum + Exact.paisa(p.amount));
    final due = Exact.paisa(draft.dueAmount);
    if (paid + due != grand) throw _refusal('PAYMENT_MISMATCH', 'The payments do not add up to the total.');

    if (due > 0 && draft.customerPhone == null) {
      throw _refusal('DUE_REQUIRES_CUSTOMER', "Enter the customer's mobile number to sell on due.");
    }

    final invoiceNo = 'INV-${_nextId.toString().padLeft(6, '0')}';
    var customer = draft.customerPhone == null ? null : customers.findOrCreate(draft.customerPhone!, draft.customerName);
    if (customer != null) {
      customer = customers.recordSale(customer, totalPaisa: grand, paidPaisa: paid, duePaisa: due, invoiceNo: invoiceNo);
    }

    final cashReceived = draft.payments
        .where((p) => p.method == PaymentMethod.cash && p.receivedAmount != null)
        .fold(0, (sum, p) => sum + Exact.paisa(p.receivedAmount!) - Exact.paisa(p.amount));

    final sale = Sale(
      id: _nextId++,
      invoiceNo: invoiceNo,
      soldAt: DateTime(2026, 11, 12, 15, 30),
      subtotal: Exact.money(subtotal),
      discountAmount: draft.discountAmount,
      additionalCharge: draft.additionalCharge,
      grandTotal: Exact.money(grand),
      paidAmount: Exact.money(paid),
      dueAmount: Exact.money(due),
      changeAmount: Exact.money(cashReceived),
      grossProfit: showProfit ? '0.00' : null,
      customer: customer == null ? null : SaleCustomer(id: customer.id, name: customer.name, phone: customer.phone, currentDue: customer.currentDue),
      items: items,
      payments: [
        for (final p in draft.payments) SalePayment(type: 'sale', method: p.method, amount: Exact.money(Exact.paisa(p.amount)), transactionId: p.transactionId),
      ],
      invoiceUrl: 'https://dokani.test/i/token-${_nextId - 1}',
    );

    _sales.insert(0, sale);
    _byUuid[draft.clientUuid] = sale;
    return sale;
  }

  @override
  Future<Sale> sale(int id) async => _sales.firstWhere((s) => s.id == id);

  @override
  Future<Sale> voidSale(int id, String reason) async {
    voided.add('$id $reason');
    final index = _sales.indexWhere((s) => s.id == id);
    final old = _sales[index];
    return _sales[index] = Sale(
      id: old.id, invoiceNo: old.invoiceNo, soldAt: old.soldAt, voided: true, voidReason: reason,
      subtotal: old.subtotal, discountAmount: old.discountAmount, additionalCharge: old.additionalCharge,
      grandTotal: old.grandTotal, paidAmount: old.paidAmount, dueAmount: old.dueAmount, changeAmount: old.changeAmount,
      customer: old.customer, items: old.items, payments: old.payments, invoiceUrl: old.invoiceUrl,
    );
  }

  @override
  Future<Paged<Sale>> sales({int page = 1}) async =>
      Paged(items: page == 1 ? [..._sales] : [], currentPage: page, lastPage: 1, total: _sales.length);

  @override
  Future<DashboardData> dashboard() async {
    final live = _sales.where((s) => !s.voided).toList();
    final all = await customers.customers(hasDue: true);
    return DashboardData(
      sales: Exact.money(live.fold(0, (sum, s) => sum + Exact.paisa(s.grandTotal))),
      profit: showProfit ? '123.00' : null,
      orders: live.length,
      itemsSold: Exact.quantity(live.fold(0, (sum, s) => sum + s.items.fold(0, (n, i) => n + Exact.milli(i.quantity)))),
      totalCustomerDue: Exact.money(all.fold(0, (sum, c) => sum + Exact.paisa(c.currentDue))),
      recentSales: live.take(5).toList(),
    );
  }
}
