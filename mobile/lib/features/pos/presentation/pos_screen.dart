import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/money/exact.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/data/models.dart';
import '../../catalog/presentation/product_widgets.dart';
import '../../scanner/barcode_scan.dart';
import '../application/cart_controller.dart';
import '../application/pos_catalog.dart';
import '../application/pos_product_list.dart';

/// The counter: find products by search or by scanning, tap to add them to
/// the cart. Tapping again adds one more.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  bool get _allowNegative => ref.read(sessionProvider)?.settings['allow_negative_stock'] == true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
        ref.read(posProductListProvider.notifier).loadMore();
      }
    });
    Future.microtask(() => ref.read(posProductListProvider.notifier).open());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Adds a variant and reports what happened in words.
  ScanFeedback _add(Product product, Variant variant) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final title = variant.name == null ? product.name : '${product.name} — ${variant.name}';

    final result = ref.read(cartProvider.notifier).add(product, variant, allowNegativeStock: _allowNegative);
    if (result == CartAddResult.outOfStock) {
      return ScanFeedback(
        '$title: ${l10n.notEnoughStock(stockLabel(variant.stockQuantity, product.unit, locale))}',
        ok: false,
      );
    }

    final line = ref.read(cartProvider).lines.firstWhere((l) => l.variantId == variant.id);
    return ScanFeedback(l10n.addedToCart(title, Formatters.quantity(Exact.quantity(line.quantityMilli), locale)));
  }

  Future<void> _onProductTap(Product product) async {
    final messenger = ScaffoldMessenger.of(context);

    var variant = product.variants.length == 1 ? product.variants.first : null;
    variant ??= await showModalBottomSheet<Variant>(
      context: context,
      showDragHandle: true,
      builder: (context) => _VariantSheet(product: product),
    );
    if (variant == null || !mounted) return;

    final feedback = _add(product, variant);
    if (!feedback.ok) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(feedback.message)));
    }
  }

  Future<void> _scan() async {
    final l10n = AppLocalizations.of(context);
    final catalog = ref.read(posCatalogProvider);

    await ref.read(continuousScanProvider)(context, (code) async {
      try {
        final match = await catalog.lookupBarcode(code);
        if (match == null) return ScanFeedback(l10n.scanUnknown(code), ok: false);
        if (!mounted) return ScanFeedback(l10n.errUnknown, ok: false);
        // The barcode identifies the exact variant, so no choice is needed.
        final variant = match.product.variants.firstWhere((v) => v.id == match.variantId);
        return _add(match.product, variant);
      } catch (error) {
        return ScanFeedback(describeError(error, l10n), ok: false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final products = ref.watch(posProductListProvider);
    final cart = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.newSale),
        actions: [
          IconButton(tooltip: l10n.scanBarcode, icon: const Icon(Icons.qr_code_scanner), onPressed: _scan),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: () => context.push('/pos/cart'),
                  child: Row(
                    children: [
                      const Icon(Icons.shopping_cart_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.cartSummary(cart.lineCount, Formatters.money(Exact.money(cart.grandTotalPaisa), locale)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(l10n.viewCart),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(hintText: l10n.searchProducts, prefixIcon: const Icon(Icons.search)),
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 350),
                  () => ref.read(posProductListProvider.notifier).search(value),
                );
              },
            ),
          ),
          Expanded(child: _productList(products, cart, l10n, locale)),
        ],
      ),
    );
  }

  Widget _productList(ProductListState products, CartState cart, AppLocalizations l10n, String locale) {
    if (products.isInitialLoad) return const Center(child: CircularProgressIndicator());

    if (products.items.isEmpty && products.error != null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: describeError(products.error!, l10n),
        action: OutlinedButton(
          onPressed: () => ref.read(posProductListProvider.notifier).refresh(),
          child: Text(l10n.retry),
        ),
      );
    }

    if (products.items.isEmpty) {
      return products.isFiltered
          ? EmptyState(icon: Icons.search_off, title: l10n.noResultsTitle, body: l10n.noResultsBody)
          : EmptyState(icon: Icons.inventory_2_outlined, title: l10n.noProductsTitle);
    }

    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: products.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final product = products.items[index];
        final inCart = cart.lines
            .where((line) => product.variants.any((v) => v.id == line.variantId))
            .fold(0, (sum, line) => sum + line.quantityMilli);

        return _PosTile(product: product, inCartMilli: inCart, onTap: () => _onProductTap(product));
      },
    );
  }
}

class _PosTile extends StatelessWidget {
  const _PosTile({required this.product, required this.inCartMilli, required this.onTap});

  final Product product;
  final int inCartMilli;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final inCart = inCartMilli > 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: inCart ? AppColors.brand : AppColors.border, width: inCart ? 2 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ProductThumb(name: product.name, imageUrl: product.imageUrl, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            stockLabel(product.totalStock, product.unit, locale),
                            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (product.stockStatus == StockStatus.out) ...[
                          const SizedBox(width: 8),
                          const StockBadge(status: StockStatus.out),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(priceLabel(product, l10n, locale), style: text.titleMedium),
                  if (inCart)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        '× ${Formatters.quantity(Exact.quantity(inCartMilli), locale)}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Choose which size / colour / model to sell.
class _VariantSheet extends StatelessWidget {
  const _VariantSheet({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: text.titleLarge),
                Text(l10n.chooseVariant, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final variant in product.variants)
                  ListTile(
                    title: Text(variant.name ?? product.name, style: text.titleMedium),
                    subtitle: Text(stockLabel(variant.stockQuantity, product.unit, locale)),
                    trailing: Text(Formatters.money(variant.sellingPrice, locale), style: text.titleMedium),
                    onTap: () => Navigator.of(context).pop(variant),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
