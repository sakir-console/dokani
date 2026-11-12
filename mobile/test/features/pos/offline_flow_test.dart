import 'package:dokani/core/database/local_database.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:dokani/features/customers/data/customer_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../support/catalog_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/sales_fakes.dart';
import '../../support/sync_fakes.dart';

/// A shop whose phone has a local database, with a switch for the internet.
class OfflineShop {
  OfflineShop() {
    final products = [
      makeProduct(id: 1, name: 'Lux Soap', variants: [makeVariant(id: 10, price: '45.00', stock: '3.000', barcodes: ['SOAP'])]),
      makeProduct(id: 2, name: 'Miniket Rice', unit: kilogram, variants: [makeVariant(id: 20, price: '70.00', stock: '50.000')]),
    ];
    const karim = Customer(id: 1, name: 'Karim Mia', phone: '01812345678', currentDue: '150.00');

    catalog = FakeCatalogRepository(products: products);
    customers = FakeCustomerRepository([karim]);
    sales = FakeSalesRepository(catalog: catalog, customers: customers);
    api = FakeSyncApi(products: products, customers: [karim], sales: sales);
    database = LocalDatabase.inMemory();
  }

  late final FakeCatalogRepository catalog;
  late final FakeCustomerRepository customers;
  late final FakeSalesRepository sales;
  late final FakeSyncApi api;
  late final LocalDatabase database;

  set online(bool value) {
    api.online = value;
    sales.offline = !value;
    customers.offline = !value;
  }
}

/// Starts the app signed in. The first sync runs while online and fills the phone's copy.
Future<OfflineShop> start(
  WidgetTester tester, {
  String role = 'owner',
  String locale = 'en',
  List<String> scanCodes = const [],
  Future<void> Function(OfflineShop shop)? before,
}) async {
  final shop = OfflineShop();
  _opened.add(shop.database);
  if (before != null) await tester.runAsync(() => before(shop));

  await pumpApp(
    tester,
    repository: signedInAs(
      role: role,
      permissions: role == 'owner' ? null : ['shop.view', 'pos.sell', 'customers.manage', 'due.collect'],
    ),
    catalog: shop.catalog,
    customers: shop.customers,
    sales: shop.sales,
    locale: locale,
    scanCodes: scanCodes,
    database: shop.database,
    syncApi: shop.api,
  );
  await settle(tester);
  return shop;
}

final _opened = <LocalDatabase>[];

/// A widget test that ends by taking the app down and closing the database,
/// so the database's own clean-up timers have run before the test is judged.
void offlineTest(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await body(tester);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    for (final database in _opened) {
      await tester.runAsync(database.close);
    }
    _opened.clear();
  });
}

/// Reads the phone's database from a test. Database calls made directly by a
/// test need the real clock; the app's own calls run under the test clock.
Future<T> db<T>(WidgetTester tester, Future<T> Function() read) async => (await tester.runAsync(read)) as T;

/// Lets database work and the background sync finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await settle(tester);
}

/// Back to the previous screen, in either language.
Future<void> goBack(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await settle(tester);
}

/// Back to home, scrolled to the top where the notice about unsent records is.
Future<void> backToHomeTop(WidgetTester tester) async {
  await goBack(tester);
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 800));
  await settle(tester);
}

/// Taps something further down a long screen.
Future<void> scrollToAndTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await tapAndSettle(tester, finder);
}

Future<void> sellOneSoap(WidgetTester tester) async {
  await tapQuickAction(tester, 'new-sale');
  await settle(tester);
  await tapAndSettle(tester, find.text('Lux Soap'));
  await tapAndSettle(tester, find.text('View cart'));
  await tapAndSettle(tester, find.textContaining('Checkout ·'));
}

Future<void> complete(WidgetTester tester) async {
  await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Complete sale'));
  await tester.pumpAndSettle(const Duration(milliseconds: 500));
}

void main() {
  offlineTest('signing in fills the phone with the shop\'s products and customers', (tester) async {
    final shop = await start(tester);

    expect(await db(tester, shop.database.productCount), 2);
    expect((await db(tester, () => shop.database.customerByPhone('01812345678')))?['name'], 'Karim Mia');
    expect(find.byKey(const ValueKey('unsynced-card')), findsNothing);
  });

  offlineTest('without internet a sale is made from the phone\'s copy, shown as waiting, and sent when the internet returns', (tester) async {
    final shop = await start(tester);
    shop.online = false;

    await sellOneSoap(tester);
    expect(shop.catalog.queries, isEmpty, reason: 'the counter reads the phone, not the network');
    await complete(tester);

    // The invoice says plainly that the server has not seen this sale.
    expect(find.text('Saved on this phone'), findsOneWidget);
    expect(find.textContaining('Temporary no. OFF-'), findsOneWidget);
    expect(find.text('Lux Soap'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining('once the sale reaches the server'), findsOneWidget);
    expect(shop.api.storedSales, isEmpty);
    expect((await db(tester, shop.database.unsynced)).single.kind, 'sale');

    // Home keeps it in view.
    await backToHomeTop(tester);
    expect(find.text('1 record waiting to be sent'), findsOneWidget);

    // The counter no longer offers the piece that was sold: 3 in stock, now 2.
    await scrollToAndTap(tester, find.byKey(const ValueKey('quick-new-sale')));
    expect(find.text('2 Piece'), findsOneWidget);
    await backToHomeTop(tester);

    // The internet is back.
    shop.online = true;
    await tapAndSettle(tester, find.widgetWithText(TextButton, 'View'));
    expect(find.textContaining('Sale · OFF-'), findsOneWidget);
    expect(find.text('Waiting to be sent'), findsOneWidget);

    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Send now'));

    expect(shop.api.storedSales, hasLength(1));
    expect(await db(tester, shop.database.unsynced), isEmpty);
    expect(find.text('Everything is saved on the server'), findsWidgets);

    await backToHomeTop(tester);
    expect(find.byKey(const ValueKey('unsynced-card')), findsNothing);
  });

  offlineTest('the waiting invoice turns into a confirmed one when the sale reaches the server', (tester) async {
    final shop = await start(tester);
    shop.online = false;
    await sellOneSoap(tester);
    await complete(tester);
    expect(find.text('Saved on this phone'), findsOneWidget);

    shop.online = true;
    await scrollToAndTap(tester, find.widgetWithText(OutlinedButton, 'Send now'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 800));
    await settle(tester);

    expect(find.text('Saved on this phone'), findsNothing);
    expect(find.text('Confirmed by the server'), findsOneWidget);
    expect(find.text('Invoice INV-9000'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Open invoice'), findsOneWidget);
  });

  offlineTest('with internet nothing changes for the cashier: the sale is confirmed at once with its QR code', (tester) async {
    final shop = await start(tester);

    await sellOneSoap(tester);
    await complete(tester);

    expect(find.text('Sale completed'), findsOneWidget);
    expect(find.text('Invoice INV-000001'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(await db(tester, shop.database.unsynced), isEmpty);
    expect(shop.sales.all, hasLength(1));
  });

  offlineTest('scanning works without internet', (tester) async {
    final shop = await start(tester, scanCodes: ['SOAP', 'NOPE']);
    shop.online = false;

    await tapQuickAction(tester, 'new-sale');
    await settle(tester);
    await tapAndSettle(tester, find.byTooltip('Scan barcode'));

    expect(find.textContaining('1 item'), findsOneWidget);
  });

  offlineTest('a sale on due without internet recognises the customer from the phone\'s copy', (tester) async {
    final shop = await start(tester);
    shop.online = false;
    await sellOneSoap(tester);

    final cash = find.byType(TextFormField).first;
    await tester.enterText(cash, '0');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '01812345678');
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await settle(tester);

    expect(find.textContaining('Karim Mia'), findsOneWidget);
    expect(find.textContaining('৳150'), findsOneWidget);

    await complete(tester);

    expect(find.text('Saved on this phone'), findsOneWidget);
    expect(find.textContaining('Karim Mia · 01812345678'), findsOneWidget);
    expect((await db(tester, () => shop.database.customerByPhone('01812345678')))?['current_due'], '195.00');
  });

  offlineTest('a record the server refused shows the reason; the owner can remove it', (tester) async {
    final shop = await start(
      tester,
      before: (shop) async {
        await shop.database.enqueue(
          clientUuid: 'bad-1',
          kind: 'sale',
          payload: cashDraft(uuid: 'bad-1', variantId: 10, price: '45.00').toJson(),
          display: {'invoice_no': 'OFF-BAD1', 'grand_total': '45.00', 'sold_at': '2026-11-12T09:00:00Z', 'subtotal': '45.00', 'paid_amount': '45.00', 'due_amount': '0.00'},
        );
        shop.api.reject['bad-1'] = (code: 'PRODUCT_NOT_FOUND', message: 'This product no longer exists.');
      },
    );

    expect(find.text('1 record waiting to be sent'), findsOneWidget);
    expect(find.text('1 record was not accepted by the server.'), findsOneWidget);

    await tapAndSettle(tester, find.widgetWithText(TextButton, 'View'));
    expect(find.textContaining('This product no longer exists.'), findsOneWidget);

    await tapAndSettle(tester, find.byTooltip('Remove from this phone'));
    expect(find.textContaining('it will not be recorded anywhere'), findsOneWidget);
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Remove'));

    expect(await db(tester, shop.database.unsynced), isEmpty);
    expect(find.textContaining('This product no longer exists.'), findsNothing);
  });

  offlineTest('a cashier sees a refused record but cannot remove it', (tester) async {
    await start(
      tester,
      role: 'cashier',
      before: (shop) async {
        await shop.database.enqueue(
          clientUuid: 'bad-1',
          kind: 'sale',
          payload: cashDraft(uuid: 'bad-1', variantId: 10, price: '45.00').toJson(),
          display: {'invoice_no': 'OFF-BAD1', 'grand_total': '45.00'},
        );
        shop.api.reject['bad-1'] = (code: 'PRODUCT_NOT_FOUND', message: 'This product no longer exists.');
      },
    );

    await tapAndSettle(tester, find.widgetWithText(TextButton, 'View'));

    expect(find.textContaining('This product no longer exists.'), findsOneWidget);
    expect(find.byTooltip('Remove from this phone'), findsNothing);
  });

  offlineTest('logging out with unsent records says what happens to them first', (tester) async {
    final shop = await start(tester);
    shop.online = false;
    await sellOneSoap(tester);
    await complete(tester);
    await backToHomeTop(tester);

    await tapAndSettle(tester, find.byTooltip('Settings'));
    expect(find.text('1 record waiting to be sent'), findsOneWidget);
    await tapAndSettle(tester, find.widgetWithText(OutlinedButton, 'Log out'));

    expect(find.textContaining('1 record has not been sent yet. It stays on this phone'), findsOneWidget);
    expect(find.textContaining('Log out of this phone?'), findsOneWidget);
  });

  offlineTest('customers and due collection work without internet, and say so', (tester) async {
    final shop = await start(tester);
    shop.online = false;

    await tapQuickAction(tester, 'collect-due');
    await settle(tester);
    expect(find.text('No internet. Showing the copy saved on this phone.'), findsOneWidget);
    expect(find.text('৳150'), findsOneWidget);

    await tapAndSettle(tester, find.text('Karim Mia'));
    expect(find.text('Outstanding due'), findsOneWidget);

    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Collect due'));
    await tester.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextFormField)).first, '50');
    await tapAndSettle(tester, find.descendant(of: find.byType(BottomSheet), matching: find.widgetWithText(FilledButton, 'Save')));

    expect(find.text('Saved on this phone. It will be sent when the internet is back.'), findsOneWidget);
    expect(find.text('৳100'), findsOneWidget);
    expect(shop.customers.collections, isEmpty);
    expect((await db(tester, shop.database.unsynced)).single.kind, 'due_collection');

    shop.online = true;
    await goBack(tester);
    await backToHomeTop(tester);
    await tapAndSettle(tester, find.widgetWithText(TextButton, 'View'));
    expect(find.textContaining('Due collection · Karim Mia'), findsOneWidget);
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Send now'));

    expect(shop.api.storedDueCollections.single, containsPair('amount', '50'));
    expect(await db(tester, shop.database.unsynced), isEmpty);
  });

  offlineTest('the waiting state is explained in Bangla too', (tester) async {
    final shop = await start(tester, locale: 'bn');
    shop.online = false;

    await tapQuickAction(tester, 'new-sale');
    await settle(tester);
    await tapAndSettle(tester, find.text('Lux Soap'));
    await tapAndSettle(tester, find.text('কার্ট দেখুন'));
    await tapAndSettle(tester, find.textContaining('বিল করুন'));
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'বিক্রি সম্পন্ন করুন'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.text('এই ফোনে সেভ হয়েছে'), findsOneWidget);
    expect(find.textContaining('অস্থায়ী নম্বর OFF-'), findsOneWidget);

    await backToHomeTop(tester);
    expect(find.text('১টি রেকর্ড পাঠানো বাকি'), findsOneWidget);
  });
}
