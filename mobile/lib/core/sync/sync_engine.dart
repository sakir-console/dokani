import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../database/local_database.dart';
import '../money/exact.dart';
import '../network/api_exception.dart';
import '../storage/preferences.dart';
import 'sync_api.dart';

/// The local database of the shop that is signed in. Null when signed out.
///
/// The file belongs to the shop, not to the login: signing out leaves it in
/// place, so sales still waiting to sync are there when the shop signs in again.
final localDatabaseProvider = Provider<LocalDatabase?>((ref) {
  final shopId = ref.watch(sessionProvider.select((session) => session?.shop.id));
  if (shopId == null) return null;

  final database = LocalDatabase.forShop(shopId);
  ref.onDispose(database.close);
  return database;
});

/// A random id for this phone, created once. Tells the server which device a
/// sale came from.
final deviceUuidProvider = Provider<String>((ref) {
  final preferences = ref.watch(sharedPreferencesProvider);
  final existing = preferences.getString('device_uuid');
  if (existing != null) return existing;

  final created = Exact.uuid();
  preferences.setString('device_uuid', created);
  return created;
});

class SyncStatus {
  const SyncStatus({this.syncing = false, this.offline = false, this.lastSyncedAt, this.lastError});

  final bool syncing;

  /// The last attempt could not reach the server.
  final bool offline;
  final DateTime? lastSyncedAt;
  final Object? lastError;

  SyncStatus copyWith({bool? syncing, bool? offline, DateTime? lastSyncedAt, Object? lastError, bool clearError = false}) =>
      SyncStatus(
        syncing: syncing ?? this.syncing,
        offline: offline ?? this.offline,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

/// Moves data between the phone and the server.
///
/// Push first, so the server knows about this phone's sales before the phone
/// asks for fresh stock; then pull what changed.
///
/// A record leaves the queue only when the server answers "created" or
/// "duplicate" for it. A failed request, a dropped connection or a rejected
/// record all leave it in place, to be retried or shown to the user.
class SyncEngine extends Notifier<SyncStatus> {
  static const _batch = 50;

  Future<void>? _running;
  Timer? _retry;

  @override
  SyncStatus build() {
    ref.onDispose(() => _retry?.cancel());
    // Signing in (or switching shop) starts a sync for that shop.
    ref.listen(localDatabaseProvider, fireImmediately: true, (previous, next) {
      if (next != null) unawaited(Future.microtask(sync));
    });
    return const SyncStatus();
  }

  /// Runs a full sync. Calls made while one is running wait for that one.
  Future<void> sync() => _running ??= _run().whenComplete(() => _running = null);

  Future<void> _run() async {
    final database = ref.read(localDatabaseProvider);
    if (database == null) return;

    state = state.copyWith(syncing: true, clearError: true);
    try {
      await _push(database);
      await _pull(database, 'products', database.upsertProducts, database.deleteProducts);
      await _pull(database, 'customers', database.upsertCustomers, database.deleteCustomers);
      await database.pruneSynced();

      state = SyncStatus(lastSyncedAt: DateTime.now());
      _retry?.cancel();
    } on ApiException catch (error) {
      state = state.copyWith(syncing: false, offline: error.isOffline, lastError: error);
      await _scheduleRetry(database);
    } catch (error) {
      state = state.copyWith(syncing: false, lastError: error);
      await _scheduleRetry(database);
    }
  }

  /// While something is waiting, keep trying in the background.
  Future<void> _scheduleRetry(LocalDatabase database) async {
    _retry?.cancel();
    if ((await database.unsynced(limit: 1)).isEmpty) return;
    _retry = Timer(const Duration(seconds: 45), () => unawaited(sync()));
  }

  Future<void> _push(LocalDatabase database) async {
    final attempted = <String>{};

    while (true) {
      // Records already tried in this run are skipped, so a rejected one does not loop forever.
      final batch = (await database.unsynced(limit: _batch + attempted.length))
          .where((entry) => !attempted.contains(entry.clientUuid))
          .take(_batch)
          .toList();
      if (batch.isEmpty) return;

      attempted.addAll(batch.map((entry) => entry.clientUuid));
      await database.countAttempt([for (final entry in batch) entry.clientUuid]);

      Map<String, dynamic> body(OutboxEntry entry) => (jsonDecode(entry.payload) as Map).cast<String, dynamic>();

      // If this request fails, nothing was marked: every record stays queued.
      final results = await ref.read(syncApiProvider).push(
            deviceUuid: ref.read(deviceUuidProvider),
            sales: [for (final entry in batch.where((e) => e.kind == 'sale')) body(entry)],
            dueCollections: [for (final entry in batch.where((e) => e.kind == 'due_collection')) body(entry)],
          );

      for (final result in [...results.sales, ...results.dueCollections]) {
        final uuid = result.clientUuid;
        if (uuid == null) continue;
        if (result.accepted) {
          await database.markSynced(uuid, result.server);
        } else {
          await database.markFailed(uuid, result.code ?? 'UNKNOWN', result.message ?? '');
        }
      }
    }
  }

  Future<void> _pull(
    LocalDatabase database,
    String what,
    Future<void> Function(List<Map<String, dynamic>>) upsert,
    Future<void> Function(List<int>) delete,
  ) async {
    final since = await database.state('${what}_cursor');
    final api = ref.read(syncApiProvider);

    String? cursor;
    for (var page = 1;; page++) {
      final result = await api.pull(what, since: since, page: page);
      // The position to resume from is the one issued when this round began.
      cursor ??= result.cursor;

      await upsert(result.rows);
      await delete(result.deletedIds);
      if (page >= result.lastPage) break;
    }

    // Saved only after every page arrived: an interrupted sync starts the round again.
    await database.setState('${what}_cursor', cursor);
  }
}

final syncEngineProvider = NotifierProvider<SyncEngine, SyncStatus>(SyncEngine.new);

/// One queued record, live: the pending invoice screen follows it until the server confirms.
final outboxEntryProvider = StreamProvider.autoDispose.family<OutboxEntry?, String>((ref, clientUuid) {
  final database = ref.watch(localDatabaseProvider);
  return database == null ? Stream.value(null) : database.watchEntry(clientUuid);
});

/// Records made on this phone that the server has not confirmed yet, newest first.
final unsyncedProvider = StreamProvider<List<OutboxEntry>>((ref) {
  final database = ref.watch(localDatabaseProvider);
  return database == null ? Stream.value(const []) : database.watchUnsynced();
});
