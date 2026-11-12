import '../../../l10n/app_localizations.dart';
import '../data/sale_models.dart';

String paymentMethodLabel(PaymentMethod method, AppLocalizations l10n) => switch (method) {
      PaymentMethod.cash => l10n.methodCash,
      PaymentMethod.bkash => l10n.methodBkash,
      PaymentMethod.nagad => l10n.methodNagad,
      PaymentMethod.bank => l10n.methodBank,
      PaymentMethod.card => l10n.methodCard,
      PaymentMethod.other => l10n.methodOther,
    };

String ledgerTypeLabel(String type, AppLocalizations l10n) => switch (type) {
      'opening' => l10n.ledgerOpening,
      'sale_due' => l10n.ledgerSaleDue,
      'payment' => l10n.ledgerPayment,
      'sale_void' => l10n.ledgerSaleVoid,
      _ => l10n.ledgerAdjustment,
    };
