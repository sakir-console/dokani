import 'package:dokani/core/network/api_exception.dart';
import 'package:dokani/core/sync/sync_api.dart';
import 'package:dokani/features/catalog/data/models.dart';
import 'package:dokani/features/customers/data/customer_repository.dart';
import 'package:dokani/features/pos/data/sale_models.dart';

import 'sales_fakes.dart';

/// A product in the shape the sync endpoint sends it.
Map<String, dynamic> productJson(Product product) => {
      'id': product.id,
      'name': product.name,
      'has_variants': product.hasVariants,
      'unit': {
        'id': product.unit.id,
        'name': product.unit.name,
        'name_bn': product.unit.nameBn,
        'short_name': product.unit.shortName,
        'allows_decimal': product.unit.allowsDecimal,
        'is_built_in': product.unit.isBuiltIn,
      },
      'total_stock': product.totalStock,
      'low_stock_variants': product.lowStockVariants,
      'out_of_stock_variants': product.outOfStockVariants,
      'variants': [
        for (final variant in product.variants)
          {
            'id': variant.id,
            'name': variant.name,
            'sku': variant.sku,
            'purchase_price': variant.purchasePrice,
            'selling_price': variant.sellingPrice,
            'stock_quantity': variant.stockQuantity,
            'stock_status': switch (variant.stockStatus) {
              StockStatus.out => 'out',
              StockStatus.low => 'low',
              StockStatus.inStock => 'in_stock',
            },
            'barcodes': variant.barcodes,
          },
      ],
    };

/// The sync endpoints, in memory. Behaves like the server: a record is stored
/// once per client_uuid, and every pushed record gets its own answer.
class FakeSyncApi implements SyncApi {
  FakeSyncApi({List<Product> products = const [], List<Customer> customers = const [], this.sales, this.pageSize = 100})
      : products = [for (final product in products) productJson(product)],
        customers = [for (final customer in customers) customer.toJson()];

  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> customers;
  final List<int> deletedProductIds = [];

  /// When given, sales pushed here are saved through it, so a sale the
  /// server already has (from a request whose answer was lost) is a duplicate.
  final FakeSalesRepository? sales;
  final int pageSize;

  /// While false every request fails the way a phone without internet fails.
  bool online = true;

  /// The pull call with this number (1-based, counting every page) fails once.
  int? failPullCall;

  /// Records the server refuses, by client_uuid.
  final Map<String, ({String code, String message})> reject = {};

  final List<String> pulls = [];
  final List<({int sales, int dueCollections})> pushes = [];

  /// Payloads the server stored, once each, in the order they arrived.
  final List<Map<String, dynamic>> storedSales = [];
  final List<Map<String, dynamic>> storedDueCollections = [];
  final Map<String, Map<String, dynamic>> _answers = {};
  int _round = 0;
  int _nextSaleId = 9000;

  void _net() {
    if (!online) throw const ApiException(kind: ApiErrorKind.network);
  }

  @override
  Future<PullPage> pull(String what, {String? since, int page = 1}) async {
    _net();
    pulls.add('$what since=$since page=$page');
    if (failPullCall == pulls.length) {
      failPullCall = null;
      throw const ApiException(kind: ApiErrorKind.timeout);
    }
    if (page == 1) _round++;

    final rows = what == 'products' ? products : customers;
    final lastPage = rows.isEmpty ? 1 : (rows.length / pageSize).ceil();
    return PullPage(
      rows: rows.skip((page - 1) * pageSize).take(pageSize).toList(),
      deletedIds: what == 'products' && page == 1 ? [...deletedProductIds] : const [],
      lastPage: lastPage,
      cursor: 'cursor-$_round',
    );
  }

  @override
  Future<({List<PushResult> sales, List<PushResult> dueCollections})> push({
    required String deviceUuid,
    List<Map<String, dynamic>> sales = const [],
    List<Map<String, dynamic>> dueCollections = const [],
  }) async {
    _net();
    pushes.add((sales: sales.length, dueCollections: dueCollections.length));

    PushResult answer(Map<String, dynamic> payload, Map<String, dynamic> Function() store) {
      final uuid = payload['client_uuid'] as String;
      if (reject[uuid] case final refusal?) {
        return PushResult(clientUuid: uuid, status: 'failed', code: refusal.code, message: refusal.message);
      }
      if (_answers[uuid] case final earlier?) return PushResult(clientUuid: uuid, status: 'duplicate', server: earlier);
      return PushResult(clientUuid: uuid, status: 'created', server: _answers[uuid] = store());
    }

    return (
      sales: [
        for (final payload in sales)
          answer(payload, () {
            // Saved earlier by a direct request whose answer never arrived?
            final known = this.sales?.byUuid(payload['client_uuid'] as String);
            if (known != null) return {'id': known.id, 'invoice_no': known.invoiceNo, 'invoice_url': known.invoiceUrl};

            storedSales.add(payload);
            final id = _nextSaleId++;
            return {'id': id, 'invoice_no': 'INV-$id', 'invoice_url': 'https://dokani.test/i/token-$id'};
          }),
      ],
      dueCollections: [
        for (final payload in dueCollections)
          answer(payload, () {
            storedDueCollections.add(payload);
            return {'customer_id': payload['customer_id'], 'current_due': '0.00'};
          }),
      ],
    );
  }
}

/// A sale draft for one unit of one variant, paid in full in cash.
SaleDraft cashDraft({required String uuid, int variantId = 100, String price = '60.00', String quantity = '1'}) => SaleDraft(
      clientUuid: uuid,
      items: [SaleLineDraft(variantId: variantId, quantity: quantity, unitPrice: price)],
      grandTotal: price,
      payments: [PaymentDraft(method: PaymentMethod.cash, amount: price, receivedAmount: price)],
      dueAmount: '0.00',
    );
