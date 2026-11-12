import 'package:dokani/features/catalog/data/models.dart';
import 'package:dokani/features/vendors/data/vendor_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/catalog_fakes.dart';
import '../../support/pump_app.dart';

const withVendors = ['products', 'pos', 'customers', 'offline', 'vendors'];

void main() {
  group('categories', () {
    testWidgets('can be added, renamed and deleted', (tester) async {
      final catalog = FakeCatalogRepository();
      await pumpApp(tester, repository: signedInAs(), catalog: catalog, locale: 'en');
      await tapQuickAction(tester, 'categories');

      expect(find.text('No categories yet'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(find.text('This is required'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'Snacks');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Snacks'), findsOneWidget);

      await tester.tap(find.byTooltip('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Snacks & Drinks');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Snacks & Drinks'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Its products stay'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('No categories yet'), findsOneWidget);
      expect(await catalog.categories(), isEmpty);
    });

    testWidgets('a cashier can see categories but not change them', (tester) async {
      final catalog = FakeCatalogRepository(categories: const [Category(id: 1, name: 'Grocery')]);
      await pumpApp(tester, repository: signedInAs(role: 'cashier'), catalog: catalog, locale: 'en');
      await tapQuickAction(tester, 'categories');

      expect(find.text('Grocery'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byTooltip('Rename'), findsNothing);
      expect(find.byTooltip('Delete'), findsNothing);
    });
  });

  group('vendors', () {
    testWidgets('can be added with a normalised phone, searched, edited and deleted', (tester) async {
      final vendors = FakeVendorRepository([const Vendor(id: 1, name: 'Karim Store', productsCount: 3)]);
      await pumpApp(tester, repository: signedInAs(modules: withVendors), vendors: vendors, locale: 'en');
      await tapQuickAction(tester, 'vendors');

      expect(find.text('Karim Store'), findsOneWidget);
      expect(find.text('3 products'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      final sheetFields = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextFormField));
      await tester.enterText(sheetFields.at(1), '12345');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('This is required'), findsOneWidget);
      expect(find.text('Enter a valid mobile number, like 01712345678'), findsOneWidget);

      await tester.enterText(sheetFields.at(0), 'Jamal Traders');
      await tester.enterText(sheetFields.at(1), '+880 1912-345678');
      await tester.enterText(sheetFields.at(2), 'Jamal & Sons');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(vendors.created.single.name, 'Jamal Traders');
      expect(vendors.created.single.phone, '01912345678');
      expect(find.text('Jamal Traders'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'jamal');
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Jamal Traders'), findsOneWidget);
      expect(find.text('Karim Store'), findsNothing);

      await tester.tap(find.text('Jamal Traders'));
      await tester.pumpAndSettle();
      expect(find.text('Edit vendor'), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextFormField)).at(0), 'Jamal Enterprise');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Jamal Enterprise'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Jamal Enterprise'), findsNothing);
    });

    testWidgets('an empty vendor list explains what vendors are for', (tester) async {
      await pumpApp(tester, repository: signedInAs(modules: withVendors), locale: 'en');
      await tapQuickAction(tester, 'vendors');

      expect(find.text('No vendors yet'), findsOneWidget);
      expect(find.text('Add the people and companies you buy from.'), findsOneWidget);
    });
  });
}
