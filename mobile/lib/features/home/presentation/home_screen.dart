import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/message_banner.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/session.dart';
import '../../shop/data/shop_types.dart';

/// The signed-in landing screen.
///
/// In this phase it shows the shop, its plan and what the plan includes.
/// The sales dashboard and quick actions are added with the POS (Phase 3).
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
        onRefresh: () => ref.read(authControllerProvider.notifier).refresh(),
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
            const SizedBox(height: 12),
            _PlanCard(session: session),
          ],
        ),
      ),
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
