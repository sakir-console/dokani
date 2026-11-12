// A live check of the phone's sync code against a running Dokani server.
//
// Not part of `flutter test` (it needs a server). Run it with:
//
//   cd backend && php artisan migrate:fresh --seed && php artisan serve --port=8010
//   cd mobile  && flutter test tool/sync_contract_test.dart
//
// DOKANI_API overrides the address (default http://127.0.0.1:8010/api/v1).
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dokani/core/database/local_database.dart';
import 'package:dokani/core/money/exact.dart';
import 'package:dokani/core/network/api_client.dart';
import 'package:dokani/core/sync/sync_api.dart';
import 'package:dokani/core/sync/sync_engine.dart';
import 'package:dokani/features/customers/data/customer_repository.dart';
import 'package:dokani/features/notifications/data/notification_repository.dart';
import 'package:dokani/features/pos/application/pos_catalog.dart';
import 'package:dokani/features/pos/application/sale_submitter.dart';
import 'package:dokani/features/pos/data/sale_models.dart';
import 'package:dokani/features/pos/data/sales_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final api = Platform.environment['DOKANI_API'] ?? 'http://127.0.0.1:8010/api/v1';

  test('offline sales made on the phone reach a real server once, and stock comes back right', () async {
    final phone = '017${10000000 + Random().nextInt(89999999)}';
    final setup = Dio(BaseOptions(baseUrl: api, headers: {'Accept': 'application/json'}));

    final registered = await setup.post<Map<String, dynamic>>('/auth/register', data: {
      'shop_name': 'Contract Store',
      'owner_name': 'Contract Owner',
      'phone': phone,
      'password': 'secret-pass',
      'shop_type': 'grocery',
      'device_name': 'contract-check',
    });
    final token = (registered.data!['data'] as Map)['token'] as String;

    Dio dio(String baseUrl) => Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 3),
            headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
          ),
        );
    final online = dio(api);

    final units = await online.get<Map<String, dynamic>>('/units');
    final unitId = ((units.data!['data'] as List).first as Map)['id'] as int;
    final created = await online.post<Map<String, dynamic>>('/products', data: {
      'name': 'Contract Soap',
      'unit_id': unitId,
      'variants': [
        {'purchase_price': '50', 'selling_price': '60', 'stock_quantity': '10', 'barcodes': ['CONTRACT-1']},
      ],
    });
    final variantId = ((((created.data!['data'] as Map)['variants'] as List).first) as Map)['id'] as int;

    final database = LocalDatabase.inMemory();
    addTearDown(database.close);

    ProviderContainer container(Dio dio) {
      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(dio),
          localDatabaseProvider.overrideWithValue(database),
          deviceUuidProvider.overrideWithValue(Exact.uuid()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    final connected = container(online);
    // Nothing listens on port 9: every request fails the way it does with no internet.
    final cutOff = container(dio('http://127.0.0.1:9/api/v1'));
    Future<void> sync() => connected.read(syncEngineProvider.notifier).sync();
    Future<String> localStock() async =>
        '${((await database.productByBarcode('CONTRACT-1'))!.product['variants'] as List).first['stock_quantity']}';

    // 1. First sync: the phone gets the product, and the app's own models read it.
    await sync();
    expect(connected.read(syncEngineProvider).lastError, isNull);
    final match = await connected.read(posCatalogProvider).lookupBarcode('CONTRACT-1');
    expect(match?.variantId, variantId);
    expect(match?.product.name, 'Contract Soap');
    expect((await connected.read(posCatalogProvider).search('soap')).items.single.variants.single.sellingPrice, '60.00');

    // 2. Two sales with no connection: one in cash, one on due to a new customer.
    SaleDraft draft({required String quantity, required String total, String paid = '0', String? customerPhone, String? name}) => SaleDraft(
          clientUuid: Exact.uuid(),
          items: [SaleLineDraft(variantId: variantId, quantity: quantity, unitPrice: '60.00')],
          grandTotal: total,
          payments: [if (paid != '0') PaymentDraft(method: PaymentMethod.cash, amount: paid, receivedAmount: paid)],
          dueAmount: Exact.money(Exact.paisa(total) - Exact.paisa(paid)),
          customerPhone: customerPhone,
          customerName: name,
        );
    SaleDisplay display(String total, String paid) => SaleDisplay(lines: const ['Contract Soap'], subtotal: total, paid: paid, change: '0.00');

    final cash = await cutOff.read(saleSubmitterProvider).submit(draft(quantity: '2', total: '120.00', paid: '120.00'), display('120.00', '120.00'));
    final onDue = await cutOff
        .read(saleSubmitterProvider)
        .submit(draft(quantity: '1', total: '60.00', customerPhone: '01811112222', name: 'Karim Contract'), display('60.00', '0.00'));
    await cutOff.read(syncEngineProvider.notifier).sync();

    expect(cash.isPending, isTrue);
    expect(onDue.isPending, isTrue);
    expect(await database.unsynced(), hasLength(2));
    expect(await localStock(), '7.000');

    // 3. The connection returns: both arrive, with real invoice numbers.
    await sync();
    expect(await database.unsynced(), isEmpty, reason: '${(await database.unsynced()).map((e) => '${e.errorCode} ${e.errorMessage}').toList()}');
    final confirmed = outboxServer((await database.entry(cash.pendingUuid!))!);
    expect(confirmed['invoice_no'], isNotNull);
    expect(confirmed['id'], isA<int>());

    Future<List<Sale>> serverSales() async => (await connected.read(salesRepositoryProvider).sales()).items;
    expect(await serverSales(), hasLength(2));
    expect(await localStock(), '7.000', reason: 'the server took the same 3 pieces off its stock');

    final karim = await database.customerByPhone('01811112222');
    expect(karim?['name'], 'Karim Contract');
    expect(karim?['current_due'], '60.00');

    // 4. Sending the same sale again is answered "duplicate" and records nothing.
    final again = await connected.read(syncApiProvider).push(
      deviceUuid: Exact.uuid(),
      sales: [
        {...draft(quantity: '2', total: '120.00', paid: '120.00').toJson(), 'client_uuid': cash.pendingUuid},
      ],
    );
    expect(again.sales.single.status, 'duplicate');
    expect(again.sales.single.server['id'], confirmed['id']);
    await sync();
    expect(await serverSales(), hasLength(2));

    // 5. A payment against the due, taken with no connection.
    final collected = await cutOff.read(saleSubmitterProvider).collectDue(
          customer: Customer.fromJson(karim!),
          clientUuid: Exact.uuid(),
          amount: '25',
          method: PaymentMethod.bkash,
          transactionId: 'TX-CONTRACT',
        );
    await cutOff.read(syncEngineProvider.notifier).sync();
    expect(collected.pending, isTrue);
    expect(collected.customer.currentDue, '35.00');

    await sync();
    expect(await database.unsynced(), isEmpty);
    expect((await database.customerByPhone('01811112222'))?['current_due'], '35.00');
    expect((await connected.read(customerRepositoryProvider).lookup('01811112222'))?.currentDue, '35.00');

    // 6. Selling more than the stock offline is accepted (the goods left the shop) and flagged.
    final oversold = await cutOff.read(saleSubmitterProvider).submit(draft(quantity: '9', total: '540.00', paid: '540.00'), display('540.00', '540.00'));
    await cutOff.read(syncEngineProvider.notifier).sync();
    await sync();
    expect((await database.entry(oversold.pendingUuid!))?.status, 'synced');
    expect(await localStock(), '-2.000');
    final notices = await connected.read(notificationRepositoryProvider).latest();
    expect(notices.unread, 1);
    expect(notices.items.single.type, 'stock_conflict');
    expect(notices.items.single.saleId, outboxServer((await database.entry(oversold.pendingUuid!))!)['id']);
    await connected.read(notificationRepositoryProvider).markAllRead();
    expect((await connected.read(notificationRepositoryProvider).latest()).unread, 0);

    // 7. A record the server cannot accept stays on the phone with the server's reason.
    final bad = Exact.uuid();
    await database.enqueue(
      clientUuid: bad,
      kind: 'sale',
      payload: {
        ...SaleDraft(
          clientUuid: bad,
          items: const [SaleLineDraft(variantId: 987654321, quantity: '1', unitPrice: '60.00')],
          grandTotal: '60.00',
          payments: const [PaymentDraft(method: PaymentMethod.cash, amount: '60.00')],
          dueAmount: '0.00',
        ).toJson(),
      },
      display: const {},
    );
    await sync();
    final refused = await database.entry(bad);
    expect(refused?.status, 'failed');
    expect(refused?.errorCode, isNotEmpty);
    expect(refused?.errorMessage, isNotEmpty);
    expect(await serverSales(), hasLength(3));

    // ignore: avoid_print
    print('Contract check passed. Refused record: ${refused?.errorCode} — ${refused?.errorMessage}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
