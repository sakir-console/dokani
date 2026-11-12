import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/message_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../application/sale_submitter.dart';
import '../data/sale_models.dart';
import 'invoice_screen.dart';

/// A sale that is saved on this phone but not yet confirmed by the server.
///
/// It says so plainly, shows the receipt from what the phone knows, and
/// changes by itself when the server confirms or refuses the sale. There is
/// no QR code or customer link: those exist only once the server has the sale.
class PendingSaleScreen extends ConsumerWidget {
  const PendingSaleScreen({super.key, required this.clientUuid, this.justCompleted = false});

  final String clientUuid;
  final bool justCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final entry = ref.watch(outboxEntryProvider(clientUuid));
    final syncing = ref.watch(syncEngineProvider.select((status) => status.syncing));
    final shopName = ref.watch(sessionProvider)?.shop.name ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.invoice)),
      body: entry.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => EmptyState(icon: Icons.error_outline, title: l10n.errUnknown),
        data: (entry) {
          if (entry == null || entry.kind != 'sale') {
            return EmptyState(icon: Icons.receipt_long_outlined, title: l10n.pendingSaleGone);
          }

          final sale = Sale.fromJson(outboxDisplay(entry));
          final server = outboxServer(entry);
          final serverId = server['id'];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (entry.status == 'synced') ...[
                MessageBanner(
                  title: l10n.confirmedByServer,
                  message: l10n.invoiceNo('${server['invoice_no'] ?? ''}'),
                  tone: BannerTone.info,
                  action: serverId is int
                      ? Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            onPressed: () => context.pushReplacement('/sales/$serverId'),
                            child: Text(l10n.openInvoice),
                          ),
                        )
                      : null,
                ),
              ] else if (entry.status == 'failed') ...[
                MessageBanner(
                  title: l10n.syncFailedTitle,
                  message: (entry.errorMessage ?? '').isEmpty ? l10n.errUnknown : entry.errorMessage!,
                ),
              ] else ...[
                MessageBanner(title: l10n.savedOnPhoneTitle, message: l10n.savedOnPhoneBody, tone: BannerTone.warning),
              ],
              const SizedBox(height: 12),
              SaleReceipt(
                sale: sale,
                shopName: shopName,
                locale: locale,
                numberLabel: l10n.temporaryNo(sale.invoiceNo),
              ),
              if (entry.status != 'synced') ...[
                const SizedBox(height: 12),
                Text(l10n.qrAfterSync, style: text.bodyMedium?.copyWith(color: AppColors.textMuted), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: syncing ? null : () => ref.read(syncEngineProvider.notifier).sync(),
                  icon: syncing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync),
                  label: Text(syncing ? l10n.syncing : l10n.syncNow),
                ),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: justCompleted
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: PrimaryButton(
                  label: l10n.newSale,
                  icon: Icons.add,
                  onPressed: () {
                    context.go('/home');
                    unawaited(context.push('/pos'));
                  },
                ),
              ),
            )
          : null,
    );
  }
}
