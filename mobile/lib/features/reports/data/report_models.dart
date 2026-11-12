/// Reports as the API returns them. Amounts stay decimal strings.
library;

import '../../pos/data/sale_models.dart';

enum ReportRangeKey {
  today('today'),
  yesterday('yesterday'),
  last7Days('last_7_days'),
  thisWeek('this_week'),
  thisMonth('this_month'),
  custom('custom');

  const ReportRangeKey(this.apiValue);

  final String apiValue;
}

/// The period a report covers. For [ReportRangeKey.custom], [from] and [to] are set.
class ReportRange {
  const ReportRange(this.key, {this.from, this.to});

  final ReportRangeKey key;
  final DateTime? from;
  final DateTime? to;

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Whole days, as the server expects them. The server applies the shop's time zone.
  Map<String, dynamic> toQuery() => {
        'range': key.apiValue,
        if (key == ReportRangeKey.custom && from != null) 'from': _date(from!),
        if (key == ReportRangeKey.custom && to != null) 'to': _date(to!),
      };

  @override
  bool operator ==(Object other) => other is ReportRange && other.key == key && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(key, from, to);
}

class ReportSummary {
  const ReportSummary({
    required this.orders,
    required this.itemsSold,
    required this.totalSales,
    required this.totalPaid,
    required this.totalDue,
    required this.totalDiscounts,
    required this.additionalCharges,
    required this.costOfGoods,
    required this.grossProfit,
    required this.dueCollected,
    required this.cancelledOrders,
    required this.cancelledAmount,
    required this.periodLabel,
  });

  final int orders;
  final String itemsSold;
  final String totalSales;
  final String totalPaid;
  final String totalDue;
  final String totalDiscounts;
  final String additionalCharges;
  final String costOfGoods;
  final String grossProfit;
  final String dueCollected;
  final int cancelledOrders;
  final String cancelledAmount;

  /// The dates the server actually used, e.g. "7 Mar 2026 – 12 Mar 2026".
  final String periodLabel;

  factory ReportSummary.fromJson(Map<String, dynamic> body) {
    final data = (body['data'] as Map).cast<String, dynamic>();
    final range = ((body['meta'] as Map?)?['range'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ReportSummary(
      orders: data['orders'] as int? ?? 0,
      itemsSold: '${data['items_sold']}',
      totalSales: '${data['total_sales']}',
      totalPaid: '${data['total_paid']}',
      totalDue: '${data['total_due']}',
      totalDiscounts: '${data['total_discounts']}',
      additionalCharges: '${data['additional_charges']}',
      costOfGoods: '${data['cost_of_goods']}',
      grossProfit: '${data['gross_profit']}',
      dueCollected: '${data['due_collected']}',
      cancelledOrders: data['cancelled_orders'] as int? ?? 0,
      cancelledAmount: '${data['cancelled_amount']}',
      periodLabel: range['label'] as String? ?? '',
    );
  }
}

class PaymentMethodRow {
  const PaymentMethodRow({required this.method, required this.net, required this.dueCollections, required this.refunds});

  final PaymentMethod method;

  /// Sales + due collections − refunds for this method.
  final String net;
  final String dueCollections;
  final String refunds;

  factory PaymentMethodRow.fromJson(Map<String, dynamic> json) => PaymentMethodRow(
        method: PaymentMethod.parse(json['method'] as String?),
        net: '${json['net']}',
        dueCollections: '${json['due_collections']}',
        refunds: '${json['refunds']}',
      );
}

class PaymentMethodsReport {
  const PaymentMethodsReport({required this.methods, required this.netTotal, required this.soldOnDue});

  final List<PaymentMethodRow> methods;
  final String netTotal;

  /// Not money received: what was sold on credit in the period.
  final String soldOnDue;

  factory PaymentMethodsReport.fromJson(Map<String, dynamic> data) => PaymentMethodsReport(
        methods: (data['methods'] as List? ?? const [])
            .map((e) => PaymentMethodRow.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        netTotal: '${(data['totals'] as Map?)?['net'] ?? '0.00'}',
        soldOnDue: '${data['sold_on_due'] ?? '0.00'}',
      );
}

class BestSeller {
  const BestSeller({
    required this.productName,
    required this.unitName,
    required this.quantity,
    required this.revenue,
    required this.profit,
    this.variantName,
  });

  final String productName;
  final String? variantName;
  final String unitName;
  final String quantity;
  final String revenue;
  final String profit;

  String get title => variantName == null ? productName : '$productName — $variantName';

  factory BestSeller.fromJson(Map<String, dynamic> json) => BestSeller(
        productName: json['product_name'] as String,
        variantName: json['variant_name'] as String?,
        unitName: json['unit_name'] as String? ?? '',
        quantity: '${json['quantity']}',
        revenue: '${json['revenue']}',
        profit: '${json['profit']}',
      );
}

enum ExportReport {
  summary('summary'),
  paymentMethods('payment-methods'),
  bestSellers('best-sellers'),
  sales('sales'),
  dues('dues'),
  lowStock('low-stock');

  const ExportReport(this.apiValue);

  final String apiValue;
}

enum ExportFormat {
  xlsx,
  csv,
  pdf,
}

/// A downloaded report file, saved on the phone and ready to share or open.
class ExportedFile {
  const ExportedFile({required this.path, required this.name});

  final String path;
  final String name;
}
