import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// The outcome of a picker: a chosen item, or "none" when [value] is null.
/// A dismissed sheet returns no Picked at all.
class Picked<T> {
  const Picked(this.value);

  final T? value;
}

/// A bottom sheet for choosing one item from a list, with search once the
/// list is long, an optional "none" row and an optional "add new" row.
Future<Picked<T>?> showPickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required String Function(T) labelOf,
  required bool Function(T) isSelected,
  bool allowNone = false,
  String? createLabel,
  Future<T?> Function()? onCreate,
}) {
  return showModalBottomSheet<Picked<T>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _PickerSheet<T>(
      title: title,
      items: items,
      labelOf: labelOf,
      isSelected: isSelected,
      allowNone: allowNone,
      createLabel: createLabel,
      onCreate: onCreate,
    ),
  );
}

class _PickerSheet<T> extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.items,
    required this.labelOf,
    required this.isSelected,
    required this.allowNone,
    this.createLabel,
    this.onCreate,
  });

  final String title;
  final List<T> items;
  final String Function(T) labelOf;
  final bool Function(T) isSelected;
  final bool allowNone;
  final String? createLabel;
  final Future<T?> Function()? onCreate;

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = _query.toLowerCase();
    final visible = widget.items.where((item) => widget.labelOf(item).toLowerCase().contains(query)).toList();
    final showSearch = widget.items.length > 8;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              ),
              if (showSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    decoration: InputDecoration(hintText: l10n.search, prefixIcon: const Icon(Icons.search)),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (widget.onCreate != null)
                      ListTile(
                        leading: const Icon(Icons.add, color: AppColors.brand),
                        title: Text(
                          widget.createLabel ?? l10n.add,
                          style: const TextStyle(color: AppColors.brandDark, fontWeight: FontWeight.w600),
                        ),
                        onTap: () async {
                          final navigator = Navigator.of(context);
                          final created = await widget.onCreate!();
                          if (created != null && navigator.mounted) navigator.pop(Picked<T>(created));
                        },
                      ),
                    if (widget.allowNone && _query.isEmpty)
                      ListTile(
                        title: Text(l10n.none, style: const TextStyle(color: AppColors.textMuted)),
                        onTap: () => Navigator.of(context).pop(Picked<T>(null)),
                      ),
                    for (final item in visible)
                      ListTile(
                        title: Text(widget.labelOf(item)),
                        trailing: widget.isSelected(item) ? const Icon(Icons.check, color: AppColors.brand) : null,
                        onTap: () => Navigator.of(context).pop(Picked<T>(item)),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A form field that shows the current choice and opens a picker when tapped.
class PickerField extends StatelessWidget {
  const PickerField({super.key, required this.label, required this.value, required this.onTap, this.errorText});

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(label, style: text.titleSmall)),
        Semantics(
          button: true,
          label: '$label: ${value ?? l10n.none}',
          excludeSemantics: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(errorText: errorText, suffixIcon: const Icon(Icons.expand_more)),
              child: Text(
                value ?? l10n.none,
                style: text.bodyLarge?.copyWith(color: value == null ? AppColors.textMuted : null),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
