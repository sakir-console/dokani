import 'package:dokani/core/network/api_exception.dart';
import 'package:dokani/features/pos/data/sale_models.dart';
import 'package:dokani/features/reports/data/report_models.dart';
import 'package:dokani/features/reports/data/report_repository.dart';

/// Canned reports: "today" is a quiet day, every other period is busier,
/// so a test can tell which period the screen asked for.
class FakeReportRepository implements ReportRepository {
  final List<ReportRange> summaryRequests = [];
  final List<String> exports = [];
  ApiException? failNextExport;

  bool _isToday(ReportRange range) => range.key == ReportRangeKey.today;

  @override
  Future<ReportSummary> summary(ReportRange range) async {
    summaryRequests.add(range);
    return _isToday(range)
        ? const ReportSummary(
            orders: 2, itemsSold: '7.000', totalSales: '355.00', totalPaid: '275.00', totalDue: '80.00',
            totalDiscounts: '30.00', additionalCharges: '5.00', costOfGoods: '240.00', grossProfit: '115.00',
            dueCollected: '30.00', cancelledOrders: 1, cancelledAmount: '50.00', periodLabel: '12 Nov 2026',
          )
        : ReportSummary(
            orders: 41, itemsSold: '212.500', totalSales: '18450.00', totalPaid: '16000.00', totalDue: '2450.00',
            totalDiscounts: '600.00', additionalCharges: '120.00', costOfGoods: '13900.00', grossProfit: '4070.00',
            dueCollected: '900.00', cancelledOrders: 0, cancelledAmount: '0.00',
            periodLabel: range.key == ReportRangeKey.custom ? '1 Nov 2026 – 5 Nov 2026' : '6 Nov 2026 – 12 Nov 2026',
          );
  }

  @override
  Future<PaymentMethodsReport> paymentMethods(ReportRange range) async => const PaymentMethodsReport(
        methods: [
          PaymentMethodRow(method: PaymentMethod.cash, net: '175.00', dueCollections: '0.00', refunds: '50.00'),
          PaymentMethodRow(method: PaymentMethod.bkash, net: '100.00', dueCollections: '0.00', refunds: '0.00'),
          PaymentMethodRow(method: PaymentMethod.nagad, net: '30.00', dueCollections: '30.00', refunds: '0.00'),
        ],
        netTotal: '305.00',
        soldOnDue: '80.00',
      );

  @override
  Future<List<BestSeller>> bestSellers(ReportRange range, {bool byRevenue = false}) async {
    const soap = BestSeller(productName: 'Lux Soap', unitName: 'Piece', quantity: '10.000', revenue: '500.00', profit: '200.00');
    const rice = BestSeller(productName: 'Miniket Rice', unitName: 'Kilogram', quantity: '7.500', revenue: '600.00', profit: '150.00');
    return byRevenue ? const [rice, soap] : const [soap, rice];
  }

  @override
  Future<ExportedFile> export(ExportReport report, ExportFormat format, ReportRange range) async {
    final failure = failNextExport;
    if (failure != null) {
      failNextExport = null;
      throw failure;
    }
    exports.add('${report.apiValue}.${format.name} ${range.key.apiValue}');
    return ExportedFile(path: '/tmp/${report.apiValue}.${format.name}', name: '${report.apiValue}.${format.name}');
  }
}
