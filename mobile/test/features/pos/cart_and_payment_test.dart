import 'package:dokani/core/money/exact.dart';
import 'package:dokani/features/pos/application/cart_controller.dart';
import 'package:dokani/features/pos/application/payment_plan.dart';
import 'package:dokani/features/pos/data/sale_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/catalog_fakes.dart';

void main() {
  group('cart', () {
    late ProviderContainer container;
    CartController cart() => container.read(cartProvider.notifier);
    CartState state() => container.read(cartProvider);

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    final soap = makeProduct(id: 1, name: 'Lux Soap', variants: [makeVariant(id: 10, price: '45.00', stock: '3.000')]);
    final rice = makeProduct(id: 2, name: 'Rice', unit: kilogram, variants: [makeVariant(id: 20, price: '70.00', stock: '50.000')]);
    final shirt = makeProduct(id: 3, name: 'Polo', variants: [makeVariant(id: 30, name: 'S', price: '350.00'), makeVariant(id: 31, name: 'M', price: '370.00')]);

    test('adding the same product again increases its quantity', () {
      expect(cart().add(soap, soap.variants[0]), CartAddResult.added);
      expect(cart().add(soap, soap.variants[0]), CartAddResult.added);

      expect(state().lines, hasLength(1));
      expect(state().lines.single.quantityMilli, 2000);
      expect(state().subtotalPaisa, 9000);
    });

    test('variants are separate lines with their own price', () {
      cart().add(shirt, shirt.variants[0]);
      cart().add(shirt, shirt.variants[1]);
      cart().add(shirt, shirt.variants[1]);

      expect(state().lines.map((l) => l.title), ['Polo — S', 'Polo — M']);
      expect(state().subtotalPaisa, 35000 + 2 * 37000);
    });

    test('cannot add more than the stock unless the shop allows it', () {
      for (var i = 0; i < 3; i++) {
        expect(cart().add(soap, soap.variants[0]), CartAddResult.added);
      }
      expect(cart().add(soap, soap.variants[0]), CartAddResult.outOfStock);
      expect(state().lines.single.quantityMilli, 3000);

      expect(cart().setQuantity(10, 4000), isFalse);
      expect(cart().setQuantity(10, 4000, allowNegativeStock: true), isTrue);
      expect(cart().add(soap, soap.variants[0], allowNegativeStock: true), CartAddResult.added);
      expect(state().lines.single.quantityMilli, 5000);
    });

    test('quantities can be fractional and a zero quantity removes the line', () {
      cart().add(rice, rice.variants[0]);
      expect(cart().setQuantity(20, Exact.milli('1.5')), isTrue);
      expect(state().lines.single.totalPaisa, 10500);

      expect(cart().setQuantity(20, 0), isTrue);
      expect(state().isEmpty, isTrue);
    });

    test('totals: the example from the brief', () {
      // Subtotal 1,200 − discount 100 + charge 20 = 1,120
      final item = makeProduct(id: 9, variants: [makeVariant(id: 90, price: '600.00', stock: '5.000')]);
      cart().add(item, item.variants[0]);
      cart().add(item, item.variants[0]);
      expect(cart().setDiscount(Exact.paisa('100')), isTrue);
      cart().setCharge(Exact.paisa('20'));

      expect(Exact.money(state().subtotalPaisa), '1200.00');
      expect(Exact.money(state().grandTotalPaisa), '1120.00');
    });

    test('a discount larger than the subtotal is refused, and shrinks when items are removed', () {
      cart().add(soap, soap.variants[0]); // 45
      cart().add(rice, rice.variants[0]); // 70
      expect(cart().setDiscount(Exact.paisa('115.01')), isFalse);
      expect(cart().setDiscount(Exact.paisa('100')), isTrue);

      cart().remove(20); // only 45 left
      expect(state().discountPaisa, 4500);
      expect(state().grandTotalPaisa, 0);
    });

    test('clear empties everything', () {
      cart().add(soap, soap.variants[0]);
      cart().setCharge(500);
      cart().clear();

      expect(state().isEmpty, isTrue);
      expect(state().grandTotalPaisa, 0);
    });
  });

  group('payment plan', () {
    PaymentPlan plan(String total, String cash, [List<(PaymentMethod, String)> others = const []]) => PaymentPlan(
          totalPaisa: Exact.paisa(total),
          cashReceivedPaisa: Exact.paisa(cash),
          others: [for (final (method, amount) in others) OtherPayment(method: method, amountPaisa: Exact.paisa(amount))],
        );

    void expectBalanced(PaymentPlan p) =>
        expect(p.paidPaisa + p.duePaisa, p.totalPaisa, reason: 'Total must always equal paid + due.');

    test('exact cash: paid in full, no change, no due', () {
      final p = plan('500', '500');
      expect([p.paidPaisa, p.changePaisa, p.duePaisa], [50000, 0, 0]);
      expect(p.hasDue, isFalse);
      expectBalanced(p);
    });

    test('bill 500, received 1,000, change 500', () {
      final p = plan('500', '1000');
      expect(Exact.money(p.cashAppliedPaisa), '500.00');
      expect(Exact.money(p.changePaisa), '500.00');
      expect(p.duePaisa, 0);
      expectBalanced(p);
    });

    test('partial payment: total 1,000, paid 600, due 400', () {
      final p = plan('1000', '600');
      expect(Exact.money(p.paidPaisa), '600.00');
      expect(Exact.money(p.duePaisa), '400.00');
      expect(p.changePaisa, 0);
      expect(p.hasDue, isTrue);
      expectBalanced(p);
    });

    test('split payment: cash 500, bKash 200, due 300', () {
      final p = plan('1000', '500', [(PaymentMethod.bkash, '200')]);
      expect(Exact.money(p.paidPaisa), '700.00');
      expect(Exact.money(p.duePaisa), '300.00');
      expectBalanced(p);
    });

    test('mobile money is applied first and cash beyond the rest is change', () {
      final p = plan('1000', '500', [(PaymentMethod.bkash, '700')]);
      expect(Exact.money(p.cashAppliedPaisa), '300.00');
      expect(Exact.money(p.changePaisa), '200.00');
      expect(p.duePaisa, 0);
      expectBalanced(p);
    });

    test('everything on due', () {
      final p = plan('1000', '0');
      expect(p.paidPaisa, 0);
      expect(Exact.money(p.duePaisa), '1000.00');
      expectBalanced(p);
    });

    test('non-cash payments above the total are invalid', () {
      final p = plan('1000', '0', [(PaymentMethod.bkash, '600'), (PaymentMethod.nagad, '500')]);
      expect(p.othersExceedTotal, isTrue);
      expect(p.isValid, isFalse);
    });

    test('a free sale needs no payment', () {
      final p = plan('0', '0');
      expect([p.paidPaisa, p.duePaisa, p.changePaisa], [0, 0, 0]);
      expect(p.isValid, isTrue);
    });
  });

  test('the sale request carries the customer only when there is one', () {
    const walkIn = SaleDraft(
      clientUuid: 'u', grandTotal: '60.00', dueAmount: '0.00',
      items: [SaleLineDraft(variantId: 1, quantity: '1.000', unitPrice: '60.00')],
      payments: [PaymentDraft(method: PaymentMethod.cash, amount: '60.00', receivedAmount: '100.00')],
    );
    expect(walkIn.toJson().containsKey('customer'), isFalse);
    expect((walkIn.toJson()['payments'] as List).single, {'method': 'cash', 'amount': '60.00', 'received_amount': '100.00'});

    const onDue = SaleDraft(
      clientUuid: 'u', grandTotal: '60.00', dueAmount: '60.00', items: [], payments: [],
      customerPhone: '01712345678', customerName: 'Rahim',
    );
    expect(onDue.toJson()['customer'], {'phone': '01712345678', 'name': 'Rahim'});
    expect(onDue.toJson()['payments'], isEmpty);
  });
}
