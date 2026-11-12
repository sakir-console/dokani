import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../data/sale_models.dart';
import '../data/sales_repository.dart';

/// One row of a sales list: invoice number, who, when, how much, what is due.
class SaleTile extends StatelessWidget {
  const SaleTile({super.key, required this.sale, required this.onTap});

  final Sale sale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final hasDue = (double.tryParse(sale.dueAmount) ?? 0) > 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        title: Text(sale.invoiceNo, style: text.titleMedium),
        subtitle: Text(
          '${sale.customer?.name ?? l10n.walkInCustomer} · ${DateFormat.MMMd(locale).add_jm().format(sale.soldAt.toLocal())}',
          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              Formatters.money(sale.grandTotal, locale),
              style: text.titleMedium?.copyWith(decoration: sale.voided ? TextDecoration.lineThrough : null),
            ),
            if (sale.voided)
              Text(l10n.cancelled, style: text.bodySmall?.copyWith(color: AppColors.danger))
            else if (hasDue)
              Text(
                '${l10n.due} ${Formatters.money(sale.dueAmount, locale)}',
                style: text.bodySmall?.copyWith(color: AppColors.danger),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sales history, newest first, loaded a page at a time.
class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  final List<Sale> _sales = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadMore);
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref.read(salesRepositoryProvider).sales(page: _page + 1);
      if (!mounted) return;
      setState(() {
        _sales.addAll(result.items);
        _page = result.currentPage;
        _hasMore = result.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _sales.clear();
      _page = 0;
      _hasMore = true;
    });
    await _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget body;
    if (_sales.isEmpty && _loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_sales.isEmpty && _error != null) {
      body = EmptyState(
        icon: Icons.cloud_off_outlined,
        title: describeError(_error!, l10n),
        action: OutlinedButton(onPressed: _loadMore, child: Text(l10n.retry)),
      );
    } else if (_sales.isEmpty) {
      body = EmptyState(icon: Icons.receipt_long_outlined, title: l10n.noSalesTitle, body: l10n.noSalesBody);
    } else {
      body = RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: _sales.length + (_hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == _sales.length) {
              return _loading
                  ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                  : OutlinedButton(onPressed: _loadMore, child: Text(_error == null ? l10n.loadMore : l10n.retry));
            }
            final sale = _sales[index];
            return SaleTile(
              sale: sale,
              onTap: () async {
                await context.push('/sales/${sale.id}');
                // A sale may have been cancelled while its invoice was open.
                if (mounted) await _refresh();
              },
            );
          },
        ),
      );
    }

    return Scaffold(appBar: AppBar(title: Text(l10n.salesHistory)), body: body);
  }
}
