import 'package:intl/intl.dart';

/// Number input and display helpers.
///
/// Amounts and quantities travel between the app and the server as decimal
/// strings ("62.50", "0.250") and are never added or multiplied as doubles
/// here; doubles are used only to draw an already-final value.
class Formatters {
  const Formatters._();

  static const _bengaliDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

  /// Shop owners often type with a Bangla keyboard: ১২৫.৫০ → 125.50.
  static String toAsciiDigits(String input) {
    var value = input;
    for (var i = 0; i < _bengaliDigits.length; i++) {
      value = value.replaceAll(_bengaliDigits[i], '$i');
    }
    return value;
  }

  /// Cleans a typed number. Returns the canonical form the server accepts,
  /// or null when it is not a non-negative number with at most [maxDecimals]
  /// decimal places.
  static String? parseDecimal(String? input, {required int maxDecimals}) {
    if (input == null) return null;
    final value = toAsciiDigits(input.trim()).replaceAll(',', '');
    if (value.isEmpty) return null;

    final pattern = maxDecimals == 0 ? RegExp(r'^\d{1,9}$') : RegExp('^\\d{1,9}(\\.\\d{1,$maxDecimals})?\$');
    return pattern.hasMatch(value) ? value : null;
  }

  /// "62.50" → ৳62.50, "70.00" → ৳70 (digits in the locale's script).
  static String money(String amount, String locale) {
    final value = double.tryParse(amount) ?? 0;
    final hasFraction = value != value.truncateToDouble();
    final format = NumberFormat.decimalPattern(locale)
      ..minimumFractionDigits = hasFraction ? 2 : 0
      ..maximumFractionDigits = 2;
    return '৳${format.format(value)}';
  }

  /// "25.500" → 25.5, "10.000" → 10.
  static String quantity(String quantity, String locale) {
    final value = double.tryParse(quantity) ?? 0;
    final format = NumberFormat.decimalPattern(locale)
      ..minimumFractionDigits = 0
      ..maximumFractionDigits = 3;
    return format.format(value);
  }

  /// A stored value as plain text for an input field: "62.50" → "62.5", "10.000" → "10".
  static String editable(String? stored) {
    if (stored == null || stored.isEmpty) return '';
    if (!stored.contains('.')) return stored;
    return stored.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  /// True when [a] is numerically smaller than [b]. For on-screen hints only.
  static bool isLess(String a, String b) => (double.tryParse(a) ?? 0) < (double.tryParse(b) ?? 0);
}
