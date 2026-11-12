import 'package:dokani/features/catalog/data/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/catalog_fakes.dart';
import '../../support/pump_app.dart';

FakeCatalogRepository catalogWithRice() => FakeCatalogRepository(
      products: [
        makeProduct(
          id: 2,
          name: 'Miniket Rice',
          unit: kilogram,
          category: const NamedRef(id: 1, name: 'Grocery'),
          storageLocation: 'Rack 3',
          variants: [makeVariant(id: 200, price: '70.00', cost: '62.50', stock: '25.500', barcodes: ['8941100000017'], sku: 'RICE-01')],
        ),
      ],
    );

Future<void> openRice(WidgetTester tester) async {
  await tapQuickAction(tester, 'products');
  await tester.tap(find.text('Miniket Rice'));
  await tester.pumpAndSettle();
}

Future<void> typeInSheet(WidgetTester tester, int index, String value) async {
  await tester.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextFormField)).at(index), value);
}

Future<void> saveSheet(WidgetTester tester) async {
  await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.widgetWithText(FilledButton, 'Save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows price, cost, stock, barcode and details to the owner', (tester) async {
    await pumpApp(tester, repository: signedInAs(), catalog: catalogWithRice(), locale: 'en');
    await openRice(tester);

    expect(find.text('Miniket Rice'), findsOneWidget);
    expect(find.text('৳70'), findsOneWidget);
    expect(find.text('Cost ৳62.50'), findsOneWidget);
    expect(find.text('Stock: 25.5 Kilogram'), findsOneWidget);
    expect(find.text('Barcode: 8941100000017  ·  SKU: RICE-01'), findsOneWidget);
    expect(find.text('Grocery'), findsOneWidget);
    expect(find.text('Rack 3'), findsOneWidget);
  });

  testWidgets('a cashier sees the price but not the cost, and cannot change stock or edit', (tester) async {
    await pumpApp(tester, repository: signedInAs(role: 'cashier'), catalog: catalogWithRice(), locale: 'en');
    await openRice(tester);

    expect(find.text('৳70'), findsOneWidget);
    expect(find.textContaining('Cost'), findsNothing);
    expect(find.text('Stock in'), findsNothing);
    expect(find.byTooltip('Edit'), findsNothing);
    expect(find.byTooltip('Delete product'), findsNothing);
  });

  testWidgets('stock in adds to stock and can record the cost', (tester) async {
    final catalog = catalogWithRice();
    await pumpApp(tester, repository: signedInAs(), catalog: catalog, locale: 'en');
    await openRice(tester);

    await tester.tap(find.text('Stock in'));
    await tester.pumpAndSettle();
    expect(find.text('Current stock: 25.5 Kilogram'), findsOneWidget);

    await saveSheet(tester);
    expect(find.text('Enter a valid number'), findsOneWidget);

    await typeInSheet(tester, 0, '10.5');
    await typeInSheet(tester, 1, '64');
    await saveSheet(tester);

    expect(catalog.stockCalls, ['in 200 10.5 cost=64 note=null']);
    expect(find.text('Stock updated'), findsOneWidget);
    expect(find.text('Stock: 36 Kilogram'), findsOneWidget);
  });

  testWidgets('stock out requires a reason', (tester) async {
    final catalog = catalogWithRice();
    await pumpApp(tester, repository: signedInAs(), catalog: catalog, locale: 'en');
    await openRice(tester);

    await tester.tap(find.text('Stock out'));
    await tester.pumpAndSettle();
    await typeInSheet(tester, 0, '2');
    await saveSheet(tester);
    expect(find.text('This is required'), findsOneWidget);
    expect(catalog.stockCalls, isEmpty);

    await typeInSheet(tester, 1, 'Damaged by rain');
    await saveSheet(tester);
    expect(catalog.stockCalls, ['out 200 2 note=Damaged by rain']);
    expect(find.text('Stock: 23.5 Kilogram'), findsOneWidget);
  });

  testWidgets('correcting stock sets the counted quantity, zero included', (tester) async {
    final catalog = catalogWithRice();
    await pumpApp(tester, repository: signedInAs(), catalog: catalog, locale: 'en');
    await openRice(tester);

    await tester.tap(find.text('Correct stock'));
    await tester.pumpAndSettle();
    await typeInSheet(tester, 0, '0');
    await saveSheet(tester);

    expect(catalog.stockCalls, ['adjust 200 0 note=null']);
    expect(find.text('Stock: 0 Kilogram'), findsOneWidget);
  });

  testWidgets('deleting asks first and returns to the list', (tester) async {
    final catalog = catalogWithRice();
    await pumpApp(tester, repository: signedInAs(), catalog: catalog, locale: 'en');
    await openRice(tester);

    await tester.tap(find.byTooltip('Delete product'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Delete "Miniket Rice"?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(catalog.deleted, isEmpty);

    await tester.tap(find.byTooltip('Delete product'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(catalog.deleted, [2]);
    expect(find.text('No products yet'), findsOneWidget);
  });
}
