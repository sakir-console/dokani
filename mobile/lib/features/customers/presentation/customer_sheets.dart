import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../../pos/application/sale_submitter.dart';
import '../../pos/data/sale_models.dart';
import '../../pos/presentation/labels.dart';
import '../data/customer_repository.dart';

/// Add or edit a customer. Completes with the saved customer.
Future<Customer?> showCustomerForm(BuildContext context, {Customer? customer}) => showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CustomerForm(customer: customer),
    );

class _CustomerForm extends ConsumerStatefulWidget {
  const _CustomerForm({this.customer});

  final Customer? customer;

  @override
  ConsumerState<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<_CustomerForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.customer?.name);
  late final _phone = TextEditingController(text: widget.customer?.phone);
  late final _address = TextEditingController(text: widget.customer?.address);
  final _openingDue = TextEditingController();
  bool _busy = false;
  String? _error;
  ApiException? _serverErrors;

  @override
  void dispose() {
    for (final controller in [_name, _phone, _address, _openingDue]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _serverErrors = null;
    });
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final address = _address.text.trim();
    final draft = CustomerDraft(
      name: _name.text.trim(),
      phone: Phone.normalize(_phone.text)!,
      address: address.isEmpty ? null : address,
      openingDue: Formatters.parseDecimal(_openingDue.text, maxDecimals: 2),
    );

    setState(() => _busy = true);
    try {
      final repository = ref.read(customerRepositoryProvider);
      final saved = widget.customer == null
          ? await repository.create(draft)
          : await repository.update(widget.customer!.id, draft);
      navigator.pop(saved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _serverErrors = error is ApiException ? error : null;
        _error = describeError(error, l10n);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final editing = widget.customer != null;

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
                Text(editing ? l10n.editCustomer : l10n.addCustomer, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                if (_error != null) ...[MessageBanner(message: _error!), const SizedBox(height: 16)],
                AppTextField(
                  label: l10n.name,
                  controller: _name,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.words,
                  validator: (value) => (value == null || value.trim().isEmpty) ? l10n.errRequired : null,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: l10n.phone,
                  hint: l10n.phoneHint,
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  serverError: _serverErrors?.fieldError('phone'),
                  validator: (value) => Phone.isValid(value) ? null : l10n.errPhone,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: l10n.addressOptional,
                  controller: _address,
                  maxLength: 255,
                  textCapitalization: TextCapitalization.sentences,
                ),
                // What they already owed before the shop started using the app. Set once, at creation.
                if (!editing) ...[
                  const SizedBox(height: 16),
                  AppTextField(
                    label: l10n.openingDue,
                    controller: _openingDue,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? null
                        : (Formatters.parseDecimal(value, maxDecimals: 2) == null ? l10n.errNumber : null),
                  ),
                ],
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

/// The customer after a payment, and whether the payment is still waiting to reach the server.
typedef CollectedDue = ({Customer customer, bool pending});

/// Record a payment against a customer's due. Completes with the customer's new state.
Future<CollectedDue?> showCollectDueSheet(BuildContext context, {required Customer customer}) =>
    showModalBottomSheet<CollectedDue>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CollectDueSheet(customer: customer),
    );

class _CollectDueSheet extends ConsumerStatefulWidget {
  const _CollectDueSheet({required this.customer});

  final Customer customer;

  @override
  ConsumerState<_CollectDueSheet> createState() => _CollectDueSheetState();
}

class _CollectDueSheetState extends ConsumerState<_CollectDueSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _transactionId = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;

  /// One id for this collection: tapping Save twice, or retrying, records it once.
  final String _clientUuid = Exact.uuid();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _transactionId.dispose();
    super.dispose();
  }

  String? _validateAmount(String? value, AppLocalizations l10n) {
    final parsed = Formatters.parseDecimal(value, maxDecimals: 2);
    if (parsed == null || Exact.paisa(parsed) <= 0) return l10n.errNumber;
    if (Exact.paisa(parsed) > Exact.paisa(widget.customer.currentDue)) return l10n.errAmountExceedsDue;
    return null;
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final transactionId = _transactionId.text.trim();

    setState(() => _busy = true);
    try {
      final updated = await ref.read(saleSubmitterProvider).collectDue(
            customer: widget.customer,
            clientUuid: _clientUuid,
            amount: Formatters.parseDecimal(_amount.text, maxDecimals: 2)!,
            method: _method,
            transactionId: _method == PaymentMethod.cash || transactionId.isEmpty ? null : transactionId,
          );
      navigator.pop(updated);
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
    final locale = Localizations.localeOf(context).languageCode;
    final customer = widget.customer;

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
                Text(l10n.collectDue, style: text.titleLarge),
                Text(
                  '${customer.name} · ${l10n.outstandingDue}: ${Formatters.money(customer.currentDue, locale)}',
                  style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[MessageBanner(message: _error!), const SizedBox(height: 16)],
                AppTextField(
                  label: l10n.collectAmount,
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) => _validateAmount(value, l10n),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => setState(() => _amount.text = Formatters.editable(customer.currentDue)),
                    child: Text(l10n.collectFull),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(l10n.paymentMethod, style: text.titleSmall),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final method in PaymentMethod.values)
                      ChoiceChip(
                        label: Text(paymentMethodLabel(method, l10n)),
                        selected: _method == method,
                        onSelected: (_) => setState(() => _method = method),
                      ),
                  ],
                ),
                if (_method != PaymentMethod.cash) ...[
                  const SizedBox(height: 12),
                  AppTextField(
                    label: '${l10n.transactionId} (${l10n.optional})',
                    controller: _transactionId,
                    maxLength: 100,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.done,
                  ),
                ],
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
