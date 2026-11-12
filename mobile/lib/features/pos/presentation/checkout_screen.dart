import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/money/exact.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/message_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../customers/data/customer_repository.dart';
import '../application/cart_controller.dart';
import '../application/payment_plan.dart';
import '../data/sale_models.dart';
import '../data/sales_repository.dart';
import 'labels.dart';

/// One non-cash payment being typed in.
class _OtherPaymentFields {
  PaymentMethod method = PaymentMethod.bkash;
  final amount = TextEditingController();
  final transactionId = TextEditingController();

  void dispose() {
    amount.dispose();
    transactionId.dispose();
  }
}

enum _Lookup { idle, searching, found, notFound }

/// Take payment and complete the sale.
///
/// Cash starts filled in with the full total, so an ordinary cash sale is one
/// tap. Lower the cash, or add bKash/Nagad, and the screen shows the change
/// or the amount left due. A due needs the customer's mobile number.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _cash;
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final List<_OtherPaymentFields> _others = [];

  /// Fixed for this checkout. A retry after a dropped connection re-sends the
  /// same id, so the server records the sale once.
  final String _clientUuid = Exact.uuid();

  _Lookup _lookup = _Lookup.idle;
  Customer? _customer;
  Timer? _lookupDebounce;
  bool _showCustomer = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final total = ref.read(cartProvider).grandTotalPaisa;
    _cash = TextEditingController(text: Formatters.editable(Exact.money(total)));
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _cash.dispose();
    _phone.dispose();
    _name.dispose();
    for (final other in _others) {
      other.dispose();
    }
    super.dispose();
  }

  int _paisa(String text) {
    final parsed = Formatters.parseDecimal(text, maxDecimals: 2);
    return parsed == null ? 0 : Exact.paisa(parsed);
  }

  PaymentPlan _plan(int totalPaisa) => PaymentPlan(
        totalPaisa: totalPaisa,
        cashReceivedPaisa: _paisa(_cash.text),
        others: [
          for (final other in _others)
            if (_paisa(other.amount.text) > 0)
              OtherPayment(
                method: other.method,
                amountPaisa: _paisa(other.amount.text),
                transactionId: other.transactionId.text.trim().isEmpty ? null : other.transactionId.text.trim(),
              ),
        ],
      );

  void _onPhoneChanged(String value) {
    _lookupDebounce?.cancel();
    final phone = Phone.normalize(value);

    if (phone == null) {
      setState(() {
        _lookup = _Lookup.idle;
        _customer = null;
      });
      return;
    }

    setState(() => _lookup = _Lookup.searching);
    _lookupDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final customer = await ref.read(customerRepositoryProvider).lookup(phone);
        if (!mounted || Phone.normalize(_phone.text) != phone) return;
        setState(() {
          _customer = customer;
          _lookup = customer == null ? _Lookup.notFound : _Lookup.found;
        });
      } catch (_) {
        // Offline or failed: carry on. The server finds or creates the customer when the sale is saved.
        if (mounted) setState(() => _lookup = _Lookup.notFound);
      }
    });
  }

  Future<void> _complete(CartState cart) async {
    final l10n = AppLocalizations.of(context);
    final router = GoRouter.of(context);
    final plan = _plan(cart.grandTotalPaisa);

    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (!plan.isValid) {
      setState(() => _error = l10n.paymentsExceedTotal);
      return;
    }

    final phone = Phone.normalize(_phone.text);
    final name = _name.text.trim();

    final draft = SaleDraft(
      clientUuid: _clientUuid,
      items: [
        for (final line in cart.lines)
          SaleLineDraft(
            variantId: line.variantId,
            quantity: Exact.quantity(line.quantityMilli),
            unitPrice: Exact.money(line.unitPricePaisa),
          ),
      ],
      discountAmount: Exact.money(cart.discountPaisa),
      additionalCharge: Exact.money(cart.chargePaisa),
      grandTotal: Exact.money(plan.totalPaisa),
      payments: [
        if (plan.cashAppliedPaisa > 0)
          PaymentDraft(
            method: PaymentMethod.cash,
            amount: Exact.money(plan.cashAppliedPaisa),
            receivedAmount: Exact.money(plan.cashReceivedPaisa),
          ),
        for (final other in plan.others)
          PaymentDraft(
            method: other.method,
            amount: Exact.money(other.amountPaisa),
            transactionId: other.transactionId,
          ),
      ],
      dueAmount: Exact.money(plan.duePaisa),
      customerPhone: phone,
      customerName: name.isEmpty ? null : name,
    );

    setState(() => _busy = true);
    try {
      final sale = await ref.read(salesRepositoryProvider).createSale(draft);

      ref.read(cartProvider.notifier).clear();
      ref
        ..invalidate(dashboardProvider)
        ..invalidate(stockSummaryProvider);

      // Leave the counter screens behind: Back from the invoice goes home.
      router.go('/home');
      unawaited(router.push('/sales/${sale.id}?new=1'));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = describeError(error, l10n);
        // The server knows this number is new: ask for the name.
        if (error is ApiException && error.code == 'CUSTOMER_NAME_REQUIRED') _lookup = _Lookup.notFound;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final cart = ref.watch(cartProvider);
    final plan = _plan(cart.grandTotalPaisa);

    String money(int paisa) => Formatters.money(Exact.money(paisa), locale);
    String? optionalMoney(String? value) => (value == null || value.trim().isEmpty)
        ? null
        : (Formatters.parseDecimal(value, maxDecimals: 2) == null ? l10n.errNumber : null);

    final needsCustomer = plan.hasDue;
    final customerVisible = needsCustomer || _showCustomer;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.checkout)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(child: Text(l10n.grandTotal, style: text.titleLarge)),
                        Text(money(plan.totalPaisa), style: text.headlineMedium),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[MessageBanner(message: _error!), const SizedBox(height: 16)],

                AppTextField(
                  label: l10n.cashReceived,
                  controller: _cash,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: optionalMoney,
                  onChanged: (_) => setState(() {}),
                ),

                for (var i = 0; i < _others.length; i++) ...[
                  const SizedBox(height: 12),
                  _otherPaymentCard(i, l10n, optionalMoney),
                ],

                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _others.length >= 5 ? null : () => setState(() => _others.add(_OtherPaymentFields())),
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(l10n.addPayment),
                  ),
                ),

                // The outcome, in plain numbers.
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Column(
                      children: [
                        _SummaryRow(label: l10n.paid, value: money(plan.paidPaisa)),
                        if (plan.changePaisa > 0)
                          _SummaryRow(label: l10n.change, value: money(plan.changePaisa), color: AppColors.brandDark, bold: true),
                        if (plan.hasDue)
                          _SummaryRow(label: l10n.due, value: money(plan.duePaisa), color: AppColors.danger, bold: true),
                      ],
                    ),
                  ),
                ),

                if (plan.othersExceedTotal) ...[
                  const SizedBox(height: 12),
                  MessageBanner(message: l10n.paymentsExceedTotal),
                ],

                const SizedBox(height: 12),
                if (customerVisible) ...[
                  if (needsCustomer) ...[
                    MessageBanner(message: l10n.dueNeedsCustomer(money(plan.duePaisa)), tone: BannerTone.warning),
                    const SizedBox(height: 12),
                  ],
                  AppTextField(
                    label: l10n.customerPhone,
                    hint: l10n.phoneHint,
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    onChanged: _onPhoneChanged,
                    validator: (value) {
                      final empty = value == null || value.trim().isEmpty;
                      // Mandatory with a due; optional otherwise, but never malformed.
                      if (empty) return needsCustomer ? l10n.errRequired : null;
                      return Phone.isValid(value) ? null : l10n.errPhone;
                    },
                  ),
                  const SizedBox(height: 8),
                  _lookupStatus(l10n, locale, text),
                  if (_lookup == _Lookup.notFound) ...[
                    const SizedBox(height: 12),
                    AppTextField(
                      label: l10n.customerName,
                      controller: _name,
                      maxLength: 120,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      validator: (value) => (value == null || value.trim().isEmpty) ? l10n.errRequired : null,
                    ),
                  ],
                ] else
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _showCustomer = true),
                      icon: const Icon(Icons.person_add_alt_outlined, size: 20),
                      label: Text(l10n.addCustomerOptional),
                    ),
                  ),

                const SizedBox(height: 24),
                PrimaryButton(
                  label: l10n.completeSale,
                  busy: _busy,
                  onPressed: cart.isEmpty ? null : () => _complete(cart),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _lookupStatus(AppLocalizations l10n, String locale, TextTheme text) {
    switch (_lookup) {
      case _Lookup.idle:
        return const SizedBox.shrink();
      case _Lookup.searching:
        return const Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      case _Lookup.found:
        final customer = _customer!;
        return Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.brand, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                customer.dueValue > 0
                    ? l10n.customerFound(customer.name, Formatters.money(customer.currentDue, locale))
                    : l10n.customerFoundNoDue(customer.name),
                style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      case _Lookup.notFound:
        return Text(l10n.customerNew, style: text.bodyMedium?.copyWith(color: AppColors.textMuted));
    }
  }

  Widget _otherPaymentCard(int index, AppLocalizations l10n, String? Function(String?) optionalMoney) {
    final other = _others[index];
    const methods = [PaymentMethod.bkash, PaymentMethod.nagad, PaymentMethod.bank, PaymentMethod.card, PaymentMethod.other];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButton<PaymentMethod>(
                    value: other.method,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final method in methods)
                        DropdownMenuItem(value: method, child: Text(paymentMethodLabel(method, l10n))),
                    ],
                    onChanged: (value) => setState(() => other.method = value ?? other.method),
                  ),
                ),
                IconButton(
                  tooltip: l10n.remove,
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _others.removeAt(index).dispose()),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                children: [
                  AppTextField(
                    label: l10n.amount,
                    controller: other.amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? l10n.errRequired : optionalMoney(value),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: '${l10n.transactionId} (${l10n.optional})',
                    controller: other.transactionId,
                    maxLength: 100,
                    keyboardType: TextInputType.visiblePassword,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.color, this.bold = false});

  final String label;
  final String value;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
