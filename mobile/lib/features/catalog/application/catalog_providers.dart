import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog_repository.dart';
import '../data/models.dart';

/// Reference lists. Loaded when first needed, refreshed with ref.invalidate
/// after a change.
final categoriesProvider = FutureProvider<List<Category>>((ref) => ref.watch(catalogRepositoryProvider).categories());

final brandsProvider = FutureProvider<List<NamedRef>>((ref) => ref.watch(catalogRepositoryProvider).brands());

final unitsProvider = FutureProvider<List<Unit>>((ref) => ref.watch(catalogRepositoryProvider).units());

final stockSummaryProvider =
    FutureProvider.autoDispose<StockSummary>((ref) => ref.watch(catalogRepositoryProvider).stockSummary());

final productProvider =
    FutureProvider.autoDispose.family<Product, int>((ref, id) => ref.watch(catalogRepositoryProvider).product(id));

class ProductListState {
  const ProductListState({
    this.items = const [],
    this.query = '',
    this.stock = StockFilter.all,
    this.page = 0,
    this.hasMore = true,
    this.loading = false,
    this.error,
  });

  final List<Product> items;
  final String query;
  final StockFilter stock;
  final int page;
  final bool hasMore;
  final bool loading;
  final Object? error;

  /// Nothing loaded yet for the current search.
  bool get isInitialLoad => loading && items.isEmpty;
  bool get isFiltered => query.isNotEmpty || stock != StockFilter.all;

  ProductListState copyWith({
    List<Product>? items,
    String? query,
    StockFilter? stock,
    int? page,
    bool? hasMore,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) =>
      ProductListState(
        items: items ?? this.items,
        query: query ?? this.query,
        stock: stock ?? this.stock,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// The products screen's list: search, stock filter and page-by-page loading.
class ProductListController extends Notifier<ProductListState> {
  /// Bumped on every new search so a slow, outdated response is ignored.
  int _generation = 0;

  @override
  ProductListState build() => const ProductListState(loading: true);

  /// Starts over with no search text and the given stock filter.
  /// The products screen calls this each time it opens.
  Future<void> open({StockFilter stock = StockFilter.all}) => _restart(ProductListState(stock: stock));

  Future<void> search(String query) => _restart(state.copyWith(query: query.trim()));

  Future<void> filterByStock(StockFilter stock) => _restart(state.copyWith(stock: stock));

  Future<void> refresh() => _restart(state);

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    await _load(state.page + 1, _generation);
  }

  Future<void> _restart(ProductListState next) async {
    final generation = ++_generation;
    state = ProductListState(query: next.query, stock: next.stock, loading: true);
    await _load(1, generation);
  }

  Future<void> _load(int page, int generation) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result = await ref
          .read(catalogRepositoryProvider)
          .products(query: state.query, stock: state.stock, page: page);
      if (generation != _generation) return;
      state = state.copyWith(
        items: page == 1 ? result.items : [...state.items, ...result.items],
        page: result.currentPage,
        hasMore: result.hasMore,
        loading: false,
      );
    } catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(loading: false, error: error);
    }
  }
}

final productListProvider = NotifierProvider<ProductListController, ProductListState>(ProductListController.new);
