import 'package:dokani/core/money/exact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converts decimal strings to whole paisa and back without loss', () {
    expect(Exact.paisa('62.50'), 6250);
    expect(Exact.paisa('70'), 7000);
    expect(Exact.paisa('0.05'), 5);
    expect(Exact.paisa('1234567.89'), 123456789);
    expect(Exact.paisa('-400.00'), -40000);
    expect(Exact.money(6250), '62.50');
    expect(Exact.money(5), '0.05');
    expect(Exact.money(0), '0.00');
    expect(Exact.money(-40000), '-400.00');
  });

  test('converts quantities to thousandths and back', () {
    expect(Exact.milli('2.5'), 2500);
    expect(Exact.milli('0.335'), 335);
    expect(Exact.milli('10'), 10000);
    expect(Exact.quantity(2500), '2.500');
    expect(Exact.quantity(335), '0.335');
  });

  test('a line is price × quantity rounded half-up, exactly like the server', () {
    // The same cases as the backend test "line amounts are rounded half up per line".
    expect(Exact.lineTotal(Exact.paisa('33.33'), Exact.milli('0.335')), 1117); // 11.165550 → 11.17
    expect(Exact.lineTotal(Exact.paisa('0.05'), Exact.milli('0.5')), 3); //      0.025 → 0.03
    expect(Exact.lineTotal(Exact.paisa('70'), Exact.milli('1.5')), 10500);
    expect(Exact.lineTotal(Exact.paisa('45'), Exact.milli('2')), 9000);
  });

  test('sums that floating point gets wrong are exact', () {
    // 0.1 + 0.2 != 0.3 in doubles.
    expect(Exact.paisa('0.10') + Exact.paisa('0.20'), Exact.paisa('0.30'));
    expect(Exact.money(List.filled(10, Exact.paisa('0.10')).reduce((a, b) => a + b)), '1.00');
  });

  test('generates distinct version-4 UUIDs', () {
    final ids = {for (var i = 0; i < 200; i++) Exact.uuid()};
    expect(ids, hasLength(200));
    expect(ids.every(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch), isTrue);
  });
}
