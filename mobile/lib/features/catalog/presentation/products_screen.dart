import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/message_banner.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../scanner/barcode_scan.dart';
import '../application/catalog_providers.dart';
import '../data/catalog_repository.dart';
import '../data/models.dart';
import 'product_widgets.dart';

/// Looks a scanned code up and goes to the product, or offers to add it.
/// Shared by the home screen's "Scan barcode" action and the products screen.
Future<void> scanAndOpenProduct(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final canAdd = ref.read(sessionProvider)?.can('catalog.manage') ?? false;

  final code = await ref.read(barcodeScanProvider)(context);
  if (code == null) return;

  try {
    final match = await ref.read(catalogRepositoryProvider).lookupBarcode(code);
    if (match != null) {
      unawaited(router.push('/products/${match.product.id}'));
      return;
    }
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(describeError(error, l10n))));
    return;
  }

  if (!context.mounted) return;
  final add = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.unknownBarcodeTitle),
      content: Text(l10n.unknownBarcodeBody(code)),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
        if (canAdd)
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.addAsNewProduct),
          ),
      ],
    ),
  );
  if (add ?? false) unawaited(router.push('/products/new', extra: code));
}

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key, this.initialFilter = StockFilter.all});

  final StockFilter initialFilter;

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Start from a clean list with the filter this screen was opened with.
    Future.microtask(() => ref.read(productListProvider.notifier).open(stock: widget.initialFilter));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Fetch the next page shortly before the end is reached.
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      ref.read(productListProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    // Wait for a pause in typing: one request per word, not per letter.
    _debounce = Timer(const Duration(milliseconds: 350), () => ref.read(productListProvider.notifier).search(value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(productListProvider);
    final canManage = ref.watch(sessionProvider)?.can('catalog.manage') ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.products),
        actions: [
          IconButton(
            tooltip: l10n.scanBarcode,
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => scanAndOpenProduct(context, ref),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/products/new'),
              icon: const Icon(Icons.add),
              label: Text(l10n.addProduct),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.searchProducts,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l10n.cancel,
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _onSearchChanged('');
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final (filter, label) in [
                  (StockFilter.all, l10n.all),
                  (StockFilter.low, l10n.lowStock),
                  (StockFilter.out, l10n.outOfStock),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: state.stock == filter,
                      onSelected: (_) => ref.read(productListProvider.notifier).filterByStock(filter),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _buildList(context, state, l10n, canManage)),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, ProductListState state, AppLocalizations l10n, bool canManage) {
    if (state.isInitialLoad) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.items.isEmpty && state.error != null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: describeError(state.error!, l10n),
        action: OutlinedButton(
          onPressed: () => ref.read(productListProvider.notifier).refresh(),
          child: Text(l10n.retry),
        ),
      );
    }

    if (state.items.isEmpty) {
      return state.isFiltered
          ? EmptyState(icon: Icons.search_off, title: l10n.noResultsTitle, body: l10n.noResultsBody)
          : EmptyState(
              icon: Icons.inventory_2_outlined,
              title: l10n.noProductsTitle,
              body: canManage ? l10n.noProductsBody : null,
            );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(productListProvider.notifier).refresh(),
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: state.items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index < state.items.length) {
            final product = state.items[index];
            return ProductTile(product: product, onTap: () => context.push('/products/${product.id}'));
          }
          if (state.error != null) {
            return InkWell(
              onTap: () => ref.read(productListProvider.notifier).loadMore(),
              child: MessageBanner(message: l10n.loadMoreFailed, tone: BannerTone.warning),
            );
          }
          return state.hasMore
              ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
              : const SizedBox.shrink();
        },
      ),
    );
  }
}
