import 'package:dokani/core/network/api_exception.dart';
import 'package:dokani/features/catalog/data/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/catalog_fakes.dart';
import '../../support/pump_app.dart';

/// The text field under a given label (AppTextField puts the label above the field).
Finder fieldLabelled(String label) => find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
      matching: find.byType(TextFormField),
    );

Future<void> type(WidgetTester tester, String label, String value) async {
  final field = fieldLabelled(label).first;
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

Future<void> pick(WidgetTester tester, String fieldLabel, String option) async {
  final field = find.bySemanticsLabel(RegExp('^$fieldLabel:'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, option));
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Save');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<FakeCatalogRepository> openNewProduct(WidgetTester tester, {FakeCatalogRepository? catalog, String? scanResult, List<String>? modules}) async {
  final repository = catalog ?? FakeCatalogRepository(categories: const [Category(id: 1, name: 'Grocery')]);
  await pumpApp(tester, repository: signedInAs(modules: modules), catalog: repository, locale: 'en', scanResult: scanResult);
  await tapQuickAction(tester, 'add-product');
  return repository;
}

void main() {
  testWidgets('nothing is sent until name, unit and selling price are valid', (tester) async {
    final catalog = await openNewProduct(tester);

    await save(tester);
    expect(find.text('This is required'), findsNWidgets(2)); // name, selling price
    expect(find.text('Choose a unit'), findsOneWidget);

    await type(tester, 'Product name', 'Rice');
    await pick(tester, 'Unit', 'Kilogram');
    await type(tester, 'Selling price', 'seventy');
    await save(tester);
    expect(find.text('Enter a valid number'), findsOneWidget);
    expect(catalog.created, isEmpty);
  });

  testWidgets('a simple product is created with clean numbers and opens its page', (tester) async {
    final catalog = await openNewProduct(tester);

    await type(tester, 'Product name', '  Miniket Rice ');
    await pick(tester, 'Unit', 'Kilogram');
    await pick(tester, 'Category', 'Grocery');
    await type(tester, 'Purchase price', '৬২.৫০'); // typed with a Bangla keyboard
    await type(tester, 'Selling price', '70');
    await type(tester, 'Opening stock (optional)', '25.5');
    await type(tester, 'Barcode (optional)', ' 8941100000017 ');
    await type(tester, 'SKU (optional)', 'RICE-01');
    await type(tester, 'Storage location (optional)', 'Rack 3');
    await save(tester);

    final draft = catalog.created.single;
    expect(draft.name, 'Miniket Rice');
    expect(draft.unitId, kilogram.id);
    expect(draft.categoryId, 1);
    expect(draft.hasVariants, isFalse);
    expect(draft.storageLocation, 'Rack 3');
    expect(draft.variants, hasLength(1));
    expect(draft.variants.single.name, isNull);
    expect(draft.variants.single.purchasePrice, '62.50');
    expect(draft.variants.single.sellingPrice, '70');
    expect(draft.variants.single.openingStock, '25.5');
    expect(draft.variants.single.barcodes, ['8941100000017']);
    expect(draft.variants.single.sku, 'RICE-01');

    // Lands on the new product's page.
    expect(find.text('Miniket Rice'), findsOneWidget);
    expect(find.text('Stock: 25.5 Kilogram'), findsOneWidget);
    expect(find.text('Product saved'), findsOneWidget);
  });

  testWidgets('an empty purchase price is sent as zero, and whole-unit products reject fractions', (tester) async {
    final catalog = await openNewProduct(tester);

    await type(tester, 'Product name', 'Soap');
    await pick(tester, 'Unit', 'Piece');
    await type(tester, 'Selling price', '45');
    await type(tester, 'Opening stock (optional)', '2.5');
    await save(tester);
    expect(find.text('Enter a whole number'), findsOneWidget);
    expect(catalog.created, isEmpty);

    await type(tester, 'Opening stock (optional)', '12');
    await save(tester);
    expect(catalog.created.single.variants.single.purchasePrice, '0');
    expect(catalog.created.single.variants.single.openingStock, '12');
  });

  testWidgets('a selling price below cost is flagged but not blocked', (tester) async {
    final catalog = await openNewProduct(tester);

    await type(tester, 'Product name', 'Clearance item');
    await pick(tester, 'Unit', 'Piece');
    await type(tester, 'Purchase price', '100');
    await type(tester, 'Selling price', '80');
    expect(find.text('Selling price is lower than the purchase price'), findsOneWidget);

    await save(tester);
    expect(catalog.created, hasLength(1));
  });

  testWidgets('variants each carry their own name, price, stock and barcode', (tester) async {
    final catalog = await openNewProduct(tester);

    await type(tester, 'Product name', 'Polo T-shirt');
    await pick(tester, 'Unit', 'Piece');
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Variant 1'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Add variant'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Add variant'));
    await tester.pumpAndSettle();
    expect(find.text('Variant 2'), findsOneWidget);

    // Saving with unnamed variants is refused.
    await save(tester);
    expect(find.text('This is required'), findsNWidgets(4)); // 2 names + 2 selling prices
    expect(catalog.created, isEmpty);

    Future<void> fill(int index, String name, String price, String stock, String barcode) async {
      Future<void> enter(String label, String value) async {
        // The field under the index-th occurrence of this label (one per variant).
        final field = find.descendant(
          of: find.ancestor(of: find.text(label).at(index), matching: find.byType(Column)).first,
          matching: find.byType(TextFormField),
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
        await tester.pump();
      }

      await enter('Variant name', name);
      await enter('Selling price', price);
      await enter('Opening stock (optional)', stock);
      await enter('Barcode (optional)', barcode);
    }

    await fill(0, 'S', '350', '4', 'TS-S');
    await fill(1, 'M', '370', '', 'TS-M');
    await save(tester);

    final draft = catalog.created.single;
    expect(draft.hasVariants, isTrue);
    expect(draft.variants.map((v) => v.name), ['S', 'M']);
    expect(draft.variants.map((v) => v.sellingPrice), ['350', '370']);
    expect(draft.variants[0].openingStock, '4');
    expect(draft.variants[1].openingStock, isNull);
    expect(draft.variants.map((v) => v.barcodes.single), ['TS-S', 'TS-M']);
  });

  testWidgets('turning variants off keeps a single price and stock', (tester) async {
    final catalog = await openNewProduct(tester);

    await type(tester, 'Product name', 'Thing');
    await pick(tester, 'Unit', 'Piece');
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Add variant'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Add variant'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Variant 1'), findsNothing);

    await type(tester, 'Selling price', '10');
    await save(tester);
    expect(catalog.created.single.hasVariants, isFalse);
    expect(catalog.created.single.variants, hasLength(1));
  });

  testWidgets('the scan button fills the barcode field', (tester) async {
    await openNewProduct(tester, scanResult: '4902430000000');

    final scanButton = find.byTooltip('Scan barcode');
    await tester.ensureVisible(scanButton.first);
    await tester.tap(scanButton.first);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '4902430000000'), findsOneWidget);
  });

  testWidgets('a category can be created from inside the form', (tester) async {
    final catalog = await openNewProduct(tester);

    await type(tester, 'Product name', 'Chips');
    await pick(tester, 'Unit', 'Piece');

    final field = find.bySemanticsLabel(RegExp('^Category:'));
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Add category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, 'Snacks');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Category: Snacks'), findsOneWidget);

    await type(tester, 'Selling price', '20');
    await save(tester);
    final categoryId = catalog.created.single.categoryId;
    expect(await catalog.categories().then((list) => list.firstWhere((c) => c.id == categoryId).name), 'Snacks');
  });

  testWidgets('the vendor field appears only when the plan includes vendors', (tester) async {
    await openNewProduct(tester);
    expect(find.bySemanticsLabel(RegExp('^Vendor:')), findsNothing);
  });

  testWidgets('with vendors in the plan, a vendor can be picked', (tester) async {
    await openNewProduct(tester, modules: ['products', 'pos', 'vendors']);
    expect(find.bySemanticsLabel(RegExp('^Vendor:')), findsOneWidget);
  });

  testWidgets('a server refusal is shown and the form stays open with its input', (tester) async {
    final catalog = await openNewProduct(tester);
    catalog.failNext = const ApiException(
      kind: ApiErrorKind.server,
      statusCode: 403,
      code: 'PLAN_LIMIT_REACHED',
      message: 'Your plan allows 50 products. Upgrade to add more.',
    );

    await type(tester, 'Product name', 'One too many');
    await pick(tester, 'Unit', 'Piece');
    await type(tester, 'Selling price', '10');
    await save(tester);

    expect(find.text('Your plan allows 50 products. Upgrade to add more.'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'One too many'), findsOneWidget);
    expect(catalog.all, isEmpty);
  });

  testWidgets('editing loads the product, keeps variant ids, and never sends stock', (tester) async {
    final catalog = FakeCatalogRepository(
      products: [
        makeProduct(
          id: 7,
          name: 'Shampoo',
          variants: [
            makeVariant(id: 70, name: '250ml', price: '150.00', cost: '100.00', stock: '6.000', barcodes: ['SH-250']),
            makeVariant(id: 71, name: '500ml', price: '260.00', cost: '180.00', stock: '0.000'),
          ],
        ),
      ],
    );
    await pumpApp(tester, repository: signedInAs(), catalog: catalog, locale: 'en');
    await tapQuickAction(tester, 'products');
    await tester.tap(find.text('Shampoo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit product'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Shampoo'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '250ml'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '150'), findsOneWidget);
    expect(find.text('Opening stock (optional)'), findsNothing, reason: 'Existing stock is changed through stock actions only.');
    expect(find.text('Current stock: 6 Piece'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, '150'), '165');
    await save(tester);

    final draft = catalog.updated[7]!;
    expect(draft.variants.map((v) => v.id), [70, 71]);
    expect(draft.variants[0].sellingPrice, '165');
    expect(draft.variants[0].barcodes, ['SH-250']);
    expect(draft.variants.every((v) => v.openingStock == null), isTrue);

    // Back on the product page with the new price.
    expect(find.text('৳165'), findsOneWidget);
  });
}
