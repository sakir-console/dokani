import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/message_banner.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/session.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/presentation/products_screen.dart';
import '../../shop/data/shop_types.dart';

/// The signed-in landing screen.
///
/// Shows the shop, a stock overview, quick actions for the catalogue, and the
/// plan. Sales figures and the "New sale" action arrive with the POS (Phase 3).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authControllerProvider).value;
    final session = auth?.session;

    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appName),
        actions: [
          IconButton(
            tooltip: l10n.settings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(stockSummaryProvider);
          await ref.read(authControllerProvider.notifier).refresh();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (auth!.isStale) ...[
              MessageBanner(message: l10n.offlineBanner, tone: BannerTone.warning),
              const SizedBox(height: 12),
            ],
            if (session.shop.status == ShopStatus.suspended) ...[
              MessageBanner(title: l10n.shopSuspendedTitle, message: l10n.shopSuspendedBody),
              const SizedBox(height: 12),
            ] else if (session.shop.status == ShopStatus.inactive) ...[
              MessageBanner(
                title: l10n.shopInactiveTitle,
                message: l10n.shopInactiveBody,
                tone: BannerTone.warning,
              ),
              const SizedBox(height: 12),
            ],
            _ShopCard(session: session),
            // A shop that is not active cannot use the catalogue; the server would refuse every call.
            if (session.shop.status == ShopStatus.active) ...[
              const SizedBox(height: 12),
              const _StockCard(),
              const SizedBox(height: 12),
              _QuickActions(session: session),
            ],
            const SizedBox(height: 12),
            _PlanCard(session: session),
          ],
        ),
      ),
    );
  }
}

/// Product count and stock alerts. Tapping an alert opens the matching list.
class _StockCard extends ConsumerWidget {
  const _StockCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final numbers = NumberFormat.decimalPattern(locale);
    final summary = ref.watch(stockSummaryProvider).value;

    String count(int? value) => value == null ? '–' : numbers.format(value);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            _StockStat(label: l10n.totalProducts, value: count(summary?.totalProducts), onTap: () => context.push('/products')),
            const VerticalDivider(width: 1),
            _StockStat(
              label: l10n.lowStock,
              value: count(summary?.lowStock),
              color: (summary?.lowStock ?? 0) > 0 ? AppColors.warning : null,
              onTap: () => context.push('/products?stock=low'),
            ),
            const VerticalDivider(width: 1),
            _StockStat(
              label: l10n.outOfStock,
              value: count(summary?.outOfStock),
              color: (summary?.outOfStock ?? 0) > 0 ? AppColors.danger : null,
              onTap: () => context.push('/products?stock=out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockStat extends StatelessWidget {
  const _StockStat({required this.label, required this.value, required this.onTap, this.color});

  final String label;
  final String value;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value, style: text.headlineSmall?.copyWith(color: color)),
              const SizedBox(height: 2),
              Text(
                label,
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Large buttons for the things a shopkeeper does most. Only actions that
/// work for this user's role and plan are shown.
class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final canManage = session.can('catalog.manage');

    // (key, icon, label, action). The key gives each button a stable identity.
    final actions = <(String, IconData, String, VoidCallback)>[
      ('products', Icons.inventory_2_outlined, l10n.products, () => context.push('/products')),
      if (canManage) ('add-product', Icons.add_box_outlined, l10n.addProduct, () => context.push('/products/new')),
      ('scan', Icons.qr_code_scanner, l10n.scanBarcode, () => scanAndOpenProduct(context, ref)),
      ('categories', Icons.category_outlined, l10n.categories, () => context.push('/categories')),
      if (session.hasModule('vendors'))
        ('vendors', Icons.local_shipping_outlined, l10n.vendors, () => context.push('/vendors')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(l10n.quickActions, style: Theme.of(context).textTheme.titleSmall),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;
            final width = (constraints.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (id, icon, label, onTap) in actions)
                  SizedBox(
                    key: ValueKey('quick-$id'),
                    width: width,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: onTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                          child: Row(
                            children: [
                              Icon(icon, color: AppColors.brand, size: 26),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  label,
                                  style: Theme.of(context).textTheme.titleSmall,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final shop = session.shop;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _ShopLogo(shop: shop),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shop.name, style: text.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '${shopTypeLabel(shop.shopType, l10n)} · ${session.user.name} (${roleLabel(session.role, l10n)})',
                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                  if (shop.address != null && shop.address!.isNotEmpty)
                    Text(shop.address!, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopLogo extends StatelessWidget {
  const _ShopLogo({required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context) {
    final initial = shop.name.isEmpty ? '?' : shop.name.characters.first.toUpperCase();
    final placeholder = Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(14)),
      child: Text(
        initial,
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.brandDark),
      ),
    );

    if (shop.logoUrl == null) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        shop.logoUrl!,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        cacheWidth: 180, // decode small: saves memory on low-end phones
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final numbers = NumberFormat.decimalPattern(locale);
    final subscription = session.subscription;

    String limit(int? value) => value == null ? l10n.unlimited : numbers.format(value);

    final modules = [
      for (final key in session.modules) ?moduleLabel(key, l10n),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.workspace_premium_outlined, color: AppColors.brand),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.planLine(subscription.planName), style: text.titleMedium)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subscription.endsAt == null
                  ? l10n.planNoExpiry
                  : l10n.planExpires(DateFormat.yMMMd(locale).format(subscription.endsAt!.toLocal())),
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const Divider(height: 28),
            _LimitRow(label: l10n.productLimit, value: limit(session.maxProducts)),
            const SizedBox(height: 8),
            _LimitRow(label: l10n.staffLimit, value: limit(session.maxUsers)),
            if (modules.isNotEmpty) ...[
              const Divider(height: 28),
              Text(l10n.features, style: text.titleSmall),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in modules)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(label, style: text.bodyMedium),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LimitRow extends StatelessWidget {
  const _LimitRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(child: Text(label, style: text.bodyLarge?.copyWith(color: AppColors.textMuted))),
        Text(value, style: text.titleMedium),
      ],
    );
  }
}
