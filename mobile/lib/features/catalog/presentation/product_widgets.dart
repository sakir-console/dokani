import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../data/models.dart';

/// Product photo, or the first letter of the name on a tinted square.
class ProductThumb extends StatelessWidget {
  const ProductThumb({super.key, required this.name, this.imageUrl, this.size = 56});

  final String name;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(12)),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w600, color: AppColors.textMuted),
      ),
    );

    if (imageUrl == null) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Decode at display size: a list of full-size photos would exhaust a low-end phone's memory.
        cacheWidth: (size * 3).round(),
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

class StockBadge extends StatelessWidget {
  const StockBadge({super.key, required this.status});

  final StockStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (String label, Color foreground, Color background) = switch (status) {
      StockStatus.out => (l10n.outOfStock, AppColors.danger, AppColors.dangerSurface),
      StockStatus.low => (l10n.lowStock, AppColors.warning, AppColors.warningSurface),
      StockStatus.inStock => (l10n.inStock, AppColors.brandDark, const Color(0xFFECFDF5)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// "৳60" for one price, "৳350 – ৳370" when variants differ.
String priceLabel(Product product, AppLocalizations l10n, String locale) {
  if (product.variants.isEmpty) return '';
  final prices = product.variants.map((v) => v.sellingPrice).toList()
    ..sort((a, b) => (double.tryParse(a) ?? 0).compareTo(double.tryParse(b) ?? 0));
  final lowest = Formatters.money(prices.first, locale);
  final highest = Formatters.money(prices.last, locale);
  return lowest == highest ? lowest : l10n.priceRange(lowest, highest);
}

/// "25.5 kg"
String stockLabel(String quantity, Unit unit, String locale) =>
    '${Formatters.quantity(quantity, locale)} ${unit.isBuiltIn ? unit.label(locale) : unit.shortName}';

class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;

    final details = [
      ?product.category?.name,
      if (product.hasVariants) l10n.variantsCount(product.variants.length),
    ].join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ProductThumb(name: product.name, imageUrl: product.imageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            stockLabel(product.totalStock, product.unit, locale),
                            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (product.stockStatus != StockStatus.inStock) ...[
                          const SizedBox(width: 8),
                          StockBadge(status: product.stockStatus),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(priceLabel(product, l10n, locale), style: text.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
