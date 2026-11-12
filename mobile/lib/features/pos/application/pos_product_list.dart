import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/sync_engine.dart';
import '../../catalog/application/catalog_providers.dart';
import 'pos_catalog.dart';

/// The counter's product list. Same behaviour as the products screen's list,
/// but it reads through [PosCatalog], so it works without a connection once
/// the phone has synced.
class PosProductList extends Notifier<ProductListState> {
  int _generation = 0;

  @override
  ProductListState build() {
    // Fresh stock and prices arrived: show them, unless the cashier has scrolled on.
    ref.listen(syncEngineProvider.select((status) => status.lastSyncedAt), (_, _) {
      if (!state.loading && state.page <= 1) _load(1, _generation, quiet: true);
    });
    return const ProductListState(loading: true);
  }

  Future<void> open() => _restart('');

  Future<void> search(String query) => _restart(query.trim());

  Future<void> refresh() => _restart(state.query);

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    await _load(state.page + 1, _generation);
  }

  Future<void> _restart(String query) async {
    final generation = ++_generation;
    state = ProductListState(query: query, loading: true);
    await _load(1, generation);
  }

  Future<void> _load(int page, int generation, {bool quiet = false}) async {
    if (!quiet) state = state.copyWith(loading: true, clearError: true);
    try {
      final result = await ref.read(posCatalogProvider).search(state.query, page: page);
      if (generation != _generation) return;
      state = state.copyWith(
        items: page == 1 ? result.items : [...state.items, ...result.items],
        page: page,
        hasMore: result.hasMore,
        loading: false,
      );
    } catch (error) {
      if (generation != _generation || quiet) return;
      state = state.copyWith(loading: false, error: error);
    }
  }
}

final posProductListProvider = NotifierProvider<PosProductList, ProductListState>(PosProductList.new);
