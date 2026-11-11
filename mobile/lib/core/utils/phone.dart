/// Bangladeshi mobile numbers. Mirrors the server's rules (App\Support\Phone)
/// so the app rejects a bad number before making a request.
class Phone {
  const Phone._();

  static const _bengaliDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
  static final _valid = RegExp(r'^01[3-9]\d{8}$');

  /// Returns the canonical form (01XXXXXXXXX), or null when the input is not
  /// a valid number. Accepts +880 / 880 prefixes, spaces, dashes and Bengali digits.
  static String? normalize(String? input) {
    if (input == null) return null;

    var value = input.trim();
    for (var i = 0; i < _bengaliDigits.length; i++) {
      value = value.replaceAll(_bengaliDigits[i], '$i');
    }
    value = value.replaceAll(RegExp(r'[\s\-().]'), '');

    if (value.startsWith('+')) value = value.substring(1);
    if (value.startsWith('8801')) value = value.substring(2);

    return _valid.hasMatch(value) ? value : null;
  }

  static bool isValid(String? input) => normalize(input) != null;
}
