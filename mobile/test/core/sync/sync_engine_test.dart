import 'package:dokani/core/database/local_database.dart';
import 'package:dokani/core/sync/sync_api.dart';
import 'package:dokani/core/sync/sync_engine.dart';
import 'package:dokani/features/customers/data/customer_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/catalog_fakes.dart';
import '../../support/sync_fakes.dart';

void main() {
  late LocalDatabase database;

  setUp(() => database = LocalDatabase.inMemory());
  tearDown(() => database.close());

  ProviderContainer containerFor(FakeSyncApi api) {
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(database),
        syncApiProvider.overrideWithValue(api),
        deviceUuidProvider.overrideWithValue('device-1'),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> queueSale(String uuid) => database.enqueue(
        clientUuid: uuid,
        kind: 'sale',
        payload: cashDraft(uuid: uuid).toJson(),
        display: {'invoice_no': 'OFF-$uuid', 'grand_total': '60.00'},
      );

  group('pulling', () {
    test('the first sync downloads every page; the next one asks only for changes', () async {
      final api = FakeSyncApi(
        products: [for (var i = 1; i <= 5; i++) makeProduct(id: i, name: 'Product $i')],
        customers: const [Customer(id: 1, name: 'Karim', phone: '01811111111', currentDue: '40.00')],
        pageSize: 2,
      );
      final container = containerFor(api);

      await container.read(syncEngineProvider.notifier).sync();

      expect(await database.productCount(), 5);
      expect((await database.customerByPhone('01811111111'))?['name'], 'Karim');
      expect(api.pulls, [
        'products since=null page=1',
        'products since=null page=2',
        'products since=null page=3',
        'customers since=null page=1',
      ]);
      expect(container.read(syncEngineProvider).lastSyncedAt, isNotNull);
      expect(container.read(syncEngineProvider).lastError, isNull);

      api.pulls.clear();
      await container.read(syncEngineProvider.notifier).sync();

      // The position saved is the one issued when the first round began.
      expect(api.pulls.first, 'products since=cursor-1 page=1');
      expect(api.pulls, contains('customers since=cursor-2 page=1'));
    });

    test('a download interrupted half way starts that round again next time', () async {
      final api = FakeSyncApi(products: [for (var i = 1; i <= 4; i++) makeProduct(id: i, name: 'Product $i')], pageSize: 2)
        ..failPullCall = 2;
      final container = containerFor(api);

      await container.read(syncEngineProvider.notifier).sync();

      expect(container.read(syncEngineProvider).offline, isTrue);
      expect(container.read(syncEngineProvider).lastSyncedAt, isNull);
      expect(await database.state('products_cursor'), isNull, reason: 'a half-finished round must not be marked as done');

      api.pulls.clear();
      await container.read(syncEngineProvider.notifier).sync();

      expect(api.pulls.take(2), ['products since=null page=1', 'products since=null page=2']);
      expect(await database.productCount(), 4);
      expect(await database.state('products_cursor'), isNotNull);
    });

    test('products deleted on the server disappear from the phone', () async {
      final api = FakeSyncApi(products: [makeProduct(id: 1, name: 'Soap'), makeProduct(id: 2, name: 'Salt')]);
      final container = containerFor(api);
      await container.read(syncEngineProvider.notifier).sync();

      api.products.removeWhere((p) => p['id'] == 2);
      api.deletedProductIds.add(2);
      await container.read(syncEngineProvider.notifier).sync();

      expect((await database.searchProducts('')).map((p) => p['name']), ['Soap']);
    });
  });

  group('pushing', () {
    test('a queued sale is sent once and marked as confirmed', () async {
      final api = FakeSyncApi();
      final container = containerFor(api);
      await queueSale('a');

      await container.read(syncEngineProvider.notifier).sync();
      await container.read(syncEngineProvider.notifier).sync();

      expect(api.storedSales, hasLength(1));
      expect(api.pushes, [(sales: 1, dueCollections: 0)], reason: 'a confirmed record is not sent again');
      expect((await database.entry('a'))?.status, 'synced');
      expect(await database.unsynced(), isEmpty);
    });

    test('with no connection nothing is lost: records stay queued and are sent later', () async {
      final api = FakeSyncApi()..online = false;
      final container = containerFor(api);
      await queueSale('a');
      await queueSale('b');

      await container.read(syncEngineProvider.notifier).sync();

      final status = container.read(syncEngineProvider);
      expect(status.offline, isTrue);
      expect(status.syncing, isFalse);
      expect((await database.unsynced()).map((e) => e.status), ['pending', 'pending']);
      expect((await database.entry('a'))?.attempts, 1);

      api.online = true;
      await container.read(syncEngineProvider.notifier).sync();

      expect(api.storedSales.map((s) => s['client_uuid']), ['a', 'b']);
      expect(await database.unsynced(), isEmpty);
      expect(container.read(syncEngineProvider).offline, isFalse);
    });

    test('a sale the server already has is confirmed, not recorded twice', () async {
      final api = FakeSyncApi();
      final container = containerFor(api);
      await queueSale('a');
      await container.read(syncEngineProvider.notifier).sync();

      // The same record turns up again (say the phone never saw the first answer).
      await database.enqueue(clientUuid: 'a2', kind: 'sale', payload: cashDraft(uuid: 'a').toJson(), display: const {});
      await container.read(syncEngineProvider.notifier).sync();

      expect(api.storedSales, hasLength(1));
    });

    test('a record the server refuses is kept, with the reason, and tried again', () async {
      final api = FakeSyncApi()..reject['bad'] = (code: 'TOTALS_MISMATCH', message: 'The total does not add up.');
      final container = containerFor(api);
      await queueSale('good');
      await queueSale('bad');

      await container.read(syncEngineProvider.notifier).sync();

      final bad = await database.entry('bad');
      expect(bad?.status, 'failed');
      expect(bad?.errorCode, 'TOTALS_MISMATCH');
      expect(bad?.errorMessage, 'The total does not add up.');
      expect((await database.entry('good'))?.status, 'synced', reason: 'one bad record does not block the others');
      expect(api.pushes, hasLength(1), reason: 'a refused record is not retried in a loop within one sync');

      // The cause is fixed on the server: the next sync gets it through.
      api.reject.clear();
      await container.read(syncEngineProvider.notifier).sync();

      expect((await database.entry('bad'))?.status, 'synced');
      expect(api.storedSales.map((s) => s['client_uuid']), ['good', 'bad']);
    });

    test('a long queue goes up in batches of 50, sales and due collections together', () async {
      final api = FakeSyncApi();
      final container = containerFor(api);
      for (var i = 0; i < 119; i++) {
        await queueSale('sale-$i');
      }
      await database.enqueue(
        clientUuid: 'due-1',
        kind: 'due_collection',
        payload: {'client_uuid': 'due-1', 'customer_id': 5, 'amount': '20.00', 'method': 'cash'},
        display: const {},
      );

      await container.read(syncEngineProvider.notifier).sync();

      expect(api.pushes, [(sales: 50, dueCollections: 0), (sales: 50, dueCollections: 0), (sales: 19, dueCollections: 1)]);
      expect(api.storedSales, hasLength(119));
      expect(api.storedDueCollections.single['customer_id'], 5);
      expect(await database.unsynced(), isEmpty);
    });

    test('two sync requests at the same moment run as one', () async {
      final api = FakeSyncApi();
      final container = containerFor(api);
      await queueSale('a');

      final engine = container.read(syncEngineProvider.notifier);
      await Future.wait([engine.sync(), engine.sync(), engine.sync()]);

      expect(api.pushes, hasLength(1));
      expect(api.storedSales, hasLength(1));
    });

    test('sales are sent before stock is fetched', () async {
      final api = FakeSyncApi(products: [makeProduct()]);
      final container = containerFor(api);
      await queueSale('a');
      final order = <String>[];
      // Record the order through the fake's own logs.
      await container.read(syncEngineProvider.notifier).sync();
      if (api.pushes.isNotEmpty) order.add('push');
      if (api.pulls.isNotEmpty) order.add('pull');

      expect(order, ['push', 'pull']);
      expect(api.storedSales, hasLength(1));
      expect(await database.productCount(), 1);
    });
  });

  test('signed out, sync does nothing', () async {
    final api = FakeSyncApi();
    final container = ProviderContainer(
      overrides: [localDatabaseProvider.overrideWithValue(null), syncApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container.read(syncEngineProvider.notifier).sync();

    expect(api.pulls, isEmpty);
    expect(api.pushes, isEmpty);
  });
}
