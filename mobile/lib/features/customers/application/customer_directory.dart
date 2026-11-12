import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/sync/sync_engine.dart';
import '../data/customer_repository.dart';

/// A list of customers, and whether it came from the copy on this phone
/// because the server could not be reached.
class CustomerList {
  const CustomerList(this.items, {this.fromPhone = false});

  final List<Customer> items;
  final bool fromPhone;
}

/// Customers from the server, falling back to the copy on this phone when
/// there is no connection. The copy is as fresh as the last sync.
class CustomerDirectory {
  CustomerDirectory({required this.database, required this.network});

  final LocalDatabase? database;
  final CustomerRepository network;

  Future<T> _orFromPhone<T>(Future<T> Function() online, Future<T?> Function(LocalDatabase database) saved) async {
    try {
      return await online();
    } on ApiException catch (error) {
      if (!error.isOffline || database == null) rethrow;
      final fallback = await saved(database!);
      if (fallback == null) rethrow;
      return fallback;
    }
  }

  Future<CustomerList> list({String query = '', bool hasDue = false}) => _orFromPhone(
        () async => CustomerList(await network.customers(query: query, hasDue: hasDue)),
        (database) async {
          var items = (await database.searchCustomers(query, limit: hasDue ? 5000 : 100)).map(Customer.fromJson).toList();
          if (hasDue) {
            items = items.where((c) => c.dueValue > 0).toList()..sort((a, b) => b.dueValue.compareTo(a.dueValue));
          }
          return CustomerList(items.take(100).toList(), fromPhone: true);
        },
      );

  Future<Customer> byId(int id) => _orFromPhone(
        () => network.customer(id),
        (database) async {
          final json = await database.customerById(id);
          return json == null ? null : Customer.fromJson(json);
        },
      );

  /// The customer with this phone number, or null if the shop has none.
  /// Without a connection the answer comes from the phone's copy; a customer
  /// added on another device since the last sync is then not found, and the
  /// server matches them by number when the sale arrives.
  Future<Customer?> byPhone(String phone) async {
    try {
      return await network.lookup(phone);
    } on ApiException catch (error) {
      if (!error.isOffline || database == null) rethrow;
      final json = await database!.customerByPhone(phone);
      return json == null ? null : Customer.fromJson(json);
    }
  }
}

final customerDirectoryProvider = Provider(
  (ref) => CustomerDirectory(database: ref.watch(localDatabaseProvider), network: ref.watch(customerRepositoryProvider)),
);

typedef CustomerQuery = ({String query, bool hasDue});

final customersProvider = FutureProvider.autoDispose.family<CustomerList, CustomerQuery>(
  (ref, filter) => ref.watch(customerDirectoryProvider).list(query: filter.query, hasDue: filter.hasDue),
);

final customerProvider =
    FutureProvider.autoDispose.family<Customer, int>((ref, id) => ref.watch(customerDirectoryProvider).byId(id));

final customerLedgerProvider = FutureProvider.autoDispose
    .family<List<LedgerEntry>, int>((ref, id) => ref.watch(customerRepositoryProvider).ledger(id));
