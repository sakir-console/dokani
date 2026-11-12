import 'package:flutter/foundation.dart';

import '../data/sale_models.dart';

/// A non-cash payment entered at checkout.
@immutable
class OtherPayment {
  const OtherPayment({required this.method, required this.amountPaisa, this.transactionId});

  final PaymentMethod method;
  final int amountPaisa;
  final String? transactionId;
}

/// Works out who pays what at checkout.
///
/// Mobile-money, bank and card amounts are applied first, exactly as entered.
/// Cash covers the rest; cash handed over beyond that is change, not payment.
/// Whatever is still uncovered is the due.
///
///   total = other payments + cash applied + due      (always)
@immutable
class PaymentPlan {
  const PaymentPlan({required this.totalPaisa, required this.cashReceivedPaisa, this.others = const []});

  final int totalPaisa;
  final int cashReceivedPaisa;
  final List<OtherPayment> others;

  int get otherPaisa => others.fold(0, (sum, payment) => sum + payment.amountPaisa);

  /// Non-cash payments may not exceed the bill: there is no change from bKash.
  bool get othersExceedTotal => otherPaisa > totalPaisa;

  int get _remainingAfterOthers => othersExceedTotal ? 0 : totalPaisa - otherPaisa;

  /// The part of the cash that pays the bill.
  int get cashAppliedPaisa => cashReceivedPaisa < _remainingAfterOthers ? cashReceivedPaisa : _remainingAfterOthers;

  int get changePaisa => cashReceivedPaisa - cashAppliedPaisa;

  int get paidPaisa => (othersExceedTotal ? 0 : otherPaisa) + cashAppliedPaisa;

  int get duePaisa => totalPaisa - paidPaisa;

  bool get hasDue => duePaisa > 0;

  /// A sale can be completed when the payments make sense. A due additionally
  /// needs a customer, which the checkout screen checks.
  bool get isValid => !othersExceedTotal;
}
