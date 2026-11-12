import 'package:dokani/core/network/api_exception.dart';
import 'package:dokani/features/reports/data/report_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';
import '../../support/report_fakes.dart';

const withReports = ['products', 'pos', 'customers', 'offline', 'reports'];
const withExports = [...withReports, 'exports'];

Future<FakeReportRepository> openReports(WidgetTester tester, {List<String> modules = withExports, Outbox? outbox}) async {
  final reports = FakeReportRepository();
  await pumpApp(tester, repository: signedInAs(modules: modules), reports: reports, locale: 'en', outbox: outbox);
  await tapQuickAction(tester, 'reports');
  return reports;
}

void main() {
  group('models', () {
    test('a preset period sends only its key; a custom one sends whole dates', () {
      expect(const ReportRange(ReportRangeKey.last7Days).toQuery(), {'range': 'last_7_days'});
      expect(
        ReportRange(ReportRangeKey.custom, from: DateTime(2026, 3, 1), to: DateTime(2026, 3, 9, 23, 59)).toQuery(),
        {'range': 'custom', 'from': '2026-03-01', 'to': '2026-03-09'},
      );
    });

    test('parses the summary and the period the server used', () {
      final summary = ReportSummary.fromJson({
        'data': {
          'orders': 2, 'items_sold': '7.000', 'total_sales': '355.00', 'total_paid': '275.00', 'total_due': '80.00',
          'total_discounts': '30.00', 'additional_charges': '5.00', 'revenue': '350.00', 'cost_of_goods': '240.00',
          'gross_profit': '115.00', 'charges_counted_as_income': true, 'due_collected': '30.00',
          'cancelled_orders': 1, 'cancelled_amount': '50.00',
        },
        'meta': {
          'range': {'key': 'this_week', 'from': '2026-03-07', 'to': '2026-03-12', 'label': '7 Mar 2026 – 12 Mar 2026'},
        },
      });

      expect(summary.totalSales, '355.00');
      expect(summary.grossProfit, '115.00');
      expect(summary.cancelledOrders, 1);
      expect(summary.periodLabel, '7 Mar 2026 – 12 Mar 2026');
    });
  });

  group('who sees reports', () {
    testWidgets('the Reports action needs the plan and the role', (tester) async {
      await pumpApp(tester, repository: signedInAs(), locale: 'en'); // free plan
      expect(find.byKey(const ValueKey('quick-reports')), findsNothing);
    });

    testWidgets('a cashier on a plan with reports still does not get them', (tester) async {
      await pumpApp(tester, repository: signedInAs(role: 'cashier', modules: withReports), locale: 'en');
      expect(find.byKey(const ValueKey('quick-reports')), findsNothing);
    });

    testWidgets('the owner on a plan with reports does', (tester) async {
      await pumpApp(tester, repository: signedInAs(modules: withReports), locale: 'en');
      expect(find.byKey(const ValueKey('quick-reports')), findsOneWidget);
    });
  });

  group('reports screen', () {
    testWidgets('opens on today with sales and profit shown as different figures', (tester) async {
      final reports = await openReports(tester);

      expect(reports.summaryRequests.single.key, ReportRangeKey.today);
      expect(find.text('12 Nov 2026'), findsOneWidget);
      expect(find.text('Total sales'), findsOneWidget);
      expect(find.text('৳355'), findsOneWidget);
      expect(find.text('Gross profit'), findsOneWidget);
      expect(find.text('৳115'), findsOneWidget);
      expect(find.textContaining('Profit = sales of goods after discounts'), findsOneWidget);

      expect(find.text('৳275'), findsOneWidget); // paid
      expect(find.text('৳80'), findsWidgets); //   due
      expect(find.text('1 · ৳50'), findsOneWidget); // cancelled
    });

    testWidgets('choosing another period loads that period', (tester) async {
      final reports = await openReports(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Last 7 days'));
      await tester.pumpAndSettle();

      expect(reports.summaryRequests.last.key, ReportRangeKey.last7Days);
      expect(find.text('6 Nov 2026 – 12 Nov 2026'), findsOneWidget);
      expect(find.text('৳18,450'), findsOneWidget);
      expect(find.text('৳4,070'), findsOneWidget);
      expect(find.text('Cancelled sales'), findsNothing, reason: 'Not shown when nothing was cancelled.');

      await tester.tap(find.widgetWithText(ChoiceChip, 'This month'));
      await tester.pumpAndSettle();
      expect(reports.summaryRequests.last.key, ReportRangeKey.thisMonth);
    });

    testWidgets('money received is listed by method, with due kept apart', (tester) async {
      await openReports(tester);
      await tester.scrollUntilVisible(find.text('Sold on due'), 200, scrollable: find.byType(Scrollable).last);

      expect(find.text('Money received'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('৳50 refunded'), findsOneWidget);
      expect(find.text('includes ৳30 due collected'), findsOneWidget);
      expect(find.text('Net received'), findsOneWidget);
      expect(find.text('৳305'), findsOneWidget);
      expect(find.text('Sold on due'), findsOneWidget);
    });

    testWidgets('best sellers can be ranked by quantity or by sales', (tester) async {
      await openReports(tester);
      await tester.scrollUntilVisible(find.text('By sales'), 200, scrollable: find.byType(Scrollable).last);
      await tester.scrollUntilVisible(find.text('Miniket Rice'), 100, scrollable: find.byType(Scrollable).last);

      double top(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(top('Lux Soap') < top('Miniket Rice'), isTrue, reason: 'By quantity, soap (10) leads rice (7.5).');
      expect(find.text('10 Piece · Profit ৳200'), findsOneWidget);

      await tester.ensureVisible(find.text('By sales'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('By sales'));
      await tester.pumpAndSettle();
      expect(top('Miniket Rice') < top('Lux Soap'), isTrue, reason: 'By sales, rice (৳600) leads soap (৳500).');
    });

    testWidgets('links lead to dues, low stock and sales history', (tester) async {
      await openReports(tester);
      await tester.scrollUntilVisible(find.text('Customer dues'), 300, scrollable: find.byType(Scrollable).last);

      await tester.tap(find.text('Customer dues'));
      await tester.pumpAndSettle();
      expect(find.text('Collect due'), findsOneWidget); // the due-only customer list
    });
  });

  group('export', () {
    testWidgets('downloads the chosen report and file type and hands it to the share sheet', (tester) async {
      final outbox = Outbox();
      final reports = await openReports(tester, outbox: outbox);

      await tester.tap(find.widgetWithText(ChoiceChip, 'This month'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Sales history'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      expect(reports.exports, ['sales.pdf this_month'], reason: 'The export covers the period on screen.');
      expect(outbox.files, ['sales.pdf']);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('defaults to the summary as Excel', (tester) async {
      final reports = await openReports(tester);

      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      expect(reports.exports, ['summary.xlsx today']);
    });

    testWidgets('a failure is explained and the sheet stays open', (tester) async {
      final outbox = Outbox();
      final reports = await openReports(tester, outbox: outbox);
      reports.failNextExport = const ApiException(kind: ApiErrorKind.network);

      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      expect(find.text('No internet connection. Check your connection and try again.'), findsOneWidget);
      expect(outbox.files, isEmpty);
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('a plan with reports but without exports has no export button', (tester) async {
      await openReports(tester, modules: withReports);

      expect(find.text('Total sales'), findsOneWidget);
      expect(find.byTooltip('Export'), findsNothing);
    });
  });

  testWidgets('reports are in Bangla by default', (tester) async {
    await pumpApp(tester, repository: signedInAs(modules: withExports), reports: FakeReportRepository());
    await tapQuickAction(tester, 'reports');

    expect(find.text('মোট বিক্রি'), findsOneWidget);
    expect(find.text('৳৩৫৫'), findsOneWidget);
    expect(find.text('মোট লাভ'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'গত ৭ দিন'), findsOneWidget);
  });
}
