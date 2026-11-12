import 'package:dokani/features/customers/data/customer_repository.dart';
import 'package:dokani/features/pos/data/sale_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/catalog_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/sales_fakes.dart';

class World {
  World({bool showProfit = true}) {
    catalog = FakeCatalogRepository(
      products: [makeProduct(id: 1, name: 'Rice Cooker', variants: [makeVariant(id: 10, price: '1000.00', stock: '9.000')])],
    );
    customers = FakeCustomerRepository([
      const Customer(id: 1, name: 'Karim Mia', phone: '01812345678'),
      const Customer(id: 2, name: 'Abdul Kader', phone: '01912345678'),
    ]);
    sales = FakeSalesRepository(catalog: catalog, customers: customers, showProfit: showProfit);
  }

  late final FakeCatalogRepository catalog;
  late FakeCustomerRepository customers;
  late final FakeSalesRepository sales;

  /// A sale of one ৳1,000 item with [paid] in cash and the rest on due to Karim.
  Future<void> sellOnDue(String paid, String due, {String uuid = 'u1'}) => sales.createSale(
        SaleDraft(
          clientUuid: uuid,
          items: const [SaleLineDraft(variantId: 10, quantity: '1.000', unitPrice: '1000.00')],
          grandTotal: '1000.00',
          payments: [if (paid != '0') PaymentDraft(method: PaymentMethod.cash, amount: paid)],
          dueAmount: due,
          customerPhone: '01812345678',
        ),
      );
}

Future<void> open(WidgetTester tester, World world, {String role = 'owner', List<String>? permissions}) => pumpApp(
      tester,
      repository: signedInAs(role: role, permissions: permissions),
      catalog: world.catalog,
      customers: world.customers,
      sales: world.sales,
      locale: 'en',
    );

Finder sheetField(int index) => find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextFormField)).at(index);

Future<void> saveSheet(WidgetTester tester) async {
  final button = find.descendant(of: find.byType(BottomSheet), matching: find.widgetWithText(FilledButton, 'Save'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('dashboard', () {
    testWidgets('shows today\'s sales, profit, orders, items and customer due', (tester) async {
      final world = World();
      await world.sellOnDue('600.00', '400.00');
      await world.sellOnDue('1000.00', '0.00', uuid: 'u2');
      await open(tester, world);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('৳2,000'), findsOneWidget); // sales
      expect(find.text('৳123'), findsOneWidget); //   profit, a different number
      expect(find.text('Profit'), findsOneWidget);
      expect(find.text('৳400'), findsOneWidget); //   customer due
      expect(find.byKey(const ValueKey('quick-new-sale')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-collect-due')), findsOneWidget);
    });

    testWidgets('a cashier sees sales but not profit', (tester) async {
      final world = World(showProfit: false);
      await world.sellOnDue('1000.00', '0.00');
      await open(tester, world, role: 'cashier', permissions: ['shop.view', 'pos.sell', 'due.collect']);

      expect(find.text('৳1,000'), findsOneWidget);
      expect(find.text('Profit'), findsNothing);
    });

    testWidgets('a role that cannot sell or collect gets neither button', (tester) async {
      await open(tester, World(), role: 'cashier', permissions: ['shop.view']);

      expect(find.byKey(const ValueKey('quick-new-sale')), findsNothing);
      expect(find.byKey(const ValueKey('quick-collect-due')), findsNothing);
      expect(find.byKey(const ValueKey('quick-sales')), findsOneWidget);
    });
  });

  group('due collection', () {
    testWidgets('Collect due lists who owes money; payments in instalments clear the balance', (tester) async {
      final world = World();
      await world.sellOnDue('400.00', '600.00');
      await open(tester, world);

      await tapQuickAction(tester, 'collect-due');
      expect(find.text('Karim Mia'), findsOneWidget);
      expect(find.text('Abdul Kader'), findsNothing, reason: 'Only customers with a due are listed.');
      expect(find.text('৳600'), findsOneWidget);

      await tester.tap(find.text('Karim Mia'));
      await tester.pumpAndSettle();
      expect(find.text('Outstanding due'), findsOneWidget);
      expect(find.text('Sale on due · INV-000001'), findsOneWidget);
      expect(find.text('+ ৳600'), findsOneWidget);

      // First instalment: 250 in cash.
      await tester.tap(find.widgetWithText(FilledButton, 'Collect due'));
      await tester.pumpAndSettle();
      await saveSheet(tester);
      expect(find.text('Enter a valid number'), findsOneWidget);

      await tester.enterText(sheetField(0), '700');
      await saveSheet(tester);
      expect(find.text('This is more than the customer owes'), findsOneWidget);
      expect(world.customers.collections, isEmpty);

      await tester.enterText(sheetField(0), '250');
      await saveSheet(tester);
      expect(world.customers.collections, ['1 250 cash tx=null']);
      expect(find.text('Payment recorded'), findsOneWidget);
      expect(find.text('৳350'), findsOneWidget);
      expect(find.text('− ৳250'), findsOneWidget);
      expect(find.textContaining('Balance ৳350'), findsOneWidget);

      // Second instalment: the full remainder by bKash with a transaction id.
      await tester.tap(find.widgetWithText(FilledButton, 'Collect due'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Full amount'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'bKash'));
      await tester.pumpAndSettle();
      await tester.enterText(sheetField(1), 'TX778899');
      await saveSheet(tester);

      expect(world.customers.collections.last, '1 350 bkash tx=TX778899');
      expect(find.text('৳0'), findsWidgets);
      expect(find.text('Payment received · bKash'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Collect due'), findsNothing, reason: 'Nothing left to collect.');

      // Back on the list nobody owes anything.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Nobody owes you money'), findsOneWidget);
    });

    testWidgets('a role without permission sees the balance but cannot collect', (tester) async {
      final world = World();
      await world.sellOnDue('0', '1000.00');
      await open(tester, world, role: 'cashier', permissions: ['shop.view', 'pos.sell']);

      await tapQuickAction(tester, 'customers');
      await tester.tap(find.text('Karim Mia'));
      await tester.pumpAndSettle();

      expect(find.text('৳1,000'), findsWidgets);
      expect(find.widgetWithText(FilledButton, 'Collect due'), findsNothing);
      expect(find.byTooltip('Edit'), findsNothing);
    });
  });

  group('customers', () {
    testWidgets('can be searched, added with what they already owe, and edited', (tester) async {
      final world = World();
      await open(tester, world);
      await tapQuickAction(tester, 'customers');

      expect(find.text('Abdul Kader'), findsOneWidget);
      expect(find.text('Karim Mia'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '0191');
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Abdul Kader'), findsOneWidget);
      expect(find.text('Karim Mia'), findsNothing);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle(const Duration(milliseconds: 400));

      // Add: validation, then a duplicate phone refused by the server, then success.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await saveSheet(tester);
      expect(find.text('This is required'), findsOneWidget);
      expect(find.text('Enter a valid mobile number, like 01712345678'), findsOneWidget);

      await tester.enterText(sheetField(0), 'Selim');
      await tester.enterText(sheetField(1), '01812345678');
      await saveSheet(tester);
      expect(find.text('A customer with this mobile number already exists.'), findsOneWidget);

      await tester.enterText(sheetField(1), '০১৭১২৩৪৫৬৭৮');
      await tester.enterText(sheetField(3), '750');
      await saveSheet(tester);

      expect(world.customers.created.single.phone, '01712345678');
      expect(world.customers.created.single.openingDue, '750');

      // Lands on the new customer's page, with the opening balance in the ledger.
      expect(find.text('Selim'), findsOneWidget);
      expect(find.text('৳750'), findsOneWidget);
      expect(find.text('Opening balance'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Already owes (optional)'), findsNothing, reason: 'The balance cannot be edited directly.');
      await tester.enterText(sheetField(0), 'Selim Reza');
      await saveSheet(tester);
      expect(find.text('Selim Reza'), findsOneWidget);
    });

    testWidgets('an empty list explains where customers come from', (tester) async {
      final world = World();
      world.customers = FakeCustomerRepository();
      await pumpApp(tester, repository: signedInAs(), customers: world.customers, locale: 'en');
      await tapQuickAction(tester, 'customers');

      expect(find.text('No customers yet'), findsOneWidget);
    });
  });

  group('sales history', () {
    testWidgets('lists sales newest first with due and cancelled marked, and opens the invoice', (tester) async {
      final world = World();
      await world.sellOnDue('1000.00', '0.00');
      await world.sellOnDue('600.00', '400.00', uuid: 'u2');
      await world.sellOnDue('1000.00', '0.00', uuid: 'u3');
      await world.sales.voidSale(3, 'Mistake');
      await open(tester, world);

      await tapQuickAction(tester, 'sales');

      final invoices = tester.widgetList<Text>(find.textContaining('INV-')).map((t) => t.data).toList();
      expect(invoices, ['INV-000003', 'INV-000002', 'INV-000001']);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Due ৳400'), findsOneWidget);

      await tester.tap(find.text('INV-000002'));
      await tester.pumpAndSettle();
      expect(find.text('Invoice INV-000002'), findsOneWidget);
      expect(find.text('Sale completed'), findsNothing, reason: 'That banner is only for a sale just made.');
      expect(find.text('Karim Mia · 01812345678'), findsOneWidget);
    });

    testWidgets('with no sales yet it says so', (tester) async {
      await open(tester, World());
      await tapQuickAction(tester, 'sales');

      expect(find.text('No sales yet'), findsOneWidget);
    });
  });
}
