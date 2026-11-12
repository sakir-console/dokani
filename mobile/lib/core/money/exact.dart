import 'dart:math';

/// Exact arithmetic for the cart.
///
/// Money is held as whole paisa and quantity as thousandths of a unit, both
/// plain integers, so 0.1 + 0.2 style floating-point errors cannot happen.
/// The rounding rule is the server's: each line is rounded half-up to paisa.
class Exact {
  const Exact._();

  /// "62.50" → 6250. The input is a canonical decimal string (see Formatters.parseDecimal).
  static int paisa(String amount) => _scaled(amount, 2);

  /// "2.5" → 2500.
  static int milli(String quantity) => _scaled(quantity, 3);

  /// 6250 → "62.50"
  static String money(int paisa) => _unscaled(paisa, 2);

  /// 2500 → "2.500"
  static String quantity(int milli) => _unscaled(milli, 3);

  /// Price × quantity, rounded half-up to the paisa — the same rule as the server.
  static int lineTotal(int unitPricePaisa, int quantityMilli) => (unitPricePaisa * quantityMilli + 500) ~/ 1000;

  static int _scaled(String value, int decimals) {
    final negative = value.startsWith('-');
    final parts = (negative ? value.substring(1) : value).split('.');
    final whole = int.tryParse(parts[0].isEmpty ? '0' : parts[0]) ?? 0;
    final fraction = (parts.length > 1 ? parts[1] : '').padRight(decimals, '0').substring(0, decimals);
    final result = whole * pow(10, decimals).toInt() + (int.tryParse(fraction) ?? 0);
    return negative ? -result : result;
  }

  static String _unscaled(int value, int decimals) {
    final scale = pow(10, decimals).toInt();
    final sign = value < 0 ? '-' : '';
    final absolute = value.abs();
    return '$sign${absolute ~/ scale}.${(absolute % scale).toString().padLeft(decimals, '0')}';
  }

  /// A random version-4 UUID. Identifies one sale or one payment so that
  /// sending it twice (a retry on a bad connection) records it once.
  static String uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
