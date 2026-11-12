import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../pos/data/sale_models.dart';

class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.address,
    this.notes,
    this.currentDue = '0.00',
    this.totalPurchases = '0.00',
    this.totalPaid = '0.00',
  });

  final int id;
  final String name;
  final String phone;
  final String? address;
  final String? notes;
  final String currentDue;
  final String totalPurchases;
  final String totalPaid;

  /// The same shape the API sends, so a customer can be kept in the phone's cache.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'notes': notes,
        'current_due': currentDue,
        'total_purchases': totalPurchases,
        'total_paid': totalPaid,
      };

  /// What the customer owes, as a number, for comparisons on screen only.
  double get dueValue => double.tryParse(currentDue) ?? 0;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'] as int,
        name: json['name'] as String,
        phone: json['phone'] as String,
        address: json['address'] as String?,
        notes: json['notes'] as String?,
        currentDue: '${json['current_due'] ?? '0.00'}',
        totalPurchases: '${json['total_purchases'] ?? '0.00'}',
        totalPaid: '${json['total_paid'] ?? '0.00'}',
      );
}

class LedgerEntry {
  const LedgerEntry({
    required this.type,
    required this.debit,
    required this.credit,
    required this.balanceAfter,
    required this.createdAt,
    this.invoiceNo,
    this.paymentMethod,
  });

  final String type;
  final String debit;
  final String credit;
  final String balanceAfter;
  final DateTime createdAt;
  final String? invoiceNo;
  final PaymentMethod? paymentMethod;

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
        type: json['type'] as String,
        debit: '${json['debit']}',
        credit: '${json['credit']}',
        balanceAfter: '${json['balance_after']}',
        createdAt: DateTime.parse(json['created_at'] as String),
        invoiceNo: json['invoice_no'] as String?,
        paymentMethod: json['payment_method'] == null ? null : PaymentMethod.parse(json['payment_method'] as String?),
      );
}

class CustomerDraft {
  const CustomerDraft({required this.name, required this.phone, this.address, this.openingDue});

  final String name;
  final String phone;
  final String? address;
  final String? openingDue;

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone, 'address': address, 'opening_due': ?openingDue};
}

class CustomerRepository {
  CustomerRepository(this._dio);

  final Dio _dio;

  /// The first 100 matches. With [hasDue], people who owe the most come first.
  Future<List<Customer>> customers({String query = '', bool hasDue = false}) => _guard(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/customers',
          queryParameters: {if (query.isNotEmpty) 'q': query, if (hasDue) 'has_due': 1, 'per_page': 100},
        );
        return _list(response, Customer.fromJson);
      });

  /// The customer with exactly this phone number in this shop, or null.
  Future<Customer?> lookup(String phone) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/customers/lookup', queryParameters: {'phone': phone});
      return Customer.fromJson(_data(response));
    } on DioException catch (error) {
      final failure = ApiException.fromDio(error);
      if (failure.code == 'CUSTOMER_NOT_FOUND') return null;
      throw failure;
    }
  }

  Future<Customer> customer(int id) =>
      _guard(() async => Customer.fromJson(_data(await _dio.get<Map<String, dynamic>>('/customers/$id'))));

  Future<Customer> create(CustomerDraft draft) => _guard(
        () async => Customer.fromJson(_data(await _dio.post<Map<String, dynamic>>('/customers', data: draft.toJson()))),
      );

  Future<Customer> update(int id, CustomerDraft draft) => _guard(
        () async => Customer.fromJson(
          _data(
            await _dio.patch<Map<String, dynamic>>(
              '/customers/$id',
              data: {'name': draft.name, 'phone': draft.phone, 'address': draft.address},
            ),
          ),
        ),
      );

  Future<List<LedgerEntry>> ledger(int customerId) => _guard(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/customers/$customerId/ledger',
          queryParameters: {'per_page': 100},
        );
        return _list(response, LedgerEntry.fromJson);
      });

  /// Records a payment against the customer's due. [clientUuid] makes a retry safe.
  Future<Customer> collectDue({
    required int customerId,
    required String clientUuid,
    required String amount,
    required PaymentMethod method,
    String? transactionId,
  }) =>
      _guard(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/customers/$customerId/collect-due',
          data: {'client_uuid': clientUuid, 'amount': amount, 'method': method.name, 'transaction_id': ?transactionId},
        );
        final meta = (response.data!['meta'] as Map).cast<String, dynamic>();
        return Customer.fromJson((meta['customer'] as Map).cast<String, dynamic>());
      });

  Map<String, dynamic> _data(Response<Map<String, dynamic>> response) =>
      (response.data!['data'] as Map).cast<String, dynamic>();

  List<T> _list<T>(Response<Map<String, dynamic>> response, T Function(Map<String, dynamic>) parse) =>
      (response.data!['data'] as List).map((e) => parse((e as Map).cast<String, dynamic>())).toList();

  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final customerRepositoryProvider = Provider((ref) => CustomerRepository(ref.watch(dioProvider)));

typedef CustomerQuery = ({String query, bool hasDue});

final customersProvider = FutureProvider.autoDispose.family<List<Customer>, CustomerQuery>(
  (ref, filter) => ref.watch(customerRepositoryProvider).customers(query: filter.query, hasDue: filter.hasDue),
);

final customerProvider =
    FutureProvider.autoDispose.family<Customer, int>((ref, id) => ref.watch(customerRepositoryProvider).customer(id));

final customerLedgerProvider = FutureProvider.autoDispose
    .family<List<LedgerEntry>, int>((ref, id) => ref.watch(customerRepositoryProvider).ledger(id));
