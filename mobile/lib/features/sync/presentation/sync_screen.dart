import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/database/local_database.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/message_banner.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../pos/application/sale_submitter.dart';

/// Everything made on this phone that the server has not confirmed: what is
/// waiting, what was refused and why, and a button to send it now.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  Future<void> _remove(BuildContext context, WidgetRef ref, OutboxEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      message: l10n.removeFromPhoneConfirm,
      confirmLabel: l10n.remove,
      destructive: true,
    );
    if (confirmed) await ref.read(saleSubmitterProvider).discardFailed(entry);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final status = ref.watch(syncEngineProvider);
    final entries = ref.watch(unsyncedProvider).value ?? const <OutboxEntry>[];
    // Removing a refused sale is as serious as cancelling one.
    final canRemove = ref.watch(sessionProvider)?.can('sales.void') ?? false;

    final lastError = status.lastError;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    status.lastSyncedAt == null
                        ? l10n.neverSynced
                        : l10n.lastSynced(DateFormat.MMMd(locale).add_jm().format(status.lastSyncedAt!)),
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entries.isEmpty ? l10n.allSyncedTitle : l10n.unsyncedCount(entries.length),
                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: status.syncing ? null : () => ref.read(syncEngineProvider.notifier).sync(),
                    icon: status.syncing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync),
                    label: Text(status.syncing ? l10n.syncing : l10n.syncNow),
                  ),
                ],
              ),
            ),
          ),
          if (!status.syncing && lastError != null) ...[
            const SizedBox(height: 12),
            MessageBanner(
              message: status.offline ? l10n.syncOffline : describeError(lastError, l10n),
              tone: status.offline ? BannerTone.warning : BannerTone.error,
            ),
          ],
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: EmptyState(icon: Icons.cloud_done_outlined, title: l10n.allSyncedTitle, body: l10n.allSyncedBody),
            )
          else
            for (final entry in entries) ...[
              _EntryCard(
                entry: entry,
                locale: locale,
                onOpen: entry.kind == 'sale' ? () => context.push('/sales/pending/${entry.clientUuid}') : null,
                onRemove: entry.status == 'failed' && canRemove ? () => _remove(context, ref, entry) : null,
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.locale, this.onOpen, this.onRemove});

  final OutboxEntry entry;
  final String locale;
  final VoidCallback? onOpen;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final display = outboxDisplay(entry);
    final failed = entry.status == 'failed';
    final isSale = entry.kind == 'sale';

    final title = isSale
        ? '${l10n.outboxSale} · ${display['invoice_no'] ?? ''}'
        : '${l10n.outboxDueCollection} · ${display['customer_name'] ?? ''}';
    final amount = Formatters.money('${isSale ? display['grand_total'] : display['amount']}', locale);
    final when = DateFormat.MMMd(locale).add_jm().format(entry.createdAt);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: Icon(
                  failed ? Icons.error_outline : Icons.schedule,
                  color: failed ? AppColors.danger : AppColors.warning,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium),
                    Text('$amount · $when', style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                    const SizedBox(height: 2),
                    Text(
                      failed
                          ? '${l10n.syncFailedTitle}: ${(entry.errorMessage ?? '').isEmpty ? l10n.errUnknown : entry.errorMessage}'
                          : l10n.pendingSync,
                      style: text.bodyMedium?.copyWith(
                        color: failed ? AppColors.danger : AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(tooltip: l10n.removeFromPhone, icon: const Icon(Icons.delete_outline), onPressed: onRemove)
              else if (onOpen != null)
                const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.chevron_right)),
            ],
          ),
        ),
      ),
    );
  }
}
