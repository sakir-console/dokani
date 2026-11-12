import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../pos/data/sales_repository.dart';
import '../../pos/presentation/labels.dart';
import '../application/customer_directory.dart';
import 'customer_sheets.dart';

/// A customer's balance, totals and full ledger, with due collection.
class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final int customerId;

  void _reload(WidgetRef ref) => ref
    ..invalidate(customerProvider(customerId))
    ..invalidate(customerLedgerProvider(customerId))
    ..invalidate(dashboardProvider);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final customer = ref.watch(customerProvider(customerId));
    final ledger = ref.watch(customerLedgerProvider(customerId));
    final session = ref.watch(sessionProvider);
    final canCollect = session?.can('due.collect') ?? false;
    final canManage = session?.can('customers.manage') ?? false;

    String money(String amount) => Formatters.money(amount, locale);

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (canManage && customer.hasValue)
            IconButton(
              tooltip: l10n.edit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final saved = await showCustomerForm(context, customer: customer.value);
                if (saved != null) _reload(ref);
              },
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: customer.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: describeError(error, l10n),
          action: OutlinedButton(onPressed: () => _reload(ref), child: Text(l10n.retry)),
        ),
        data: (customer) {
          final due = customer.dueValue;

          return RefreshIndicator(
            onRefresh: () async => _reload(ref),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(header: true, child: Text(customer.name, style: text.titleLarge)),
                        Text(
                          [customer.phone, ?customer.address].join(' · '),
                          style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                        ),
                        const Divider(height: 28),
                        Text(l10n.outstandingDue, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                        Text(
                          // A negative balance means the shop holds the customer's money.
                          due < 0 ? l10n.advance(money(customer.currentDue.substring(1))) : money(customer.currentDue),
                          style: text.headlineMedium?.copyWith(
                            color: due > 0 ? AppColors.danger : (due < 0 ? AppColors.brandDark : null),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _Stat(label: l10n.totalPurchases, value: money(customer.totalPurchases))),
                            Expanded(child: _Stat(label: l10n.totalPaid, value: money(customer.totalPaid))),
                          ],
                        ),
                        if (due > 0 && canCollect) ...[
                          const SizedBox(height: 16),
                          PrimaryButton(
                            label: l10n.collectDue,
                            icon: Icons.payments_outlined,
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final result = await showCollectDueSheet(context, customer: customer);
                              if (result == null) return;
                              _reload(ref);
                              messenger.showSnackBar(
                                SnackBar(content: Text(result.pending ? l10n.savedOnPhoneWillSend : l10n.dueCollected)),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                  child: Text(l10n.ledger, style: text.titleMedium),
                ),
                ...ledger.when(
                  loading: () => [const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
                  error: (error, _) => [Text(describeError(error, l10n))],
                  data: (entries) => entries.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(l10n.noLedgerTitle, textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                          ),
                        ]
                      : [
                          for (final entry in entries) ...[
                            Card(
                              child: ListTile(
                                title: Text(
                                  [
                                    ledgerTypeLabel(entry.type, l10n),
                                    ?entry.invoiceNo,
                                    if (entry.paymentMethod != null) paymentMethodLabel(entry.paymentMethod!, l10n),
                                  ].join(' · '),
                                  style: text.titleSmall,
                                ),
                                subtitle: Text(
                                  '${DateFormat.yMMMd(locale).add_jm().format(entry.createdAt.toLocal())}\n${l10n.balance(money(entry.balanceAfter))}',
                                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                                ),
                                isThreeLine: true,
                                // Debit: they owe more (red, +). Credit: they owe less (green, −).
                                trailing: (double.tryParse(entry.debit) ?? 0) > 0
                                    ? Text('+ ${money(entry.debit)}', style: text.titleMedium?.copyWith(color: AppColors.danger))
                                    : Text('− ${money(entry.credit)}', style: text.titleMedium?.copyWith(color: AppColors.brandDark)),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
        Text(value, style: text.titleMedium),
      ],
    );
  }
}
