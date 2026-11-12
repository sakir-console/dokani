import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../data/notification_repository.dart';

/// Notices from the server, newest first. A notice about a sale opens that sale.
class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  Future<void> _markAllRead(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(notificationRepositoryProvider).markAllRead();
      ref.invalidate(noticesProvider);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error, l10n))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final notices = ref.watch(noticesProvider);
    final unread = notices.value?.unread ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.alerts),
        actions: [
          if (unread > 0) TextButton(onPressed: () => _markAllRead(context, ref), child: Text(l10n.markAllRead)),
          const SizedBox(width: 4),
        ],
      ),
      body: notices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: describeError(error, l10n),
          action: OutlinedButton(onPressed: () => ref.invalidate(noticesProvider), child: Text(l10n.retry)),
        ),
        data: (list) => list.items.isEmpty
            ? EmptyState(icon: Icons.notifications_none, title: l10n.noAlertsTitle, body: l10n.noAlertsBody)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: list.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final notice = list.items[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: Icon(
                        notice.type == 'stock_conflict' ? Icons.inventory_2_outlined : Icons.notifications_outlined,
                        color: notice.read ? AppColors.textMuted : AppColors.warning,
                      ),
                      title: Text(
                        notice.title,
                        style: text.titleSmall?.copyWith(fontWeight: notice.read ? FontWeight.w500 : FontWeight.w700),
                      ),
                      subtitle: Text(
                        [?notice.body, DateFormat.MMMd(locale).add_jm().format(notice.createdAt.toLocal())].join('\n'),
                        style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                      ),
                      isThreeLine: notice.body != null,
                      trailing: notice.saleId == null ? null : const Icon(Icons.chevron_right),
                      onTap: notice.saleId == null ? null : () => context.push('/sales/${notice.saleId}'),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
