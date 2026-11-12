import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/external.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/message_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../pos/presentation/labels.dart';
import '../data/report_models.dart';
import '../data/report_repository.dart';

/// Business reports for a chosen period: sales and profit, money received by
/// method, best sellers, and links to dues, low stock and sales history.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportRange _range = const ReportRange(ReportRangeKey.today);
  bool _byRevenue = false;

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _range.key == ReportRangeKey.custom && _range.from != null
          ? DateTimeRange(start: _range.from!, end: _range.to!)
          : DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
    );
    if (picked != null) {
      setState(() => _range = ReportRange(ReportRangeKey.custom, from: picked.start, to: picked.end));
    }
  }

  void _reload() => ref
    ..invalidate(reportSummaryProvider)
    ..invalidate(paymentMethodsReportProvider)
    ..invalidate(bestSellersProvider);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);

    if (!(session?.hasModule('reports') ?? false) || !(session?.can('reports.view') ?? false)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.reports)),
        body: EmptyState(icon: Icons.lock_outline, title: l10n.reportsNotInPlan),
      );
    }

    final canExport = session!.hasModule('exports');
    final summary = ref.watch(reportSummaryProvider(_range));

    final ranges = [
      (ReportRangeKey.today, l10n.rangeToday),
      (ReportRangeKey.yesterday, l10n.rangeYesterday),
      (ReportRangeKey.last7Days, l10n.rangeLast7Days),
      (ReportRangeKey.thisWeek, l10n.rangeThisWeek),
      (ReportRangeKey.thisMonth, l10n.rangeThisMonth),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reports),
        actions: [
          if (canExport)
            IconButton(
              tooltip: l10n.export,
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (context) => _ExportSheet(range: _range),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // All periods visible at once; they wrap onto a second line on a narrow phone.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 8,
                children: [
                  for (final (key, label) in ranges)
                    ChoiceChip(
                      label: Text(label),
                      selected: _range.key == key,
                      onSelected: (_) => setState(() => _range = ReportRange(key)),
                    ),
                  ChoiceChip(
                    avatar: const Icon(Icons.date_range, size: 18),
                    label: Text(l10n.rangeCustom),
                    selected: _range.key == ReportRangeKey.custom,
                    onSelected: (_) => _pickCustomRange(),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: summary.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(
                icon: Icons.cloud_off_outlined,
                title: describeError(error, l10n),
                action: OutlinedButton(onPressed: _reload, child: Text(l10n.retry)),
              ),
              data: (summary) => RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    if (summary.periodLabel.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          summary.periodLabel,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                        ),
                      ),
                    _SummaryCard(summary: summary),
                    const SizedBox(height: 12),
                    _PaymentMethodsCard(range: _range),
                    const SizedBox(height: 12),
                    _BestSellersCard(
                      range: _range,
                      byRevenue: _byRevenue,
                      onChanged: (value) => setState(() => _byRevenue = value),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final (icon, label, path) in [
                            (Icons.payments_outlined, l10n.duesReport, '/customers?due=1'),
                            (Icons.inventory_outlined, l10n.lowStockReport, '/products?stock=low'),
                            (Icons.receipt_long_outlined, l10n.salesHistory, '/sales'),
                          ]) ...[
                            ListTile(
                              leading: Icon(icon),
                              title: Text(label),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push(path),
                            ),
                            if (path != '/sales') const Divider(),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    String money(String amount) => Formatters.money(amount, locale);

    final rows = <(String, String)>[
      (l10n.totalOrders, NumberFormat.decimalPattern(locale).format(summary.orders)),
      (l10n.totalItemsSold, Formatters.quantity(summary.itemsSold, locale)),
      (l10n.totalPaidLabel, money(summary.totalPaid)),
      (l10n.totalDueLabel, money(summary.totalDue)),
      (l10n.totalDiscounts, money(summary.totalDiscounts)),
      (l10n.additionalCharges, money(summary.additionalCharges)),
      (l10n.costOfGoods, money(summary.costOfGoods)),
      (l10n.dueCollectedLabel, money(summary.dueCollected)),
      if (summary.cancelledOrders > 0)
        (l10n.cancelledSales, l10n.cancelledSalesValue(summary.cancelledOrders, money(summary.cancelledAmount))),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.totalSales, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                      Text(money(summary.totalSales), style: text.headlineMedium),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(l10n.grossProfit, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                    Text(money(summary.grossProfit), style: text.titleLarge?.copyWith(color: AppColors.brandDark)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Sales and profit are often confused; say what profit means here.
            Text(l10n.profitExplained, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
            const Divider(height: 28),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(label, style: text.bodyLarge?.copyWith(color: AppColors.textMuted))),
                    Text(value, style: text.titleMedium),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodsCard extends ConsumerWidget {
  const _PaymentMethodsCard({required this.range});

  final ReportRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final report = ref.watch(paymentMethodsReportProvider(range));
    String money(String amount) => Formatters.money(amount, locale);
    bool positive(String amount) => (double.tryParse(amount) ?? 0) > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.byPaymentMethod, style: text.titleMedium),
            const SizedBox(height: 8),
            ...report.when(
              loading: () => [const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))],
              error: (error, _) => [MessageBanner(message: describeError(error, l10n))],
              data: (report) => [
                if (report.methods.isEmpty)
                  Text(l10n.noPaymentsInPeriod, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                for (final row in report.methods)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(paymentMethodLabel(row.method, l10n), style: text.bodyLarge),
                              if (positive(row.dueCollections))
                                Text(
                                  l10n.includesDueCollected(money(row.dueCollections)),
                                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                                ),
                              if (positive(row.refunds))
                                Text(l10n.refunded(money(row.refunds)), style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        Text(money(row.net), style: text.titleMedium),
                      ],
                    ),
                  ),
                if (report.methods.isNotEmpty) ...[
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(child: Text(l10n.netReceived, style: text.titleMedium)),
                      Text(money(report.netTotal), style: text.titleLarge),
                    ],
                  ),
                ],
                if (positive(report.soldOnDue)) ...[
                  const SizedBox(height: 6),
                  // Due is not a payment: shown apart from the money actually received.
                  Row(
                    children: [
                      Expanded(child: Text(l10n.soldOnDue, style: text.bodyLarge?.copyWith(color: AppColors.danger))),
                      Text(money(report.soldOnDue), style: text.titleMedium?.copyWith(color: AppColors.danger)),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BestSellersCard extends ConsumerWidget {
  const _BestSellersCard({required this.range, required this.byRevenue, required this.onChanged});

  final ReportRange range;
  final bool byRevenue;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final items = ref.watch(bestSellersProvider((range: range, byRevenue: byRevenue)));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.bestSellers, style: text.titleMedium),
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(value: false, label: Text(l10n.byQuantity)),
                ButtonSegment(value: true, label: Text(l10n.byRevenue)),
              ],
              selected: {byRevenue},
              onSelectionChanged: (selection) => onChanged(selection.first),
            ),
            const SizedBox(height: 8),
            ...items.when(
              loading: () => [const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))],
              error: (error, _) => [MessageBanner(message: describeError(error, l10n))],
              data: (items) => [
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(l10n.noSalesInPeriod, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                  ),
                for (final (index, item) in items.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            NumberFormat.decimalPattern(locale).format(index + 1),
                            style: text.titleMedium?.copyWith(color: AppColors.textMuted),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.title, style: text.bodyLarge),
                              Text(
                                '${Formatters.quantity(item.quantity, locale)} ${item.unitName} · ${l10n.profitValue(Formatters.money(item.profit, locale))}',
                                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                        Text(Formatters.money(item.revenue, locale), style: text.titleMedium),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Choose a report and a file type, download it, and hand it to the share sheet.
class _ExportSheet extends ConsumerStatefulWidget {
  const _ExportSheet({required this.range});

  final ReportRange range;

  @override
  ConsumerState<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<_ExportSheet> {
  ExportReport _report = ExportReport.summary;
  ExportFormat _format = ExportFormat.xlsx;
  bool _busy = false;
  String? _error;

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await ref.read(reportRepositoryProvider).export(_report, _format, widget.range);
      await ref.read(shareFileProvider)(file.path, file.name);
      navigator.pop();
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error, l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    final reports = [
      (ExportReport.summary, l10n.exportSummary),
      (ExportReport.sales, l10n.exportSales),
      (ExportReport.paymentMethods, l10n.exportPaymentMethods),
      (ExportReport.bestSellers, l10n.exportBestSellers),
      (ExportReport.dues, l10n.exportDues),
      (ExportReport.lowStock, l10n.exportLowStock),
    ];
    final formats = [
      (ExportFormat.xlsx, l10n.formatExcel),
      (ExportFormat.pdf, l10n.formatPdf),
      (ExportFormat.csv, l10n.formatCsv),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.export, style: text.titleLarge),
              const SizedBox(height: 12),
              if (_error != null) ...[MessageBanner(message: _error!), const SizedBox(height: 12)],
              Text(l10n.exportWhat, style: text.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final (report, label) in reports)
                    ChoiceChip(
                      label: Text(label),
                      selected: _report == report,
                      onSelected: _busy ? null : (_) => setState(() => _report = report),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(l10n.exportFormat, style: text.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final (format, label) in formats)
                    ChoiceChip(
                      label: Text(label),
                      selected: _format == format,
                      onSelected: _busy ? null : (_) => setState(() => _format = format),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              PrimaryButton(label: l10n.export, icon: Icons.file_download_outlined, busy: _busy, onPressed: _export),
            ],
          ),
        ),
      ),
    );
  }
}
