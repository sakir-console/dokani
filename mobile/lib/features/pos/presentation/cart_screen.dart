import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/money/exact.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../application/cart_controller.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  /// Asks for an amount. Returns paisa, or null if cancelled or not a number.
  Future<int?> _askAmount(BuildContext context, String title, int currentPaisa) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final typed = await showTextInputDialog(
      context,
      title: title,
      label: l10n.amount,
      initialValue: currentPaisa == 0 ? '' : Formatters.editable(Exact.money(currentPaisa)),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      maxLength: 12,
    );
    if (typed == null) return null;

    final parsed = Formatters.parseDecimal(typed, maxDecimals: 2);
    if (parsed == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errNumber)));
      return null;
    }
    return Exact.paisa(parsed);
  }

  Future<void> _editQuantity(BuildContext context, WidgetRef ref, CartLine line, bool allowNegative) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final locale = Localizations.localeOf(context).languageCode;

    final typed = await showTextInputDialog(
      context,
      title: line.title,
      label: l10n.quantityLabel,
      initialValue: Formatters.editable(Exact.quantity(line.quantityMilli)),
      keyboardType: TextInputType.numberWithOptions(decimal: line.allowsDecimal),
      maxLength: 12,
    );
    if (typed == null) return;

    final parsed = Formatters.parseDecimal(typed, maxDecimals: line.allowsDecimal ? 3 : 0);
    if (parsed == null) {
      messenger.showSnackBar(SnackBar(content: Text(line.allowsDecimal ? l10n.errNumber : l10n.errWholeNumber)));
      return;
    }

    final ok = ref
        .read(cartProvider.notifier)
        .setQuantity(line.variantId, Exact.milli(parsed), allowNegativeStock: allowNegative);
    if (!ok) {
      final available = '${Formatters.quantity(Exact.quantity(line.stockMilli), locale)} ${line.unitLabel(locale)}';
      messenger.showSnackBar(SnackBar(content: Text(l10n.notEnoughStock(available))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final cart = ref.watch(cartProvider);
    final controller = ref.read(cartProvider.notifier);
    final allowNegative = ref.watch(sessionProvider)?.settings['allow_negative_stock'] == true;

    String money(int paisa) => Formatters.money(Exact.money(paisa), locale);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cart),
        actions: [
          if (!cart.isEmpty)
            IconButton(
              tooltip: l10n.clearCart,
              icon: const Icon(Icons.remove_shopping_cart_outlined),
              onPressed: () async {
                final confirmed = await showConfirmDialog(
                  context,
                  message: l10n.clearCartConfirm,
                  confirmLabel: l10n.clearCart,
                  destructive: true,
                );
                if (confirmed) controller.clear();
              },
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: cart.isEmpty
          ? EmptyState(icon: Icons.shopping_cart_outlined, title: l10n.cartEmptyTitle, body: l10n.cartEmptyBody)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                for (final line in cart.lines) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: Text(line.title, style: text.titleMedium)),
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(money(line.totalPaisa), style: text.titleMedium),
                              ),
                            ],
                          ),
                          Text(
                            '${money(line.unitPricePaisa)} / ${line.unitLabel(locale)}',
                            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                          ),
                          Row(
                            children: [
                              IconButton(
                                tooltip: '−',
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () => controller.setQuantity(line.variantId, line.quantityMilli - 1000),
                              ),
                              // Tap the number to type an exact quantity (2.5 kg, 12 pieces).
                              TextButton(
                                onPressed: () => _editQuantity(context, ref, line, allowNegative),
                                child: Text(
                                  Formatters.quantity(Exact.quantity(line.quantityMilli), locale),
                                  style: text.titleMedium,
                                ),
                              ),
                              IconButton(
                                tooltip: '+',
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () {
                                  final ok = controller.setQuantity(
                                    line.variantId,
                                    line.quantityMilli + 1000,
                                    allowNegativeStock: allowNegative,
                                  );
                                  if (!ok) {
                                    final available =
                                        '${Formatters.quantity(Exact.quantity(line.stockMilli), locale)} ${line.unitLabel(locale)}';
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(SnackBar(content: Text(l10n.notEnoughStock(available))));
                                  }
                                },
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: l10n.remove,
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => controller.remove(line.variantId),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 4),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        _TotalRow(label: l10n.subtotal, value: money(cart.subtotalPaisa)),
                        _TotalRow(
                          label: l10n.discount,
                          value: cart.discountPaisa == 0 ? l10n.add : '− ${money(cart.discountPaisa)}',
                          onTap: () async {
                            final paisa = await _askAmount(context, l10n.discount, cart.discountPaisa);
                            if (paisa == null || !context.mounted) return;
                            if (!controller.setDiscount(paisa)) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.errDiscountTooLarge)));
                            }
                          },
                        ),
                        _TotalRow(
                          label: l10n.additionalCharge,
                          value: cart.chargePaisa == 0 ? l10n.add : money(cart.chargePaisa),
                          onTap: () async {
                            final paisa = await _askAmount(context, l10n.additionalCharge, cart.chargePaisa);
                            if (paisa != null) controller.setCharge(paisa);
                          },
                        ),
                        const Divider(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(child: Text(l10n.grandTotal, style: text.titleLarge)),
                              Text(money(cart.grandTotalPaisa), style: text.headlineSmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      // Always in reach, however long the cart is.
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: PrimaryButton(
                  label: '${l10n.checkout} · ${money(cart.grandTotalPaisa)}',
                  onPressed: () => context.push('/pos/checkout'),
                ),
              ),
            ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(child: Text(label, style: text.bodyLarge)),
            Text(
              value,
              style: text.bodyLarge?.copyWith(
                color: onTap == null ? null : AppColors.brandDark,
                fontWeight: onTap == null ? null : FontWeight.w600,
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
