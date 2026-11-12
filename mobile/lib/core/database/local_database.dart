import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'local_database.g.dart';

/// A product as last received from the server, stored whole as JSON, with the
/// name pulled out for searching.
class CachedProducts extends Table {
  IntColumn get id => integer()();
  TextColumn get searchName => text()();
  TextColumn get json => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Barcode → the exact variant it belongs to. This is what makes scanning
/// work without a connection.
class CachedBarcodes extends Table {
  TextColumn get code => text()();
  IntColumn get variantId => integer()();
  IntColumn get productId => integer()();

  @override
  Set<Column<Object>> get primaryKey => {code};
}

class CachedCustomers extends Table {
  IntColumn get id => integer()();
  TextColumn get phone => text()();
  TextColumn get searchName => text()();
  TextColumn get json => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Everything recorded on this phone that the server must hear about.
///
/// A row is written before any network request is made, and is only marked
/// synced after the server confirms it. Rows are never deleted while unsynced.
class OutboxEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The id the server uses to recognise a repeat of the same record.
  TextColumn get clientUuid => text().unique()();

  /// 'sale' or 'due_collection'
  TextColumn get kind => text()();

  /// The request body, exactly as it will be sent.
  TextColumn get payload => text()();

  /// What is needed to show the record on the phone before it is synced
  /// (product names, customer name), which the request body does not carry.
  TextColumn get display => text()();

  /// 'pending', 'synced' or 'failed'
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get errorCode => text().nullable()();
  TextColumn get errorMessage => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  /// The server's answer once synced (id, invoice number, invoice link).
  TextColumn get server => text().nullable()();
}

/// Small key/value store: sync cursors, the last sync time.
class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// One database file per shop, so two shops used on the same phone never mix.
@DriftDatabase(tables: [CachedProducts, CachedBarcodes, CachedCustomers, OutboxEntries, SyncState])
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase(super.executor);

  /// Opens (or creates) the database for a shop, on a background isolate so
  /// a large first sync does not freeze the screen.
  factory LocalDatabase.forShop(int shopId) => LocalDatabase(
        LazyDatabase(() async {
          final directory = await getApplicationDocumentsDirectory();
          return NativeDatabase.createInBackground(File(p.join(directory.path, 'dokani_shop_$shopId.sqlite')));
        }),
      );

  factory LocalDatabase.inMemory() => LocalDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('CREATE INDEX cached_customers_phone ON cached_customers (phone)');
          await customStatement('CREATE INDEX outbox_status ON outbox_entries (status, id)');
        },
      );

  // --- Products and barcodes ---------------------------------------------------

  /// Stores products as received from the server, replacing older copies and
  /// their barcodes.
  Future<void> upsertProducts(List<Map<String, dynamic>> products) => transaction(() async {
        for (final product in products) {
          final id = product['id'] as int;
          await into(cachedProducts).insertOnConflictUpdate(
            CachedProductsCompanion.insert(
              id: Value(id),
              searchName: (product['name'] as String).toLowerCase(),
              json: jsonEncode(product),
            ),
          );
          await _replaceBarcodes(id, product);
        }
      });

  Future<void> _replaceBarcodes(int productId, Map<String, dynamic> product) async {
    await (delete(cachedBarcodes)..where((b) => b.productId.equals(productId))).go();
    for (final variant in (product['variants'] as List? ?? const [])) {
      final variantMap = (variant as Map).cast<String, dynamic>();
      for (final code in (variantMap['barcodes'] as List? ?? const [])) {
        await into(cachedBarcodes).insertOnConflictUpdate(
          CachedBarcodesCompanion.insert(code: '$code', variantId: variantMap['id'] as int, productId: productId),
        );
      }
    }
  }

  Future<void> deleteProducts(List<int> ids) async {
    if (ids.isEmpty) return;
    await transaction(() async {
      await (delete(cachedBarcodes)..where((b) => b.productId.isIn(ids))).go();
      await (delete(cachedProducts)..where((p) => p.id.isIn(ids))).go();
    });
  }

  /// Products whose name contains [query], or which have exactly that barcode or SKU.
  Future<List<Map<String, dynamic>>> searchProducts(String query, {int limit = 30, int offset = 0}) async {
    final term = query.trim();
    final select_ = select(cachedProducts)
      ..orderBy([(p) => OrderingTerm(expression: p.searchName)])
      ..limit(limit, offset: offset);

    if (term.isNotEmpty) {
      final byBarcode = await (select(cachedBarcodes)..where((b) => b.code.equals(term))).getSingleOrNull();
      final like = '%${term.toLowerCase().replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      select_.where(
        (p) => byBarcode == null
            ? p.searchName.like(like, escapeChar: r'\')
            : (p.searchName.like(like, escapeChar: r'\') | p.id.equals(byBarcode.productId)),
      );
    }

    final rows = await select_.get();
    return [for (final row in rows) (jsonDecode(row.json) as Map).cast<String, dynamic>()];
  }

  Future<int> productCount() async {
    final count = cachedProducts.id.count();
    return (await (selectOnly(cachedProducts)..addColumns([count])).getSingle()).read(count) ?? 0;
  }

  /// The product and variant a barcode belongs to, or null.
  Future<({int variantId, Map<String, dynamic> product})?> productByBarcode(String code) async {
    final barcode = await (select(cachedBarcodes)..where((b) => b.code.equals(code.trim()))).getSingleOrNull();
    if (barcode == null) return null;
    final row = await (select(cachedProducts)..where((p) => p.id.equals(barcode.productId))).getSingleOrNull();
    if (row == null) return null;
    return (variantId: barcode.variantId, product: (jsonDecode(row.json) as Map).cast<String, dynamic>());
  }

  /// Lowers (or raises) the stock shown on this phone after a sale made here,
  /// so the counter does not offer what was just sold. The next sync replaces
  /// it with the server's figure. [deltaMilli] is in thousandths of a unit.
  Future<void> adjustLocalStock(int variantId, int deltaMilli) => transaction(() async {
        // Narrow to rows that mention the id, then check properly below.
        final rows = await (select(cachedProducts)..where((p) => p.json.like('%"id":$variantId%'))).get();
        for (final row in rows) {
          final product = (jsonDecode(row.json) as Map).cast<String, dynamic>();
          final variants = (product['variants'] as List? ?? const []).map((v) => (v as Map).cast<String, dynamic>()).toList();
          final index = variants.indexWhere((v) => v['id'] == variantId);
          if (index == -1) continue;

          int milli(Object? value) => ((double.tryParse('$value') ?? 0) * 1000).round();
          String text(int value) => (value / 1000).toStringAsFixed(3);

          variants[index]['stock_quantity'] = text(milli(variants[index]['stock_quantity']) + deltaMilli);
          product['variants'] = variants;
          final left = milli(variants[index]['stock_quantity']);
          if (left <= 0) {
            variants[index]['stock_status'] = 'out';
          } else if (variants[index]['stock_status'] == 'out') {
            variants[index]['stock_status'] = 'in_stock';
          }
          product['out_of_stock_variants'] = variants.where((v) => v['stock_status'] == 'out').length;
          product['low_stock_variants'] = variants.where((v) => v['stock_status'] == 'low').length;
          product['total_stock'] = text(variants.fold(0, (sum, v) => sum + milli(v['stock_quantity'])));

          await (update(cachedProducts)..where((p) => p.id.equals(row.id))).write(CachedProductsCompanion(json: Value(jsonEncode(product))));
          return;
        }
      });

  // --- Customers --------------------------------------------------------------

  Future<void> upsertCustomers(List<Map<String, dynamic>> customers) => transaction(() async {
        for (final customer in customers) {
          await into(cachedCustomers).insertOnConflictUpdate(
            CachedCustomersCompanion.insert(
              id: Value(customer['id'] as int),
              phone: customer['phone'] as String,
              searchName: (customer['name'] as String).toLowerCase(),
              json: jsonEncode(customer),
            ),
          );
        }
      });

  Future<void> deleteCustomers(List<int> ids) async {
    if (ids.isEmpty) return;
    await (delete(cachedCustomers)..where((c) => c.id.isIn(ids))).go();
  }

  /// Customers by name or phone, for working without a connection.
  Future<List<Map<String, dynamic>>> searchCustomers(String query, {int limit = 100}) async {
    final term = query.trim().toLowerCase().replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
    final rows = await (select(cachedCustomers)
          ..where((c) => term.isEmpty ? const Constant(true) : (c.searchName.like('%$term%', escapeChar: r'\') | c.phone.like('%$term%', escapeChar: r'\')))
          ..orderBy([(c) => OrderingTerm(expression: c.searchName)])
          ..limit(limit))
        .get();
    return [for (final row in rows) (jsonDecode(row.json) as Map).cast<String, dynamic>()];
  }

  Future<Map<String, dynamic>?> customerById(int id) async {
    final row = await (select(cachedCustomers)..where((c) => c.id.equals(id))).getSingleOrNull();
    return row == null ? null : (jsonDecode(row.json) as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>?> customerByPhone(String phone) async {
    final row = await (select(cachedCustomers)..where((c) => c.phone.equals(phone))..limit(1)).getSingleOrNull();
    return row == null ? null : (jsonDecode(row.json) as Map).cast<String, dynamic>();
  }

  // --- Outbox -----------------------------------------------------------------

  Future<void> enqueue({
    required String clientUuid,
    required String kind,
    required Map<String, dynamic> payload,
    required Map<String, dynamic> display,
    DateTime? createdAt,
  }) =>
      into(outboxEntries).insert(
        OutboxEntriesCompanion.insert(
          clientUuid: clientUuid,
          kind: kind,
          payload: jsonEncode(payload),
          display: jsonEncode(display),
          createdAt: createdAt ?? DateTime.now(),
        ),
        // The same record queued twice (a double tap) stays one row.
        mode: InsertMode.insertOrIgnore,
      );

  /// Records still waiting for the server, oldest first. Failed ones are
  /// included: they are retried, because the reason may have been fixed.
  Future<List<OutboxEntry>> unsynced({int limit = 50}) => (select(outboxEntries)
        ..where((o) => o.status.isNotValue('synced'))
        ..orderBy([(o) => OrderingTerm(expression: o.id)])
        ..limit(limit))
      .get();

  Future<OutboxEntry?> entry(String clientUuid) =>
      (select(outboxEntries)..where((o) => o.clientUuid.equals(clientUuid))).getSingleOrNull();

  /// One record, followed as it moves from waiting to confirmed (or failed).
  Stream<OutboxEntry?> watchEntry(String clientUuid) =>
      (select(outboxEntries)..where((o) => o.clientUuid.equals(clientUuid))).watchSingleOrNull();

  /// Everything not yet confirmed, newest first, for the "waiting to sync" screen.
  Stream<List<OutboxEntry>> watchUnsynced() => (select(outboxEntries)
        ..where((o) => o.status.isNotValue('synced'))
        ..orderBy([(o) => OrderingTerm(expression: o.id, mode: OrderingMode.desc)]))
      .watch();

  Future<void> markSynced(String clientUuid, Map<String, dynamic> server) =>
      (update(outboxEntries)..where((o) => o.clientUuid.equals(clientUuid))).write(
        OutboxEntriesCompanion(
          status: const Value('synced'),
          server: Value(jsonEncode(server)),
          errorCode: const Value(null),
          errorMessage: const Value(null),
        ),
      );

  Future<void> markFailed(String clientUuid, String code, String message) =>
      (update(outboxEntries)..where((o) => o.clientUuid.equals(clientUuid))).write(
        OutboxEntriesCompanion(status: const Value('failed'), errorCode: Value(code), errorMessage: Value(message)),
      );

  /// Removes a record that the server refused while the user was still on the
  /// screen that created it (they see the reason and can correct it).
  /// Never used for records that simply have not been sent yet.
  Future<void> discard(String clientUuid) =>
      (delete(outboxEntries)..where((o) => o.clientUuid.equals(clientUuid) & o.status.isNotValue('synced'))).go();

  Future<void> countAttempt(List<String> clientUuids) async {
    if (clientUuids.isEmpty) return;
    await customUpdate(
      'UPDATE outbox_entries SET attempts = attempts + 1 WHERE client_uuid IN (${List.filled(clientUuids.length, '?').join(',')})',
      variables: [for (final uuid in clientUuids) Variable.withString(uuid)],
      updates: {outboxEntries},
    );
  }

  /// Clears confirmed records older than [keep]. Unsynced records are never removed.
  Future<void> pruneSynced({Duration keep = const Duration(days: 7)}) => (delete(outboxEntries)
        ..where((o) => o.status.equals('synced') & o.createdAt.isSmallerThanValue(DateTime.now().subtract(keep))))
      .go();

  // --- Sync state -------------------------------------------------------------

  Future<String?> state(String key) async =>
      (await (select(syncState)..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setState(String key, String value) =>
      into(syncState).insertOnConflictUpdate(SyncStateCompanion.insert(key: key, value: value));
}
