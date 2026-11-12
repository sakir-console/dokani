import 'package:dokani/features/notifications/data/notification_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';
import '../../support/sync_fakes.dart';

void main() {
  ShopNotice conflict({bool read = false}) => ShopNotice(
        id: 1,
        type: 'stock_conflict',
        title: 'A sale made offline sold more than was in stock',
        body: 'INV-000012: check the stock of Lux Soap.',
        read: read,
        createdAt: DateTime(2026, 11, 12, 10, 30),
      );

  test('a notice from the server is read with the sale it is about', () {
    final notice = ShopNotice.fromJson({
      'id': 4,
      'type': 'stock_conflict',
      'title': 'A sale made offline sold more than was in stock',
      'body': 'INV-000012: check the stock of Lux Soap.',
      'data': {'sale_id': 12, 'invoice_no': 'INV-000012', 'products': ['Lux Soap']},
      'read': false,
      'created_at': '2026-11-12T04:30:00+00:00',
    });

    expect(notice.saleId, 12);
    expect(notice.read, isFalse);
    expect(notice.createdAt.toUtc(), DateTime.utc(2026, 11, 12, 4, 30));
    expect(ShopNotice.fromJson({'id': 5, 'type': 'other', 'title': 'x', 'data': null, 'created_at': null}).saleId, isNull);
  });

  testWidgets('home shows how many alerts are unread; reading them clears the count', (tester) async {
    final notices = FakeNotificationRepository([conflict()]);
    await pumpApp(tester, repository: signedInAs(), locale: 'en', notices: notices);

    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(badge.isLabelVisible, isTrue);
    expect(find.descendant(of: find.byType(Badge), matching: find.text('1')), findsOneWidget);

    await tester.tap(find.byTooltip('Alerts'));
    await tester.pumpAndSettle();
    expect(find.text('A sale made offline sold more than was in stock'), findsOneWidget);
    expect(find.textContaining('check the stock of Lux Soap'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Mark all as read'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Mark all as read'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
  });

  testWidgets('with no alerts the screen says what would appear there', (tester) async {
    await pumpApp(tester, repository: signedInAs(), locale: 'en');

    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    await tester.tap(find.byTooltip('Alerts'));
    await tester.pumpAndSettle();

    expect(find.text('No alerts'), findsOneWidget);
  });

  testWidgets('without a connection the bell has no count and the screen offers a retry', (tester) async {
    final notices = FakeNotificationRepository([conflict()])..offline = true;
    await pumpApp(tester, repository: signedInAs(), locale: 'en', notices: notices);

    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    await tester.tap(find.byTooltip('Alerts'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Try again'), findsOneWidget);

    notices.offline = false;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Try again'));
    await tester.pumpAndSettle();
    expect(find.text('A sale made offline sold more than was in stock'), findsOneWidget);
  });

  testWidgets('a suspended shop has no alerts button', (tester) async {
    await pumpApp(tester, repository: signedInAs(status: 'suspended'), locale: 'en');

    expect(find.byTooltip('Alerts'), findsNothing);
  });
}
