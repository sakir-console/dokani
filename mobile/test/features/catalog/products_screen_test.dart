import 'package:dokani/features/catalog/data/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/catalog_fakes.dart';
import '../../support/pump_app.dart';

FakeCatalogRepository stockedCatalog() => FakeCatalogRepository(
      products: [
        makeProduct(id: 1, name: 'Lux Soap', variants: [makeVariant(id: 100, barcodes: ['111222'])], category: const NamedRef(id: 1, name: 'Toiletries')),
        makeProduct(id: 2, name: 'Miniket Rice', unit: kilogram, variants: [makeVariant(id: 200, price: '70.00', stock: '2.500', status: StockStatus.low)]),
        makeProduct(id: 3, name: 'Sugar', variants: [makeVariant(id: 300, stock: '0.000', status: StockStatus.out)]),
        makeProduct(
          id: 4,
          name: 'Polo T-shirt',
          variants: [makeVariant(id: 400, name: 'S', price: '350.00'), makeVariant(id: 401, name: 'M', price: '370.00')],
        ),
      ],
    );

Future<void> openProducts(WidgetTester tester) => tapQuickAction(tester, 'products');

void main() {
  testWidgets('home shows stock numbers and only the quick actions that work', (tester) async {
    await pumpApp(tester, repository: signedInAs(), catalog: stockedCatalog(), locale: 'en');

    expect(find.text('4'), findsOneWidget); // products
    expect(find.text('Low stock'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-add-product')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-scan')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-categories')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-vendors')), findsNothing, reason: 'Not in the free plan.');
  });

  testWidgets('a cashier gets no add-product action; a paid plan gets vendors', (tester) async {
    await pumpApp(
      tester,
      repository: signedInAs(role: 'cashier', modules: ['products', 'pos', 'vendors']),
      catalog: stockedCatalog(),
      locale: 'en',
    );

    expect(find.byKey(const ValueKey('quick-add-product')), findsNothing);
    expect(find.byKey(const ValueKey('quick-vendors')), findsOneWidget);

    await openProducts(tester);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Lux Soap'), findsOneWidget);
  });

  testWidgets('a suspended shop sees no catalogue actions', (tester) async {
    await pumpApp(tester, repository: signedInAs(status: 'suspended'), catalog: stockedCatalog(), locale: 'en');

    expect(find.text('Shop suspended'), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-scan')), findsNothing);
    expect(find.text('Quick actions'), findsNothing);
  });

  testWidgets('the list shows price, price range, stock with unit and status', (tester) async {
    await pumpApp(tester, repository: signedInAs(), catalog: stockedCatalog(), locale: 'en');
    await openProducts(tester);

    expect(find.text('Lux Soap'), findsOneWidget);
    expect(find.text('৳60'), findsWidgets);
    expect(find.text('৳350 – ৳370'), findsOneWidget);
    expect(find.text('2.5 Kilogram'), findsOneWidget);
    expect(find.text('Toiletries'), findsOneWidget);
    expect(find.text('2 variants'), findsOneWidget);
    // One "Low stock" filter chip plus one badge; same for "Out of stock".
    expect(find.text('Low stock'), findsNWidgets(2));
    expect(find.text('Out of stock'), findsNWidgets(2));
  });

  testWidgets('the list is in Bangla by default, with Bangla digits', (tester) async {
    await pumpApp(tester, repository: signedInAs(), catalog: stockedCatalog());
    await openProducts(tester);

    expect(find.text('৳৩৫০ – ৳৩৭০'), findsOneWidget);
    expect(find.text('২.৫ কেজি'), findsOneWidget);
    expect(find.text('স্টক শেষ'), findsNWidgets(2));
  });

  testWidgets('typing searches after a pause; filters narrow the list', (tester) async {
    final catalog = stockedCatalog();
    await pumpApp(tester, repository: signedInAs(), catalog: catalog, locale: 'en');
    await openProducts(tester);

    await tester.enterText(find.byType(TextField), 'so');
    await tester.enterText(find.byType(TextField), 'soap');
    await tester.pump(const Duration(milliseconds: 100));
    expect(catalog.queries.where((q) => q.contains('q=so')), isEmpty, reason: 'No request while still typing.');

    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(catalog.queries.where((q) => q.contains('q=so ')), isEmpty, reason: 'Only the final text is searched.');
    expect(find.text('Lux Soap'), findsOneWidget);
    expect(find.text('Sugar'), findsNothing);

    await tester.enterText(find.byType(TextField), 'no such product');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('Nothing found'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Out of stock'));
    await tester.pumpAndSettle();
    expect(find.text('Sugar'), findsOneWidget);
    expect(find.text('Lux Soap'), findsNothing);
  });

  testWidgets('a stock alert on home opens the list already filtered', (tester) async {
    await pumpApp(tester, repository: signedInAs(), catalog: stockedCatalog(), locale: 'en');

    await tester.tap(find.text('Low stock'));
    await tester.pumpAndSettle();

    expect(find.text('Miniket Rice'), findsOneWidget);
    expect(find.text('Lux Soap'), findsNothing);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Low stock')).selected, isTrue);
  });

  testWidgets('an empty shop is told how to start', (tester) async {
    await pumpApp(tester, repository: signedInAs(), locale: 'en');
    await openProducts(tester);

    expect(find.text('No products yet'), findsOneWidget);
    expect(find.text('Add your first product to start selling.'), findsOneWidget);
  });

  testWidgets('scanning a known barcode opens that product', (tester) async {
    await pumpApp(tester, repository: signedInAs(), catalog: stockedCatalog(), locale: 'en', scanResult: '111222');

    await tapQuickAction(tester, 'scan');

    expect(find.text('Lux Soap'), findsOneWidget);
    expect(find.text('Barcode: 111222'), findsOneWidget);
  });

  testWidgets('scanning an unknown barcode offers to add it, with the code filled in', (tester) async {
    await pumpApp(tester, repository: signedInAs(), catalog: stockedCatalog(), locale: 'en', scanResult: '999000');

    await tapQuickAction(tester, 'scan');
    expect(find.text('No product with this barcode'), findsOneWidget);
    expect(find.text('Barcode 999000 is not in your shop yet.'), findsOneWidget);

    await tester.tap(find.text('Add as new product'));
    await tester.pumpAndSettle();

    expect(find.text('Add product'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '999000'), findsOneWidget);
  });

  testWidgets('a cashier scanning an unknown barcode is not offered to add it', (tester) async {
    await pumpApp(tester, repository: signedInAs(role: 'cashier'), catalog: stockedCatalog(), locale: 'en', scanResult: '999000');

    await tapQuickAction(tester, 'scan');

    expect(find.text('No product with this barcode'), findsOneWidget);
    expect(find.text('Add as new product'), findsNothing);
  });

  testWidgets('backing out of the scanner does nothing', (tester) async {
    await pumpApp(tester, repository: signedInAs(), catalog: stockedCatalog(), locale: 'en');

    await tapQuickAction(tester, 'scan');

    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
