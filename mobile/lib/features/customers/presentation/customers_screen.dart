import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../data/customer_repository.dart';
import 'customer_sheets.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key, this.dueOnly = false});

  /// Opened from "Collect due": start with only the people who owe money.
  final bool dueOnly;

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _query = '';
  late bool _dueOnly = widget.dueOnly;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _add() async {
    final router = GoRouter.of(context);
    final created = await showCustomerForm(context);
    if (created == null) return;
    ref.invalidate(customersProvider);
    unawaited(router.push('/customers/${created.id}'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final canManage = ref.watch(sessionProvider)?.can('customers.manage') ?? false;
    final customers = ref.watch(customersProvider((query: _query, hasDue: _dueOnly)));

    return Scaffold(
      appBar: AppBar(title: Text(_dueOnly ? l10n.collectDue : l10n.customers)),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.person_add_alt), label: Text(l10n.addCustomer))
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              textInputAction: TextInputAction.search,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(hintText: l10n.searchCustomers, prefixIcon: const Icon(Icons.search)),
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _query = value.trim()));
              },
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilterChip(
                label: Text(l10n.withDue),
                selected: _dueOnly,
                onSelected: (value) => setState(() => _dueOnly = value),
              ),
            ),
          ),
          Expanded(
            child: customers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(
                icon: Icons.cloud_off_outlined,
                title: describeError(error, l10n),
                action: OutlinedButton(onPressed: () => ref.invalidate(customersProvider), child: Text(l10n.retry)),
              ),
              data: (items) {
                if (items.isEmpty) {
                  if (_query.isNotEmpty) return EmptyState(icon: Icons.search_off, title: l10n.noResultsTitle);
                  return _dueOnly
                      ? EmptyState(icon: Icons.verified_outlined, title: l10n.noDuesTitle)
                      : EmptyState(icon: Icons.people_outline, title: l10n.noCustomersTitle, body: l10n.noCustomersBody);
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final customer = items[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        title: Text(customer.name, style: text.titleMedium),
                        subtitle: Text(customer.phone, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                        trailing: customer.dueValue > 0
                            ? Text(
                                Formatters.money(customer.currentDue, locale),
                                style: text.titleMedium?.copyWith(color: AppColors.danger),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: () async {
                          await context.push('/customers/${customer.id}');
                          ref.invalidate(customersProvider);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
