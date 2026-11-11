import '../../l10n/app_localizations.dart';
import 'phone.dart';

/// Form validators. Each returns null when the value is acceptable.
class Validators {
  const Validators(this.l10n);

  final AppLocalizations l10n;

  static const passwordMinLength = 8;
  static const otpLength = 6;

  String? required(String? value) => (value == null || value.trim().isEmpty) ? l10n.errRequired : null;

  String? phone(String? value) {
    if (value == null || value.trim().isEmpty) return l10n.errRequired;
    return Phone.isValid(value) ? null : l10n.errPhone;
  }

  String? password(String? value) {
    if (value == null || value.isEmpty) return l10n.errRequired;
    return value.length < passwordMinLength ? l10n.errPasswordShort(passwordMinLength) : null;
  }

  String? otp(String? value) {
    final digits = value?.trim() ?? '';
    return RegExp('^\\d{$otpLength}\$').hasMatch(digits) ? null : l10n.errOtp(otpLength);
  }
}
