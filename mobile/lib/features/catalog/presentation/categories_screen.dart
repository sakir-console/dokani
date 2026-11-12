import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../application/catalog_providers.dart';
import '../data/catalog_repository.dart';
import '../data/models.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  /// Runs a change, refreshes the list, and reports a failure as a snackbar.
  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() change) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await change();
      ref.invalidate(categoriesProvider);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error, l10n))));
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final name = await showTextInputDialog(context, title: l10n.addCategory, label: l10n.categoryName, confirmLabel: l10n.add);
    if (name == null || !context.mounted) return;
    await _run(context, ref, () => ref.read(catalogRepositoryProvider).createCategory(name));
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Category category) async {
    final l10n = AppLocalizations.of(context);
    final name = await showTextInputDialog(context, title: l10n.rename, label: l10n.categoryName, initialValue: category.name);
    if (name == null || name == category.name || !context.mounted) return;
    await _run(context, ref, () => ref.read(catalogRepositoryProvider).renameCategory(category.id, name));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Category category) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      message: l10n.deleteCategoryConfirm(category.name),
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await _run(context, ref, () => ref.read(catalogRepositoryProvider).deleteCategory(category.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final categories = ref.watch(categoriesProvider);
    final canManage = ref.watch(sessionProvider)?.can('catalog.manage') ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.categories)),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add),
              label: Text(l10n.addCategory),
            )
          : null,
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: describeError(error, l10n),
          action: OutlinedButton(onPressed: () => ref.invalidate(categoriesProvider), child: Text(l10n.retry)),
        ),
        data: (items) => items.isEmpty
            ? EmptyState(icon: Icons.category_outlined, title: l10n.noCategoriesTitle, body: l10n.noCategoriesBody)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final category = items[index];
                  return Card(
                    child: ListTile(
                      title: Text(category.name),
                      trailing: canManage
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: l10n.rename,
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _rename(context, ref, category),
                                ),
                                IconButton(
                                  tooltip: l10n.delete,
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _delete(context, ref, category),
                                ),
                              ],
                            )
                          : null,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
