import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../application/catalog_providers.dart';
import '../data/catalog_repository.dart';
import '../data/models.dart';
import 'product_widgets.dart';
import 'stock_action_sheet.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final int productId;

  Future<void> _delete(BuildContext context, WidgetRef ref, Product product) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final confirmed = await showConfirmDialog(
      context,
      message: l10n.deleteProductConfirm(product.name),
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (!confirmed) return;

    try {
      await ref.read(catalogRepositoryProvider).deleteProduct(product.id);
      ref.invalidate(stockSummaryProvider);
      await ref.read(productListProvider.notifier).refresh();
      router.pop();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error, l10n))));
    }
  }

  Future<void> _changeStock(BuildContext context, WidgetRef ref, StockAction action, Product product, Variant variant) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final saved = await showStockActionSheet(context, action: action, product: product, variant: variant);
    if (!saved) return;

    ref
      ..invalidate(productProvider(productId))
      ..invalidate(stockSummaryProvider);
    await ref.read(productListProvider.notifier).refresh();
    messenger.showSnackBar(SnackBar(content: Text(l10n.stockUpdated)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final product = ref.watch(productProvider(productId));
    final session = ref.watch(sessionProvider);
    final canManage = session?.can('catalog.manage') ?? false;
    final canStock = session?.can('inventory.manage') ?? false;

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (canManage && product.hasValue) ...[
            IconButton(
              tooltip: l10n.edit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/products/$productId/edit'),
            ),
            IconButton(
              tooltip: l10n.deleteProduct,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, ref, product.value!),
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
      body: product.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: describeError(error, l10n),
          action: OutlinedButton(
            onPressed: () => ref.invalidate(productProvider(productId)),
            child: Text(l10n.retry),
          ),
        ),
        data: (product) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(productProvider(productId)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              _Header(product: product),
              const SizedBox(height: 12),
              for (final variant in product.variants) ...[
                _VariantCard(
                  product: product,
                  variant: variant,
                  showCost: canManage,
                  onAction: canStock ? (action) => _changeStock(context, ref, action, product, variant) : null,
                ),
                const SizedBox(height: 8),
              ],
              if ((product.description ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(product.description!, style: Theme.of(context).textTheme.bodyMedium),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    final facts = <(String, String)>[
      if (product.category != null) (l10n.category, product.category!.name),
      if (product.brand != null) (l10n.brand, product.brand!.name),
      if (product.vendor != null) (l10n.vendor, product.vendor!.name),
      if ((product.storageLocation ?? '').isNotEmpty) (l10n.storageLocation, product.storageLocation!),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProductThumb(name: product.name, imageUrl: product.imageUrl, size: 72),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(header: true, child: Text(product.name, style: text.titleLarge)),
                      const SizedBox(height: 4),
                      StockBadge(status: product.stockStatus),
                    ],
                  ),
                ),
              ],
            ),
            if (facts.isNotEmpty) const Divider(height: 28),
            for (final (label, value) in facts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(label, style: text.bodyMedium?.copyWith(color: AppColors.textMuted))),
                    Expanded(flex: 2, child: Text(value, style: text.bodyMedium, textAlign: TextAlign.end)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VariantCard extends StatelessWidget {
  const _VariantCard({required this.product, required this.variant, required this.showCost, required this.onAction});

  final Product product;
  final Variant variant;
  final bool showCost;
  final ValueChanged<StockAction>? onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (variant.name != null) Text(variant.name!, style: text.titleMedium),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${l10n.stock}: ${stockLabel(variant.stockQuantity, product.unit, locale)}',
                              style: text.bodyLarge,
                            ),
                          ),
                          if (variant.stockStatus != StockStatus.inStock) ...[
                            const SizedBox(width: 8),
                            StockBadge(status: variant.stockStatus),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(Formatters.money(variant.sellingPrice, locale), style: text.titleLarge),
                    // The purchase cost is the owner's business, not every cashier's.
                    if (showCost)
                      Text(
                        l10n.costLabel(Formatters.money(variant.purchasePrice, locale)),
                        style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                      ),
                  ],
                ),
              ],
            ),
            if (variant.barcodes.isNotEmpty || (variant.sku ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                [
                  if (variant.barcodes.isNotEmpty) '${l10n.barcode}: ${variant.barcodes.join(', ')}',
                  if ((variant.sku ?? '').isNotEmpty) '${l10n.sku}: ${variant.sku}',
                ].join('  ·  '),
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
            if (onAction != null) ...[
              const Divider(height: 20),
              Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () => onAction!(StockAction.stockIn),
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    label: Text(l10n.stockIn),
                  ),
                  TextButton.icon(
                    onPressed: () => onAction!(StockAction.stockOut),
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    label: Text(l10n.stockOut),
                  ),
                  TextButton.icon(
                    onPressed: () => onAction!(StockAction.adjust),
                    icon: const Icon(Icons.fact_check_outlined, size: 20),
                    label: Text(l10n.adjustStock),
                  ),
                ],
              ),
            ] else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
