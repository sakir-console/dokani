import 'dart:convert';

import 'package:dokani/core/database/local_database.dart';
import 'package:dokani/core/network/api_exception.dart';
import 'package:dokani/core/sync/sync_api.dart';
import 'package:dokani/core/sync/sync_engine.dart';
import 'package:dokani/features/customers/data/customer_repository.dart';
import 'package:dokani/features/pos/application/sale_submitter.dart';
import 'package:dokani/features/pos/data/sale_models.dart';
import 'package:dokani/features/pos/data/sales_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/catalog_fakes.dart';
import '../../support/sales_fakes.dart';
import '../../support/sync_fakes.dart';

const _display = SaleDisplay(lines: ['Miniket Rice'], subtotal: '60.00', paid: '60.00', change: '0.00');

void main() {
  late LocalDatabase database;
  late FakeCatalogRepository catalog;
  late FakeCustomerRepository customers;
  late FakeSalesRepository sales;
  late FakeSyncApi api;
  late ProviderContainer container;

  const karim = Customer(id: 5, name: 'Karim', phone: '01811111111', currentDue: '100.00');

  setUp(() async {
    database = LocalDatabase.inMemory();
    catalog = FakeCatalogRepository(products: [makeProduct(variants: [makeVariant(stock: '10.000')])]);
    customers = FakeCustomerRepository([karim]);
    sales = FakeSalesRepository(catalog: catalog, customers: customers);
    api = FakeSyncApi(sales: sales);
    container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(database),
        syncApiProvider.overrideWithValue(api),
        deviceUuidProvider.overrideWithValue('device-1'),
        salesRepositoryProvider.overrideWithValue(sales),
        customerRepositoryProvider.overrideWithValue(customers),
      ],
    );
    // What the phone has from its last sync.
    await database.upsertProducts([productJson(catalog.all.single)]);
    await database.upsertCustomers([karim.toJson()]);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<String> localStock() async => '${((await database.searchProducts('')).single['variants'] as List).single['stock_quantity']}';

  /// Lets the background sync started by the submitter finish.
  Future<void> settle() => container.read(syncEngineProvider.notifier).sync();

  group('a sale', () {
    test('with a connection is confirmed at once, and leaves nothing waiting', () async {
      final result = await container.read(saleSubmitterProvider).submit(cashDraft(uuid: 'a'), _display);

      expect(result.isPending, isFalse);
      expect(result.sale?.invoiceNo, 'INV-000001');
      expect(await database.unsynced(), isEmpty);
      expect((await database.entry('a'))?.status, 'synced');
      expect(await localStock(), '9.000');
    });

    test('without a connection is saved on the phone and sent later, exactly once', () async {
      sales.offline = true;
      api.online = false;

      final result = await container.read(saleSubmitterProvider).submit(cashDraft(uuid: 'a'), _display);
      await settle();

      expect(result.isPending, isTrue);
      final entry = (await database.unsynced()).single;
      expect(entry.status, 'pending');
      final payload = jsonDecode(entry.payload) as Map;
      expect(payload['client_uuid'], 'a');
      expect(payload['offline_ref'], startsWith('OFF-'));
      expect(DateTime.parse(payload['sold_at'] as String).isUtc, isTrue);
      expect(await localStock(), '9.000', reason: 'this phone stops offering what it just sold');

      // The phone shows the sale from what it stored, before any server has seen it.
      final shown = Sale.fromJson(outboxDisplay(entry));
      expect(shown.invoiceNo, payload['offline_ref']);
      expect(shown.items.single.title, 'Miniket Rice');
      expect(shown.grandTotal, '60.00');
      expect(shown.invoiceUrl, isNull);

      api.online = true;
      await settle();
      await settle();

      expect(api.storedSales, hasLength(1));
      expect(await database.unsynced(), isEmpty);
      expect(outboxServer((await database.entry('a'))!)['invoice_no'], isNotNull);
    });

    test('whose answer is lost on the way back is not recorded twice', () async {
      sales.loseNextResponse = true;

      final result = await container.read(saleSubmitterProvider).submit(cashDraft(uuid: 'a'), _display);
      await settle();

      expect(result.isPending, isTrue, reason: 'the phone cannot know the server saved it');
      expect(sales.all, hasLength(1));
      expect(api.storedSales, isEmpty, reason: 'the retry was recognised by its id');
      final entry = await database.entry('a');
      expect(entry?.status, 'synced');
      expect(outboxServer(entry!)['id'], sales.all.single.id);
    });

    test('the server refuses is not queued: the cashier sees why and stock is put back', () async {
      final draft = cashDraft(uuid: 'a', quantity: '11');

      await expectLater(
        container.read(saleSubmitterProvider).submit(draft, _display),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INSUFFICIENT_STOCK')),
      );

      expect(await database.entry('a'), isNull);
      expect(await localStock(), '10.000');
    });

    for (final failure in const [
      ApiException(kind: ApiErrorKind.server, statusCode: 500),
      ApiException(kind: ApiErrorKind.server, statusCode: 429),
      ApiException(kind: ApiErrorKind.unauthenticated, statusCode: 401),
      ApiException(kind: ApiErrorKind.timeout),
      ApiException(kind: ApiErrorKind.unknown),
    ]) {
      test('is kept when the request fails with ${failure.kind.name} ${failure.statusCode ?? ''}', () async {
        sales.failNext = failure;
        api.online = false;

        final result = await container.read(saleSubmitterProvider).submit(cashDraft(uuid: 'a'), _display);
        await settle();

        expect(result.isPending, isTrue);
        expect((await database.unsynced()).single.clientUuid, 'a');
      });
    }

    test('on due made offline raises what this phone shows the customer owes', () async {
      sales.offline = true;
      api.online = false;
      const draft = SaleDraft(
        clientUuid: 'a',
        items: [SaleLineDraft(variantId: 100, quantity: '1', unitPrice: '60.00')],
        grandTotal: '60.00',
        payments: [PaymentDraft(method: PaymentMethod.cash, amount: '20.00', receivedAmount: '20.00')],
        dueAmount: '40.00',
        customerPhone: '01811111111',
      );

      await container.read(saleSubmitterProvider).submit(
            draft,
            const SaleDisplay(lines: ['Miniket Rice'], subtotal: '60.00', paid: '20.00', change: '0.00', customerName: 'Karim'),
          );
      await settle();

      expect((await database.customerByPhone('01811111111'))?['current_due'], '140.00');
      final shown = Sale.fromJson(outboxDisplay((await database.unsynced()).single));
      expect(shown.customer?.name, 'Karim');
      expect(shown.dueAmount, '40.00');
    });

    test('refused later can be removed from the phone on purpose, restoring its stock', () async {
      sales.offline = true;
      api
        ..online = true
        ..reject['a'] = (code: 'PRODUCT_NOT_FOUND', message: 'This product no longer exists.');

      await container.read(saleSubmitterProvider).submit(cashDraft(uuid: 'a'), _display);
      await settle();
      await settle();

      final failed = (await database.unsynced()).single;
      expect(failed.status, 'failed');
      expect(await localStock(), '9.000');

      await container.read(saleSubmitterProvider).discardFailed(failed);

      expect(await database.unsynced(), isEmpty);
      expect(await localStock(), '10.000');
    });

    test('still waiting cannot be removed', () async {
      sales.offline = true;
      api.online = false;
      await container.read(saleSubmitterProvider).submit(cashDraft(uuid: 'a'), _display);
      await settle();

      await container.read(saleSubmitterProvider).discardFailed((await database.unsynced()).single);

      expect(await database.unsynced(), hasLength(1));
    });
  });

  group('a due collection', () {
    Future<({Customer customer, bool pending})> collect(String amount) => container.read(saleSubmitterProvider).collectDue(
          customer: karim,
          clientUuid: 'd',
          amount: amount,
          method: PaymentMethod.bkash,
          transactionId: 'TX1',
        );

    test('with a connection is confirmed at once', () async {
      final result = await collect('30.00');

      expect(result.pending, isFalse);
      expect(result.customer.currentDue, '70.00');
      expect(await database.unsynced(), isEmpty);
      expect((await database.customerById(5))?['current_due'], '70.00');
    });

    test('without a connection is saved on the phone, shown in the balance, and sent later', () async {
      customers.offline = true;
      api.online = false;

      final result = await collect('30.00');
      await settle();

      expect(result.pending, isTrue);
      expect(result.customer.currentDue, '70.00');
      expect((await database.customerById(5))?['current_due'], '70.00');
      final payload = jsonDecode((await database.unsynced()).single.payload) as Map;
      expect(payload, containsPair('customer_id', 5));
      expect(payload, containsPair('amount', '30.00'));
      expect(payload, containsPair('method', 'bkash'));
      expect(payload, containsPair('transaction_id', 'TX1'));

      api.online = true;
      await settle();
      await settle();

      expect(api.storedDueCollections, hasLength(1));
      expect(await database.unsynced(), isEmpty);
    });

    test('the server refuses is not queued', () async {
      await expectLater(collect('500.00'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'AMOUNT_EXCEEDS_DUE')));

      expect(await database.entry('d'), isNull);
    });
  });

  test('with no local database the sale goes straight to the server', () async {
    final plain = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(null),
        salesRepositoryProvider.overrideWithValue(sales),
        customerRepositoryProvider.overrideWithValue(customers),
      ],
    );
    addTearDown(plain.dispose);

    final result = await plain.read(saleSubmitterProvider).submit(cashDraft(uuid: 'z'), _display);

    expect(result.sale?.id, isNotNull);
  });
}
