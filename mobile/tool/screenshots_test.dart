// Renders the main screens to PNG files without a phone or emulator.
//
//   flutter test tool/screenshots_test.dart --update-goldens
//
// Images are written to tool/screenshots/ (git-ignored). This is a way to
// look at the UI during development, not a regression test: it is not part
// of the normal `flutter test` run.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dokani/features/catalog/data/models.dart';
import 'package:dokani/features/customers/data/customer_repository.dart';

import '../test/support/catalog_fakes.dart';
import '../test/support/fakes.dart';
import '../test/support/pump_app.dart';
import '../test/support/sales_fakes.dart';

/// Tests draw text with a placeholder font unless real fonts are loaded.
Future<void> loadFonts() async {
  final hind = FontLoader('HindSiliguri');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/HindSiliguri-$weight.ttf').readAsBytesSync();
    hind.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await hind.load();

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await loader.load();
    }
  }
}

Future<void> shoot(WidgetTester tester, String name) async {
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/$name.png'));
}

void main() {
  setUpAll(loadFonts);

  // A small, low-end Android screen: 360 x 720 logical pixels.
  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(720, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('login', (tester) async {
    usePhone(tester);
    await pumpApp(tester, repository: FakeAuthRepository());
    await shoot(tester, 'login_bn');

    await tester.tap(find.widgetWithText(FilledButton, 'লগ ইন'));
    await tester.pumpAndSettle();
    await shoot(tester, 'login_bn_errors');
  });

  testWidgets('register', (tester) async {
    usePhone(tester);
    await pumpApp(tester, repository: FakeAuthRepository());
    await tester.tap(find.widgetWithText(TextButton, 'অ্যাকাউন্ট খুলুন'));
    await tester.pumpAndSettle();
    await shoot(tester, 'register_bn');
  });

  testWidgets('home and settings', (tester) async {
    usePhone(tester);
    final session = testSession(shopName: 'রহিম স্টোর');
    await pumpApp(tester, repository: FakeAuthRepository(token: 't', cached: session, serverSession: session));
    await shoot(tester, 'home_bn');

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await shoot(tester, 'settings_bn');

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await shoot(tester, 'home_en');
  });

  testWidgets('suspended shop', (tester) async {
    usePhone(tester);
    final session = testSession(status: 'suspended');
    await pumpApp(tester, repository: FakeAuthRepository(token: 't', cached: session, serverSession: session));
    await shoot(tester, 'home_suspended_bn');
  });

  testWidgets('catalogue', (tester) async {
    usePhone(tester);
    final catalog = FakeCatalogRepository(
      categories: const [Category(id: 1, name: 'মুদি')],
      products: [
        makeProduct(id: 1, name: 'লাক্স সাবান', category: const NamedRef(id: 2, name: 'প্রসাধনী'), variants: [makeVariant(id: 100, price: '45.00', stock: '36.000', barcodes: ['8901030700019'])]),
        makeProduct(id: 2, name: 'মিনিকেট চাল', unit: kilogram, category: const NamedRef(id: 1, name: 'মুদি'), variants: [makeVariant(id: 200, price: '70.00', cost: '62.50', stock: '2.500', status: StockStatus.low)]),
        makeProduct(id: 3, name: 'চিনি', unit: kilogram, variants: [makeVariant(id: 300, price: '135.00', stock: '0.000', status: StockStatus.out)]),
        makeProduct(
          id: 4,
          name: 'পোলো টি-শার্ট',
          variants: [
            makeVariant(id: 400, name: 'S', price: '350.00', cost: '200.00', stock: '4.000', status: StockStatus.low, barcodes: ['TS-S']),
            makeVariant(id: 401, name: 'M', price: '370.00', cost: '210.00', stock: '12.000'),
          ],
        ),
      ],
    );
    await pumpApp(tester, repository: signedInAs(), catalog: catalog);
    await shoot(tester, 'home_catalog_bn');

    await tapQuickAction(tester, 'products');
    await shoot(tester, 'products_bn');

    await tester.tap(find.text('পোলো টি-শার্ট'));
    await tester.pumpAndSettle();
    await shoot(tester, 'product_detail_bn');

    await tester.tap(find.text('স্টক যোগ').first);
    await tester.pumpAndSettle();
    await shoot(tester, 'stock_in_bn');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await shoot(tester, 'product_form_bn');
  });

  testWidgets('point of sale', (tester) async {
    usePhone(tester);
    final catalog = FakeCatalogRepository(
      products: [
        makeProduct(id: 1, name: 'লাক্স সাবান', variants: [makeVariant(id: 100, price: '45.00', stock: '36.000', barcodes: ['SOAP'])]),
        makeProduct(id: 2, name: 'মিনিকেট চাল', unit: kilogram, variants: [makeVariant(id: 200, price: '70.00', stock: '50.000')]),
        makeProduct(id: 3, name: 'রাইস কুকার', variants: [makeVariant(id: 300, price: '1000.00', stock: '5.000')]),
        makeProduct(id: 4, name: 'চিনি', unit: kilogram, variants: [makeVariant(id: 400, price: '135.00', stock: '0.000', status: StockStatus.out)]),
      ],
    );
    final customers = FakeCustomerRepository([const Customer(id: 1, name: 'করিম মিয়া', phone: '01812345678', currentDue: '150.00')]);
    final sales = FakeSalesRepository(catalog: catalog, customers: customers);
    await pumpApp(tester, repository: signedInAs(), catalog: catalog, customers: customers, sales: sales);

    await tapQuickAction(tester, 'new-sale');
    await tester.tap(find.text('লাক্স সাবান'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('লাক্স সাবান'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('রাইস কুকার'));
    await tester.pumpAndSettle();
    await shoot(tester, 'pos_bn');

    await tester.tap(find.text('কার্ট দেখুন'));
    await tester.pumpAndSettle();
    await shoot(tester, 'cart_bn');

    await tester.tap(find.textContaining('বিল করুন ·'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '600');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '01812345678');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    await shoot(tester, 'checkout_bn');

    await tester.ensureVisible(find.text('বিক্রি সম্পন্ন করুন'));
    await tester.tap(find.text('বিক্রি সম্পন্ন করুন'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    await shoot(tester, 'invoice_bn');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await shoot(tester, 'home_dashboard_bn');

    await tapQuickAction(tester, 'collect-due');
    await tester.tap(find.text('করিম মিয়া'));
    await tester.pumpAndSettle();
    await shoot(tester, 'customer_bn');
  });
}
