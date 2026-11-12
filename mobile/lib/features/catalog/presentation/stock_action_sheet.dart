import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/message_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/app_localizations.dart';
import '../data/catalog_repository.dart';
import '../data/models.dart';
import 'product_widgets.dart';

enum StockAction { stockIn, stockOut, adjust }

/// Bottom sheet for receiving stock, removing stock, or correcting a count.
/// Completes with true when the change was saved.
Future<bool> showStockActionSheet(
  BuildContext context, {
  required StockAction action,
  required Product product,
  required Variant variant,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _StockActionSheet(action: action, product: product, variant: variant),
  );
  return saved ?? false;
}

class _StockActionSheet extends ConsumerStatefulWidget {
  const _StockActionSheet({required this.action, required this.product, required this.variant});

  final StockAction action;
  final Product product;
  final Variant variant;

  @override
  ConsumerState<_StockActionSheet> createState() => _StockActionSheetState();
}

class _StockActionSheetState extends ConsumerState<_StockActionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _cost = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  int get _quantityDecimals => widget.product.unit.allowsDecimal ? 3 : 0;

  @override
  void dispose() {
    _quantity.dispose();
    _cost.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final repository = ref.read(catalogRepositoryProvider);
    final quantity = Formatters.parseDecimal(_quantity.text, maxDecimals: _quantityDecimals)!;
    final note = _note.text.trim();

    setState(() => _busy = true);
    try {
      switch (widget.action) {
        case StockAction.stockIn:
          await repository.stockIn(
            variantId: widget.variant.id,
            quantity: quantity,
            unitCost: Formatters.parseDecimal(_cost.text, maxDecimals: 2),
            note: note.isEmpty ? null : note,
          );
        case StockAction.stockOut:
          await repository.stockOut(variantId: widget.variant.id, quantity: quantity, note: note);
        case StockAction.adjust:
          await repository.adjustStock(
            variantId: widget.variant.id,
            countedQuantity: quantity,
            note: note.isEmpty ? null : note,
          );
      }
      navigator.pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error, l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validateQuantity(String? value, AppLocalizations l10n) {
    final parsed = Formatters.parseDecimal(value, maxDecimals: _quantityDecimals);
    if (parsed == null) return _quantityDecimals == 0 ? l10n.errWholeNumber : l10n.errNumber;
    // Receiving or removing nothing is a mistake; a count of zero is valid.
    if (widget.action != StockAction.adjust && (double.tryParse(parsed) ?? 0) <= 0) return l10n.errNumber;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final action = widget.action;

    final title = switch (action) {
      StockAction.stockIn => l10n.stockIn,
      StockAction.stockOut => l10n.stockOut,
      StockAction.adjust => l10n.adjustStock,
    };
    final name = [widget.product.name, ?widget.variant.name].join(' · ');

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: text.titleLarge),
                const SizedBox(height: 2),
                Text(name, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                Text(
                  l10n.currentStock(stockLabel(widget.variant.stockQuantity, widget.product.unit, locale)),
                  style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[MessageBanner(message: _error!), const SizedBox(height: 16)],
                AppTextField(
                  label: action == StockAction.adjust ? l10n.countedQuantity : l10n.quantity,
                  controller: _quantity,
                  keyboardType: TextInputType.numberWithOptions(decimal: _quantityDecimals > 0),
                  validator: (value) => _validateQuantity(value, l10n),
                ),
                if (action == StockAction.stockIn) ...[
                  const SizedBox(height: 16),
                  AppTextField(
                    label: '${l10n.costPerUnit} (${l10n.optional})',
                    controller: _cost,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? null
                        : (Formatters.parseDecimal(value, maxDecimals: 2) == null ? l10n.errNumber : null),
                  ),
                ],
                const SizedBox(height: 16),
                AppTextField(
                  // Removing stock without a sale always needs a reason.
                  label: action == StockAction.stockOut ? l10n.reason : '${l10n.note} (${l10n.optional})',
                  hint: action == StockAction.stockOut ? l10n.reasonHint : null,
                  controller: _note,
                  maxLength: 255,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.sentences,
                  validator: action == StockAction.stockOut
                      ? (value) => (value == null || value.trim().isEmpty) ? l10n.errRequired : null
                      : null,
                ),
                const SizedBox(height: 20),
                PrimaryButton(label: l10n.save, busy: _busy, onPressed: _save),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
