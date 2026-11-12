import 'package:dokani/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseDecimal', () {
    test('accepts plain, Bangla-digit and comma-grouped numbers', () {
      expect(Formatters.parseDecimal('62.50', maxDecimals: 2), '62.50');
      expect(Formatters.parseDecimal(' 70 ', maxDecimals: 2), '70');
      expect(Formatters.parseDecimal('১২৫.৫০', maxDecimals: 2), '125.50');
      expect(Formatters.parseDecimal('1,250', maxDecimals: 2), '1250');
      expect(Formatters.parseDecimal('0.250', maxDecimals: 3), '0.250');
      expect(Formatters.parseDecimal('0', maxDecimals: 0), '0');
    });

    test('rejects anything the server would reject', () {
      for (final bad in [null, '', '  ', 'abc', '-5', '1.2.3', '10.999', '.5', '5.', '1e3', '12 34']) {
        expect(Formatters.parseDecimal(bad, maxDecimals: 2), isNull, reason: '"$bad"');
      }
      expect(Formatters.parseDecimal('2.5', maxDecimals: 0), isNull, reason: 'whole units only');
      expect(Formatters.parseDecimal('0.0001', maxDecimals: 3), isNull);
    });
  });

  test('money drops empty decimals and uses the locale digits', () {
    expect(Formatters.money('70.00', 'en'), '৳70');
    expect(Formatters.money('62.50', 'en'), '৳62.50');
    expect(Formatters.money('1234567.89', 'en'), '৳1,234,567.89');
    expect(Formatters.money('62.50', 'bn'), '৳৬২.৫০');
    expect(Formatters.money('not a number', 'en'), '৳0');
  });

  test('quantity trims trailing zeros', () {
    expect(Formatters.quantity('10.000', 'en'), '10');
    expect(Formatters.quantity('25.500', 'en'), '25.5');
    expect(Formatters.quantity('0.250', 'en'), '0.25');
    expect(Formatters.quantity('10.000', 'bn'), '১০');
  });

  test('editable turns a stored value into what a person would type', () {
    expect(Formatters.editable('62.50'), '62.5');
    expect(Formatters.editable('70.00'), '70');
    expect(Formatters.editable('100'), '100');
    expect(Formatters.editable('0.250'), '0.25');
    expect(Formatters.editable(null), '');
  });
}
