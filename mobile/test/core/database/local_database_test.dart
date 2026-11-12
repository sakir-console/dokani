import 'package:dokani/core/database/local_database.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> productJson(int id, String name, {List<Map<String, dynamic>>? variants}) => {
      'id': id,
      'name': name,
      'has_variants': (variants?.length ?? 1) > 1,
      'unit': {'id': 1, 'name': 'Piece', 'name_bn': 'পিস', 'short_name': 'pc', 'allows_decimal': false, 'is_built_in': true},
      'total_stock': '10.000',
      'low_stock_variants': 0,
      'out_of_stock_variants': 0,
      'variants': variants ??
          [
            {'id': id * 10, 'name': null, 'purchase_price': '50.00', 'selling_price': '60.00', 'stock_quantity': '10.000', 'stock_status': 'in', 'barcodes': <String>[]},
          ],
    };

Map<String, dynamic> variantJson(int id, String? name, String stock, List<String> barcodes) =>
    {'id': id, 'name': name, 'purchase_price': '50.00', 'selling_price': '60.00', 'stock_quantity': stock, 'stock_status': 'in', 'barcodes': barcodes};

void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase.inMemory());
  tearDown(() => db.close());

  group('products and barcodes', () {
    test('stores products and finds them by name, in any letter case, in Bangla too', () async {
      await db.upsertProducts([productJson(1, 'Lux Soap'), productJson(2, 'Lifebuoy Soap'), productJson(3, 'মিনিকেট চাল')]);

      expect((await db.searchProducts('soap')).map((p) => p['name']), ['Lifebuoy Soap', 'Lux Soap']);
      expect((await db.searchProducts('LUX')).single['name'], 'Lux Soap');
      expect((await db.searchProducts('চাল')).single['name'], 'মিনিকেট চাল');
      expect(await db.searchProducts(''), hasLength(3));
      expect(await db.searchProducts('100%'), isEmpty, reason: 'Wildcards typed by the user are literal.');
      expect(await db.productCount(), 3);
    });

    test('a barcode resolves to its exact variant, offline', () async {
      await db.upsertProducts([
        productJson(4, 'Polo', variants: [variantJson(40, 'S', '4.000', ['TS-S']), variantJson(41, 'M', '6.000', ['TS-M', 'TS-M-ALT'])]),
      ]);

      final match = await db.productByBarcode(' TS-M-ALT ');
      expect(match!.variantId, 41);
      expect(match.product['name'], 'Polo');
      expect(await db.productByBarcode('UNKNOWN'), isNull);

      // Searching by a barcode also finds the product.
      expect((await db.searchProducts('TS-S')).single['name'], 'Polo');
    });

    test('an updated product replaces the old copy and its barcodes', () async {
      await db.upsertProducts([productJson(1, 'Old', variants: [variantJson(10, null, '5.000', ['OLD-CODE'])])]);
      await db.upsertProducts([productJson(1, 'New', variants: [variantJson(10, null, '7.000', ['NEW-CODE'])])]);

      expect(await db.productCount(), 1);
      expect((await db.searchProducts('')).single['name'], 'New');
      expect(await db.productByBarcode('OLD-CODE'), isNull, reason: 'A barcode removed on the server must stop working here.');
      expect((await db.productByBarcode('NEW-CODE'))!.variantId, 10);
    });

    test('deleted products disappear with their barcodes', () async {
      await db.upsertProducts([productJson(1, 'Keep'), productJson(2, 'Gone', variants: [variantJson(20, null, '1.000', ['GONE'])])]);
      await db.deleteProducts([2, 999]);

      expect((await db.searchProducts('')).map((p) => p['name']), ['Keep']);
      expect(await db.productByBarcode('GONE'), isNull);
    });

    test('a sale on this phone lowers the stock it shows', () async {
      await db.upsertProducts([
        productJson(4, 'Polo', variants: [variantJson(40, 'S', '4.000', []), variantJson(41, 'M', '6.000', [])]),
      ]);

      await db.adjustLocalStock(41, -2500);

      final product = (await db.searchProducts('polo')).single;
      final variants = (product['variants'] as List).cast<Map<String, dynamic>>();
      expect(variants[0]['stock_quantity'], '4.000');
      expect(variants[1]['stock_quantity'], '3.500');
      expect(product['total_stock'], '7.500');
    });

    test('search is paged', () async {
      await db.upsertProducts([for (var i = 1; i <= 7; i++) productJson(i, 'Item $i')]);

      expect(await db.searchProducts('', limit: 3), hasLength(3));
      expect((await db.searchProducts('', limit: 3, offset: 6)).single['name'], 'Item 7');
    });
  });

  group('customers', () {
    test('are found by phone and follow updates and deletions', () async {
      await db.upsertCustomers([
        {'id': 1, 'name': 'Karim Mia', 'phone': '01812345678', 'current_due': '150.00'},
        {'id': 2, 'name': 'Abdul', 'phone': '01912345678', 'current_due': '0.00'},
      ]);

      expect((await db.customerByPhone('01812345678'))!['name'], 'Karim Mia');
      expect(await db.customerByPhone('01700000000'), isNull);

      await db.upsertCustomers([{'id': 1, 'name': 'Karim Mia', 'phone': '01812345678', 'current_due': '550.00'}]);
      expect((await db.customerByPhone('01812345678'))!['current_due'], '550.00');

      await db.deleteCustomers([1]);
      expect(await db.customerByPhone('01812345678'), isNull);
    });
  });

  group('outbox', () {
    Future<void> queue(String uuid, {String kind = 'sale'}) =>
        db.enqueue(clientUuid: uuid, kind: kind, payload: {'client_uuid': uuid, 'grand_total': '60.00'}, display: {'title': 'x'});

    test('keeps records in the order they were made until the server confirms them', () async {
      await queue('a');
      await queue('b', kind: 'due_collection');
      await queue('c');

      expect((await db.unsynced()).map((e) => e.clientUuid), ['a', 'b', 'c']);
      expect((await db.unsynced()).first.status, 'pending');

      await db.markSynced('a', {'id': 9, 'invoice_no': 'INV-000009'});
      expect((await db.unsynced()).map((e) => e.clientUuid), ['b', 'c']);
      expect((await db.entry('a'))!.server, contains('INV-000009'));
    });

    test('queuing the same record twice keeps one row', () async {
      await queue('same');
      await queue('same');

      expect(await db.unsynced(), hasLength(1));
    });

    test('a failed record stays in the queue with its reason and is retried', () async {
      await queue('bad');
      await db.countAttempt(['bad']);
      await db.markFailed('bad', 'TOTALS_MISMATCH', 'The total has changed.');

      final entry = (await db.unsynced()).single;
      expect(entry.status, 'failed');
      expect(entry.errorCode, 'TOTALS_MISMATCH');
      expect(entry.attempts, 1);

      // Later it goes through: the error is cleared.
      await db.markSynced('bad', {'id': 1});
      final synced = await db.entry('bad');
      expect(synced!.status, 'synced');
      expect(synced.errorCode, isNull);
    });

    test('pruning removes only old, confirmed records', () async {
      final old = DateTime.now().subtract(const Duration(days: 30));
      await db.enqueue(clientUuid: 'old-synced', kind: 'sale', payload: {}, display: {}, createdAt: old);
      await db.enqueue(clientUuid: 'old-pending', kind: 'sale', payload: {}, display: {}, createdAt: old);
      await db.enqueue(clientUuid: 'old-failed', kind: 'sale', payload: {}, display: {}, createdAt: old);
      await queue('new-synced');
      await db.markSynced('old-synced', {});
      await db.markSynced('new-synced', {});
      await db.markFailed('old-failed', 'X', 'x');

      await db.pruneSynced();

      expect(await db.entry('old-synced'), isNull);
      expect(await db.entry('new-synced'), isNotNull);
      expect(await db.entry('old-pending'), isNotNull, reason: 'An unsynced sale is never deleted, however old.');
      expect(await db.entry('old-failed'), isNotNull);
    });

    test('the unsynced list updates live', () async {
      final seen = <int>[];
      final subscription = db.watchUnsynced().listen((entries) => seen.add(entries.length));
      Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

      await settle();
      await queue('a');
      await queue('b');
      await settle();
      await db.markSynced('a', {});
      await settle();
      await subscription.cancel();

      // Quick changes may arrive together; what matters is that each state is reached in order.
      expect(seen.first, 0);
      expect(seen, contains(2));
      expect(seen.last, 1);
    });
  });

  test('sync positions are remembered', () async {
    expect(await db.state('products_cursor'), isNull);
    await db.setState('products_cursor', '2026-03-10T06:00:00Z');
    await db.setState('products_cursor', '2026-03-11T06:00:00Z');
    expect(await db.state('products_cursor'), '2026-03-11T06:00:00Z');
  });
}
