import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/message_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../data/vendor_repository.dart';

class VendorsScreen extends ConsumerStatefulWidget {
  const VendorsScreen({super.key});

  @override
  ConsumerState<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends ConsumerState<VendorsScreen> {
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _openForm([Vendor? vendor]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _VendorForm(vendor: vendor),
    );
    if (saved ?? false) ref.invalidate(vendorsProvider);
  }

  Future<void> _delete(Vendor vendor) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showConfirmDialog(
      context,
      message: l10n.deleteVendorConfirm(vendor.name),
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (!confirmed) return;

    try {
      await ref.read(vendorRepositoryProvider).delete(vendor.id);
      ref.invalidate(vendorsProvider);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error, l10n))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    final canManage = session?.can('vendors.manage') ?? false;

    if (!(session?.hasModule('vendors') ?? false)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.vendors)),
        body: EmptyState(icon: Icons.lock_outline, title: l10n.vendorsNotInPlan),
      );
    }

    final vendors = ref.watch(vendorsProvider(_query));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.vendors)),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(onPressed: _openForm, icon: const Icon(Icons.add), label: Text(l10n.addVendor))
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(hintText: l10n.searchVendors, prefixIcon: const Icon(Icons.search)),
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _query = value.trim()));
              },
            ),
          ),
          Expanded(
            child: vendors.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(
                icon: Icons.cloud_off_outlined,
                title: describeError(error, l10n),
                action: OutlinedButton(onPressed: () => ref.invalidate(vendorsProvider), child: Text(l10n.retry)),
              ),
              data: (items) => items.isEmpty
                  ? (_query.isEmpty
                      ? EmptyState(icon: Icons.local_shipping_outlined, title: l10n.noVendorsTitle, body: l10n.noVendorsBody)
                      : EmptyState(icon: Icons.search_off, title: l10n.noResultsTitle))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final vendor = items[index];
                        final details = [
                          ?vendor.companyName,
                          ?vendor.phone,
                          if (vendor.productsCount != null) l10n.productsCount(vendor.productsCount!),
                        ].join(' · ');

                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            title: Text(vendor.name, style: text.titleMedium),
                            subtitle: details.isEmpty
                                ? null
                                : Text(details, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                            onTap: canManage ? () => _openForm(vendor) : null,
                            trailing: canManage
                                ? IconButton(
                                    tooltip: l10n.delete,
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _delete(vendor),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VendorForm extends ConsumerStatefulWidget {
  const _VendorForm({this.vendor});

  final Vendor? vendor;

  @override
  ConsumerState<_VendorForm> createState() => _VendorFormState();
}

class _VendorFormState extends ConsumerState<_VendorForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.vendor?.name);
  late final _phone = TextEditingController(text: widget.vendor?.phone);
  late final _company = TextEditingController(text: widget.vendor?.companyName);
  late final _address = TextEditingController(text: widget.vendor?.address);
  late final _notes = TextEditingController(text: widget.vendor?.notes);
  bool _busy = false;
  String? _error;
  ApiException? _serverErrors;

  @override
  void dispose() {
    for (final controller in [_name, _phone, _company, _address, _notes]) {
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
    String? clean(TextEditingController controller) {
      final value = controller.text.trim();
      return value.isEmpty ? null : value;
    }

    final draft = VendorDraft(
      name: _name.text.trim(),
      phone: Phone.normalize(_phone.text),
      companyName: clean(_company),
      address: clean(_address),
      notes: clean(_notes),
    );

    setState(() => _busy = true);
    try {
      final repository = ref.read(vendorRepositoryProvider);
      widget.vendor == null ? await repository.create(draft) : await repository.update(widget.vendor!.id, draft);
      navigator.pop(true);
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
                Text(
                  widget.vendor == null ? l10n.addVendor : l10n.editVendor,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[MessageBanner(message: _error!), const SizedBox(height: 16)],
                AppTextField(
                  label: l10n.vendorName,
                  controller: _name,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.words,
                  serverError: _serverErrors?.fieldError('name'),
                  validator: (value) => (value == null || value.trim().isEmpty) ? l10n.errRequired : null,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: l10n.phoneOptional,
                  hint: l10n.phoneHint,
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  serverError: _serverErrors?.fieldError('phone'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty || Phone.isValid(value)) ? null : l10n.errPhone,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: '${l10n.companyName} (${l10n.optional})',
                  controller: _company,
                  maxLength: 150,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: l10n.addressOptional,
                  controller: _address,
                  maxLength: 255,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: '${l10n.notes} (${l10n.optional})',
                  controller: _notes,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
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
