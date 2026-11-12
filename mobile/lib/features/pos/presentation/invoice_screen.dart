import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/external.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/message_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../catalog/application/catalog_providers.dart';
import '../data/sale_models.dart';
import '../data/sales_repository.dart';
import 'labels.dart';

/// A sale shown as its invoice: what was sold, how it was paid, the QR code
/// that opens the customer's copy, and sharing.
class InvoiceScreen extends ConsumerWidget {
  const InvoiceScreen({super.key, required this.saleId, this.justCompleted = false});

  final int saleId;
  final bool justCompleted;

  Future<void> _void(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final reason = await showTextInputDialog(
      context,
      title: l10n.voidSale,
      label: l10n.voidReason,
      confirmLabel: l10n.voidSale,
      maxLength: 255,
    );
    if (reason == null) return;

    try {
      await ref.read(salesRepositoryProvider).voidSale(saleId, reason);
      ref
        ..invalidate(saleProvider(saleId))
        ..invalidate(dashboardProvider)
        ..invalidate(stockSummaryProvider);
      messenger.showSnackBar(SnackBar(content: Text(l10n.saleVoided)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error, l10n))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final sale = ref.watch(saleProvider(saleId));
    final session = ref.watch(sessionProvider);
    final canVoid = (session?.can('sales.void') ?? false) && sale.hasValue && !sale.value!.voided;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.invoice),
        actions: [
          if (canVoid)
            PopupMenuButton<String>(
              onSelected: (_) => _void(context, ref),
              itemBuilder: (context) => [PopupMenuItem(value: 'void', child: Text(l10n.voidSale))],
            ),
        ],
      ),
      body: sale.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: describeError(error, l10n),
          action: OutlinedButton(onPressed: () => ref.invalidate(saleProvider(saleId)), child: Text(l10n.retry)),
        ),
        data: (sale) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (justCompleted && !sale.voided) ...[
              MessageBanner(message: l10n.saleCompleted, tone: BannerTone.info),
              const SizedBox(height: 12),
            ],
            if (sale.voided) ...[
              MessageBanner(title: l10n.cancelled, message: sale.voidReason ?? ''),
              const SizedBox(height: 12),
            ],
            _Receipt(sale: sale, shopName: session?.shop.name ?? '', locale: locale),
            const SizedBox(height: 16),
            if (sale.invoiceUrl != null) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => ref.read(shareTextProvider)(
                        l10n.shareInvoiceText(
                          session?.shop.name ?? '',
                          sale.invoiceNo,
                          Formatters.money(sale.grandTotal, locale),
                          sale.invoiceUrl!,
                        ),
                      ),
                      icon: const Icon(Icons.share_outlined),
                      label: Text(l10n.share),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => ref.read(openUrlProvider)(Uri.parse('${sale.invoiceUrl}/pdf')),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(l10n.downloadPdf),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (justCompleted)
              PrimaryButton(
                label: l10n.newSale,
                icon: Icons.add,
                onPressed: () {
                  context.go('/home');
                  unawaited(context.push('/pos'));
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Receipt extends StatelessWidget {
  const _Receipt({required this.sale, required this.shopName, required this.locale});

  final Sale sale;
  final String shopName;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textMuted);
    String money(String amount) => Formatters.money(amount, locale);
    bool positive(String amount) => (double.tryParse(amount) ?? 0) > 0;

    final salePayments = sale.payments.where((p) => p.type == 'sale').toList();
    final hasManualMobileMoney =
        salePayments.any((p) => p.method == PaymentMethod.bkash || p.method == PaymentMethod.nagad);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(shopName, style: text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(l10n.invoiceNo(sale.invoiceNo), style: text.titleMedium, textAlign: TextAlign.center),
            Text(
              DateFormat.yMMMd(locale).add_jm().format(sale.soldAt.toLocal()),
              style: muted,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              sale.customer == null ? l10n.walkInCustomer : '${sale.customer!.name} · ${sale.customer!.phone}',
              style: muted,
              textAlign: TextAlign.center,
            ),
            const Divider(height: 28),
            for (final item in sale.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title, style: text.bodyLarge),
                          Text('${Formatters.quantity(item.quantity, locale)} × ${money(item.unitPrice)}', style: muted),
                        ],
                      ),
                    ),
                    Text(money(item.lineTotal), style: text.bodyLarge),
                  ],
                ),
              ),
            const Divider(height: 28),
            _Line(label: l10n.subtotal, value: money(sale.subtotal)),
            if (positive(sale.discountAmount)) _Line(label: l10n.discount, value: '− ${money(sale.discountAmount)}'),
            if (positive(sale.additionalCharge)) _Line(label: l10n.additionalCharge, value: money(sale.additionalCharge)),
            const SizedBox(height: 6),
            _Line(label: l10n.grandTotal, value: money(sale.grandTotal), style: text.titleLarge),
            const SizedBox(height: 6),
            for (final payment in salePayments)
              _Line(
                label: '${l10n.paid} · ${paymentMethodLabel(payment.method, l10n)}',
                value: money(payment.amount),
                color: AppColors.brandDark,
              ),
            if (positive(sale.changeAmount)) _Line(label: l10n.change, value: money(sale.changeAmount), color: AppColors.textMuted),
            if (positive(sale.dueAmount))
              _Line(label: l10n.due, value: money(sale.dueAmount), color: AppColors.danger, style: text.titleMedium),
            if (hasManualMobileMoney) ...[
              const SizedBox(height: 8),
              // The app did not talk to bKash or Nagad; say so rather than imply the money arrived.
              Text(l10n.unverifiedNote, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
            ],
            if (sale.invoiceUrl != null && !sale.voided) ...[
              const Divider(height: 28),
              Center(
                child: Semantics(
                  label: l10n.scanToView,
                  image: true,
                  child: QrImageView(data: sale.invoiceUrl!, size: 150, backgroundColor: Colors.white),
                ),
              ),
              const SizedBox(height: 4),
              Text(l10n.scanToView, style: muted, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.style, this.color});

  final String label;
  final String value;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effective = (style ?? Theme.of(context).textTheme.bodyLarge)?.copyWith(color: color);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: effective)),
          Text(value, style: effective),
        ],
      ),
    );
  }
}
