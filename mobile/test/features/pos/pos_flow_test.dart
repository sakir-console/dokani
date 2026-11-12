import 'package:dokani/core/network/api_exception.dart';
import 'package:dokani/features/catalog/data/models.dart';
import 'package:dokani/features/customers/data/customer_repository.dart';
import 'package:dokani/features/pos/data/sale_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../support/catalog_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/sales_fakes.dart';

/// A small shop: soap ৳45 (3 in stock), rice ৳70/kg, a T-shirt in two sizes,
/// sugar that is out of stock, and one customer who already owes ৳150.
class Shop {
  Shop({bool showProfit = true}) {
    catalog = FakeCatalogRepository(
      products: [
        makeProduct(id: 1, name: 'Lux Soap', variants: [makeVariant(id: 10, price: '45.00', stock: '3.000', barcodes: ['SOAP'])]),
        makeProduct(id: 2, name: 'Miniket Rice', unit: kilogram, variants: [makeVariant(id: 20, price: '70.00', stock: '50.000', barcodes: ['RICE'])]),
        makeProduct(
          id: 3,
          name: 'Polo T-shirt',
          variants: [
            makeVariant(id: 30, name: 'S', price: '350.00', stock: '4.000', barcodes: ['TS-S']),
            makeVariant(id: 31, name: 'M', price: '370.00', stock: '6.000', barcodes: ['TS-M']),
          ],
        ),
        makeProduct(id: 4, name: 'Sugar', unit: kilogram, variants: [makeVariant(id: 40, price: '135.00', stock: '0.000', status: StockStatus.out)]),
        makeProduct(id: 5, name: 'Rice Cooker', variants: [makeVariant(id: 50, price: '1000.00', stock: '5.000')]),
      ],
    );
    customers = FakeCustomerRepository([const Customer(id: 1, name: 'Karim Mia', phone: '01812345678', currentDue: '150.00')]);
    sales = FakeSalesRepository(catalog: catalog, customers: customers, showProfit: showProfit);
  }

  late final FakeCatalogRepository catalog;
  late final FakeCustomerRepository customers;
  late final FakeSalesRepository sales;
}

Future<Shop> openPos(WidgetTester tester, {Shop? shop, String role = 'owner', List<String> scanCodes = const [], Outbox? outbox, List<String>? permissions}) async {
  final s = shop ?? Shop(showProfit: role == 'owner');
  await pumpApp(
    tester,
    repository: signedInAs(role: role, permissions: permissions ?? (role == 'owner' ? null : ['shop.view', 'pos.sell', 'customers.manage', 'due.collect'])),
    catalog: s.catalog,
    customers: s.customers,
    sales: s.sales,
    locale: 'en',
    scanCodes: scanCodes,
    outbox: outbox,
  );
  await tapQuickAction(tester, 'new-sale');
  return s;
}

Future<void> addToCart(WidgetTester tester, String product, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.text(product));
    await tester.pumpAndSettle();
  }
}

Future<void> goToCheckout(WidgetTester tester) async {
  await tester.tap(find.text('View cart'));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Checkout ·'));
  await tester.pumpAndSettle();
}

Future<void> complete(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Complete sale');
  await tester.ensureVisible(button);
  await tester.tap(button);
  // Covers the customer lookup's short delay as well as the request.
  await tester.pumpAndSettle(const Duration(milliseconds: 500));
}

/// The text field under a label on the checkout screen.
Finder field(String label, {int at = 0}) => find.descendant(
      of: find.ancestor(of: find.text(label).at(at), matching: find.byType(Column)).first,
      matching: find.byType(TextFormField),
    );

Future<void> type(WidgetTester tester, String label, String value, {int at = 0}) async {
  final target = field(label, at: at).first;
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
  await tester.pumpAndSettle(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('an ordinary cash sale is: tap, tap, checkout, complete — and needs no customer', (tester) async {
    final shop = await openPos(tester);

    await addToCart(tester, 'Lux Soap', times: 2);
    expect(find.text('× 2'), findsOneWidget);
    expect(find.text('1 items · ৳90'), findsOneWidget);

    await goToCheckout(tester);
    expect(find.text('৳90'), findsWidgets);
    expect(find.text("Customer's mobile number"), findsNothing, reason: 'A fully paid sale does not ask for a customer.');

    await complete(tester);

    final draft = shop.sales.received.single;
    expect(draft.items.single.variantId, 10);
    expect(draft.items.single.quantity, '2.000');
    expect(draft.items.single.unitPrice, '45.00');
    expect(draft.grandTotal, '90.00');
    expect(draft.dueAmount, '0.00');
    expect(draft.customerPhone, isNull);
    expect(draft.payments.single.method, PaymentMethod.cash);
    expect(draft.payments.single.amount, '90.00');

    // Lands on the invoice.
    expect(find.text('Sale completed'), findsOneWidget);
    expect(find.text('Invoice INV-000001'), findsOneWidget);
    expect(find.text('Walk-in customer'), findsOneWidget);
    expect(find.text('Paid · Cash'), findsOneWidget);

    // The cart is empty for the next customer.
    await tester.tap(find.widgetWithText(FilledButton, 'New sale'));
    await tester.pumpAndSettle();
    expect(find.text('View cart'), findsNothing);
  });

  testWidgets('cash received above the bill shows the change to hand back', (tester) async {
    final shop = await openPos(tester);
    await addToCart(tester, 'Lux Soap', times: 2); // ৳90
    await goToCheckout(tester);

    await type(tester, 'Cash received', '500');
    expect(find.text('Change to return'), findsOneWidget);
    expect(find.text('৳410'), findsOneWidget);
    expect(find.text('Due'), findsNothing);

    await complete(tester);
    final payment = shop.sales.received.single.payments.single;
    expect(payment.amount, '90.00', reason: 'Only the bill is recorded as paid, not the note handed over.');
    expect(payment.receivedAmount, '500.00');
    expect(find.text('Change to return'), findsOneWidget); // on the invoice too
  });

  testWidgets('a partial payment leaves a due, which requires the customer', (tester) async {
    // Grand total 1,000 · paid 600 · due 400
    final shop = await openPos(tester);
    await addToCart(tester, 'Rice Cooker');
    await goToCheckout(tester);

    await type(tester, 'Cash received', '600');
    expect(find.text('৳400'), findsOneWidget);
    expect(find.textContaining('will stay due'), findsOneWidget);

    // Without a phone number the sale cannot be completed.
    await complete(tester);
    expect(find.text('This is required'), findsOneWidget);
    expect(shop.sales.received, isEmpty);

    await type(tester, "Customer's mobile number", '123');
    await complete(tester);
    expect(find.text('Enter a valid mobile number, like 01712345678'), findsOneWidget);
    expect(shop.sales.received, isEmpty);

    // An existing customer is recognised by phone and shown with what they already owe.
    await type(tester, "Customer's mobile number", '+880 1812-345678');
    expect(find.text('Karim Mia · already owes ৳150'), findsOneWidget);
    expect(find.text("Customer's name"), findsNothing);

    await complete(tester);
    final draft = shop.sales.received.single;
    expect(draft.payments.single.amount, '600.00');
    expect(draft.dueAmount, '400.00');
    expect(draft.customerPhone, '01812345678');

    expect(find.text('Karim Mia · 01812345678'), findsOneWidget);
    expect(find.text('Due'), findsOneWidget);
    expect((await shop.customers.lookup('01812345678'))!.currentDue, '550.00');
  });

  testWidgets('a new phone number asks for the name and creates the customer', (tester) async {
    final shop = await openPos(tester);
    await addToCart(tester, 'Rice Cooker');
    await goToCheckout(tester);

    await type(tester, 'Cash received', '0');
    await type(tester, "Customer's mobile number", '01999999999');
    expect(find.textContaining('New customer'), findsOneWidget);

    await complete(tester);
    expect(find.text('This is required'), findsOneWidget, reason: 'A new customer needs a name.');
    expect(shop.sales.received, isEmpty);

    await type(tester, "Customer's name", 'Rahim Uddin');
    await complete(tester);

    final draft = shop.sales.received.single;
    expect(draft.payments, isEmpty, reason: 'Everything is on due: no payment rows.');
    expect(draft.dueAmount, '1000.00');
    expect(draft.customerName, 'Rahim Uddin');

    final created = await shop.customers.lookup('01999999999');
    expect(created!.name, 'Rahim Uddin');
    expect(created.currentDue, '1000.00');
  });

  testWidgets('split payment: cash 500, bKash 200, due 300', (tester) async {
    final shop = await openPos(tester);
    await addToCart(tester, 'Rice Cooker');
    await goToCheckout(tester);

    await type(tester, 'Cash received', '500');
    await tester.tap(find.textContaining('Add bKash'));
    await tester.pumpAndSettle();
    await type(tester, 'Amount', '200');
    await type(tester, 'Transaction ID (optional)', '9XK2L0AB');

    expect(find.text('৳700'), findsOneWidget); // paid
    expect(find.text('৳300'), findsOneWidget); // due

    await type(tester, "Customer's mobile number", '01812345678');
    await complete(tester);

    final draft = shop.sales.received.single;
    expect(draft.payments.map((p) => '${p.method.name}:${p.amount}'), ['cash:500.00', 'bkash:200.00']);
    expect(draft.payments[1].transactionId, '9XK2L0AB');
    expect(draft.dueAmount, '300.00');

    // The invoice lists each method and does not pretend bKash was verified.
    expect(find.text('Paid · bKash'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Entered by hand'), 200, scrollable: find.byType(Scrollable).first);
  });

  testWidgets('non-cash payments above the total are refused on the spot', (tester) async {
    final shop = await openPos(tester);
    await addToCart(tester, 'Lux Soap'); // ৳45
    await goToCheckout(tester);

    await type(tester, 'Cash received', '0');
    await tester.tap(find.textContaining('Add bKash'));
    await tester.pumpAndSettle();
    await type(tester, 'Amount', '100');

    expect(find.text('The payments are more than the total'), findsOneWidget);
    await complete(tester);
    expect(shop.sales.received, isEmpty);
  });

  testWidgets('a product with variants asks which one', (tester) async {
    final shop = await openPos(tester);

    await tester.tap(find.text('Polo T-shirt'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a variant'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'M'));
    await tester.pumpAndSettle();

    expect(find.text('1 items · ৳370'), findsOneWidget);
    await goToCheckout(tester);
    await complete(tester);
    expect(shop.sales.received.single.items.single.variantId, 31);
    expect(find.text('Polo T-shirt — M'), findsOneWidget);
  });

  testWidgets('stock limits what can be added', (tester) async {
    await openPos(tester);

    await addToCart(tester, 'Sugar');
    expect(find.textContaining('Only 0 Kilogram in stock'), findsOneWidget);
    expect(find.text('View cart'), findsNothing);

    await addToCart(tester, 'Lux Soap', times: 4); // only 3 in stock
    expect(find.text('× 3'), findsOneWidget);
    expect(find.textContaining('Only 3 Piece in stock'), findsOneWidget);
  });

  testWidgets('the cart edits quantities, discount and charge with exact totals', (tester) async {
    final shop = await openPos(tester);
    await addToCart(tester, 'Miniket Rice');
    await addToCart(tester, 'Lux Soap');
    await tester.tap(find.text('View cart'));
    await tester.pumpAndSettle();

    // Type an exact weight for the rice: 2.5 kg × 70 = 175.
    await tester.tap(find.widgetWithText(TextButton, '1').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '২.৫');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('৳175'), findsOneWidget);

    // + on the soap: 2 × 45 = 90. Subtotal 265.
    await tester.tap(find.byTooltip('+').last);
    await tester.pumpAndSettle();
    expect(find.text('৳265'), findsWidgets);

    Future<void> setAmount(String row, String amount) async {
      await tester.ensureVisible(find.text(row));
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), amount);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
    }

    await setAmount('Discount', '300');
    expect(find.text('The discount is larger than the amount'), findsOneWidget);

    await setAmount('Discount', '15');
    await setAmount('Additional charge', '20');
    expect(find.text('− ৳15'), findsOneWidget);
    expect(find.text('Checkout · ৳270'), findsOneWidget); // 265 − 15 + 20

    // Remove the soap: 175 − 15 + 20 = 180.
    await tester.tap(find.byTooltip('Remove').last);
    await tester.pumpAndSettle();
    expect(find.text('৳180'), findsOneWidget);
    expect(find.text('Checkout · ৳180'), findsOneWidget);

    await tester.tap(find.text('Checkout · ৳180'));
    await tester.pumpAndSettle();
    await complete(tester);

    final draft = shop.sales.received.single;
    expect(draft.items.single.quantity, '2.500');
    expect(draft.discountAmount, '15.00');
    expect(draft.additionalCharge, '20.00');
    expect(draft.grandTotal, '180.00');
    expect(find.text('Sale completed'), findsOneWidget, reason: 'The server agreed with the app\'s total.');
  });

  testWidgets('scanning a basket adds each product; the same barcode twice counts twice', (tester) async {
    final shop = Shop();
    await pumpApp(
      tester,
      repository: signedInAs(),
      catalog: shop.catalog,
      customers: shop.customers,
      sales: shop.sales,
      locale: 'en',
      scanCodes: ['SOAP', 'TS-M', 'SOAP', 'NOT-A-PRODUCT', 'RICE'],
    );
    await tapQuickAction(tester, 'new-sale');

    await tester.tap(find.byTooltip('Scan barcode'));
    await tester.pumpAndSettle();

    // 2 × 45 + 370 + 70 = 530, in three lines; the unknown code added nothing.
    expect(find.text('3 items · ৳530'), findsOneWidget);
    expect(find.text('× 2'), findsOneWidget);

    await goToCheckout(tester);
    await complete(tester);
    expect(shop.sales.received.single.items.map((i) => '${i.variantId}×${i.quantity}'), ['10×2.000', '31×1.000', '20×1.000']);
  });

  testWidgets('a refusal from the server is shown, the cart is kept, and the retry is the same sale', (tester) async {
    final shop = await openPos(tester);
    await addToCart(tester, 'Lux Soap');
    await goToCheckout(tester);

    shop.sales.failNext = const ApiException(kind: ApiErrorKind.network);
    await complete(tester);
    expect(find.text('No internet connection. Check your connection and try again.'), findsOneWidget);
    expect(find.text('Complete sale'), findsOneWidget);

    await complete(tester);
    expect(find.text('Sale completed'), findsOneWidget);
    expect(shop.sales.received, hasLength(2));
    expect(shop.sales.received[0].clientUuid, shop.sales.received[1].clientUuid, reason: 'A retry must not become a second sale.');
    expect(shop.sales.all, hasLength(1));
  });

  testWidgets('a price that changed on the server stops the sale with an explanation', (tester) async {
    final shop = await openPos(tester);
    await addToCart(tester, 'Lux Soap');
    await goToCheckout(tester);

    shop.sales.failNext = const ApiException(
      kind: ApiErrorKind.server,
      statusCode: 422,
      code: 'TOTALS_MISMATCH',
      message: 'The total has changed to 50.00. Check the bill and try again.',
    );
    await complete(tester);

    expect(find.text('The total has changed to 50.00. Check the bill and try again.'), findsOneWidget);
    expect(shop.sales.all, isEmpty);
  });

  testWidgets('the invoice can be shared and opened as PDF, and shows a QR code', (tester) async {
    final outbox = Outbox();
    await openPos(tester, outbox: outbox);
    await addToCart(tester, 'Lux Soap');
    await goToCheckout(tester);
    await complete(tester);

    await tester.scrollUntilVisible(find.text('Share'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Scan to view this invoice'), findsOneWidget);

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(outbox.shared.single, contains('INV-000001'));
    expect(outbox.shared.single, contains('৳45'));
    expect(outbox.shared.single, contains('https://dokani.test/i/token-1'));

    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    expect(outbox.opened.single.toString(), 'https://dokani.test/i/token-1/pdf');
  });

  testWidgets('the owner can cancel a sale from its invoice; a cashier cannot', (tester) async {
    final shop = await openPos(tester);
    await addToCart(tester, 'Lux Soap');
    await goToCheckout(tester);
    await complete(tester);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel sale').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Customer changed their mind');
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel sale'));
    await tester.pumpAndSettle();

    expect(shop.sales.voided, ['1 Customer changed their mind']);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing, reason: 'A cancelled sale cannot be cancelled again.');
  });

  testWidgets('a cashier can sell but sees no profit and no cancel option', (tester) async {
    await openPos(tester, role: 'cashier');
    await addToCart(tester, 'Lux Soap');
    await goToCheckout(tester);
    await complete(tester);

    expect(find.text('Sale completed'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Sales'), findsWidgets);
    expect(find.text('Profit'), findsNothing);
  });
}
