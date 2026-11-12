/// Sales as the API returns them, and the request the checkout sends.
library;

enum PaymentMethod {
  cash,
  bkash,
  nagad,
  bank,
  card,
  other;

  static PaymentMethod parse(String? value) =>
      PaymentMethod.values.firstWhere((m) => m.name == value, orElse: () => PaymentMethod.other);
}

class SaleItem {
  const SaleItem({
    required this.productName,
    required this.unitName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.variantName,
    this.discountAmount = '0.00',
  });

  final String productName;
  final String? variantName;
  final String unitName;
  final String quantity;
  final String unitPrice;
  final String discountAmount;
  final String lineTotal;

  String get title => variantName == null ? productName : '$productName — $variantName';

  factory SaleItem.fromJson(Map<String, dynamic> json) => SaleItem(
        productName: json['product_name'] as String,
        variantName: json['variant_name'] as String?,
        unitName: json['unit_name'] as String? ?? '',
        quantity: '${json['quantity']}',
        unitPrice: '${json['unit_price']}',
        discountAmount: '${json['discount_amount'] ?? '0.00'}',
        lineTotal: '${json['line_total']}',
      );
}

class SalePayment {
  const SalePayment({required this.type, required this.method, required this.amount, this.transactionId});

  /// sale, due_collection or refund
  final String type;
  final PaymentMethod method;
  final String amount;
  final String? transactionId;

  factory SalePayment.fromJson(Map<String, dynamic> json) => SalePayment(
        type: json['type'] as String? ?? 'sale',
        method: PaymentMethod.parse(json['method'] as String?),
        amount: '${json['amount']}',
        transactionId: json['transaction_id'] as String?,
      );
}

class SaleCustomer {
  const SaleCustomer({required this.id, required this.name, required this.phone, this.currentDue = '0.00'});

  final int id;
  final String name;
  final String phone;
  final String currentDue;

  factory SaleCustomer.fromJson(Map<String, dynamic> json) => SaleCustomer(
        id: json['id'] as int,
        name: json['name'] as String,
        phone: json['phone'] as String,
        currentDue: '${json['current_due'] ?? '0.00'}',
      );
}

class Sale {
  const Sale({
    required this.id,
    required this.invoiceNo,
    required this.soldAt,
    required this.subtotal,
    required this.grandTotal,
    required this.paidAmount,
    required this.dueAmount,
    this.voided = false,
    this.discountAmount = '0.00',
    this.additionalCharge = '0.00',
    this.changeAmount = '0.00',
    this.grossProfit,
    this.customer,
    this.items = const [],
    this.payments = const [],
    this.invoiceUrl,
    this.voidReason,
  });

  final int id;
  final String invoiceNo;
  final DateTime soldAt;
  final bool voided;
  final String subtotal;
  final String discountAmount;
  final String additionalCharge;
  final String grandTotal;
  final String paidAmount;
  final String dueAmount;
  final String changeAmount;

  /// Only present for roles allowed to see profit.
  final String? grossProfit;
  final SaleCustomer? customer;
  final List<SaleItem> items;
  final List<SalePayment> payments;
  final String? invoiceUrl;
  final String? voidReason;

  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
        id: json['id'] as int,
        invoiceNo: json['invoice_no'] as String,
        soldAt: DateTime.parse(json['sold_at'] as String),
        voided: json['status'] == 'voided',
        subtotal: '${json['subtotal']}',
        discountAmount: '${json['discount_amount'] ?? '0.00'}',
        additionalCharge: '${json['additional_charge'] ?? '0.00'}',
        grandTotal: '${json['grand_total']}',
        paidAmount: '${json['paid_amount']}',
        dueAmount: '${json['due_amount']}',
        changeAmount: '${json['change_amount'] ?? '0.00'}',
        grossProfit: json['gross_profit'] == null ? null : '${json['gross_profit']}',
        customer: json['customer'] is Map ? SaleCustomer.fromJson((json['customer'] as Map).cast<String, dynamic>()) : null,
        items: (json['items'] as List? ?? const [])
            .map((e) => SaleItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        payments: (json['payments'] as List? ?? const [])
            .map((e) => SalePayment.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        invoiceUrl: json['invoice_url'] as String?,
        voidReason: json['void_reason'] as String?,
      );
}

class DashboardData {
  const DashboardData({
    required this.sales,
    required this.orders,
    required this.itemsSold,
    required this.totalCustomerDue,
    this.profit,
    this.recentSales = const [],
  });

  final String sales;

  /// Null for roles that may not see profit.
  final String? profit;
  final int orders;
  final String itemsSold;
  final String totalCustomerDue;
  final List<Sale> recentSales;

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final today = (json['today'] as Map).cast<String, dynamic>();
    return DashboardData(
      sales: '${today['sales']}',
      profit: today['profit'] == null ? null : '${today['profit']}',
      orders: today['orders'] as int? ?? 0,
      itemsSold: '${today['items_sold']}',
      totalCustomerDue: '${json['total_customer_due']}',
      recentSales: (json['recent_sales'] as List? ?? const [])
          .map((e) => Sale.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

// --- The request -------------------------------------------------------------

class SaleLineDraft {
  const SaleLineDraft({required this.variantId, required this.quantity, required this.unitPrice});

  final int variantId;
  final String quantity;

  /// The price the cashier saw. The server compares it with its own.
  final String unitPrice;

  Map<String, dynamic> toJson() => {'variant_id': variantId, 'quantity': quantity, 'unit_price': unitPrice};
}

class PaymentDraft {
  const PaymentDraft({required this.method, required this.amount, this.receivedAmount, this.transactionId});

  final PaymentMethod method;
  final String amount;
  final String? receivedAmount;
  final String? transactionId;

  Map<String, dynamic> toJson() => {
        'method': method.name,
        'amount': amount,
        'received_amount': ?receivedAmount,
        'transaction_id': ?transactionId,
      };
}

class SaleDraft {
  const SaleDraft({
    required this.clientUuid,
    required this.items,
    required this.grandTotal,
    required this.payments,
    required this.dueAmount,
    this.discountAmount = '0.00',
    this.additionalCharge = '0.00',
    this.customerPhone,
    this.customerName,
  });

  /// Stays the same when the request is retried, so the sale is recorded once.
  final String clientUuid;
  final List<SaleLineDraft> items;
  final String discountAmount;
  final String additionalCharge;
  final String grandTotal;
  final List<PaymentDraft> payments;
  final String dueAmount;
  final String? customerPhone;
  final String? customerName;

  Map<String, dynamic> toJson() => {
        'client_uuid': clientUuid,
        'items': [for (final item in items) item.toJson()],
        'discount_amount': discountAmount,
        'additional_charge': additionalCharge,
        'grand_total': grandTotal,
        'payments': [for (final payment in payments) payment.toJson()],
        'due_amount': dueAmount,
        if (customerPhone != null) 'customer': {'phone': customerPhone, 'name': ?customerName},
      };
}
