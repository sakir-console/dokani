import 'package:dokani/core/utils/phone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phone.normalize', () {
    const canonical = '01712345678';

    for (final input in [
      '01712345678',
      '+8801712345678',
      '8801712345678',
      '017 1234-5678',
      '০১৭১২৩৪৫৬৭৮',
      '  01712345678 ',
    ]) {
      test('accepts "$input"', () => expect(Phone.normalize(input), canonical));
    }

    for (final input in [
      null,
      '',
      '0171234567', // too short
      '017123456789', // too long
      '01212345678', // not a mobile operator prefix
      '0212345678', // landline
      '01712abc678',
      '+911712345678',
    ]) {
      test('rejects "$input"', () => expect(Phone.normalize(input), isNull));
    }
  });
}
