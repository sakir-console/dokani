import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/phone.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/message_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../data/shop_repository.dart';
import '../data/shop_types.dart';

class EditShopScreen extends ConsumerStatefulWidget {
  const EditShopScreen({super.key});

  @override
  ConsumerState<EditShopScreen> createState() => _EditShopScreenState();
}

class _EditShopScreenState extends ConsumerState<EditShopScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late String _shopType;

  bool _busy = false;
  String? _error;
  ApiException? _serverErrors;

  @override
  void initState() {
    super.initState();
    final shop = ref.read(sessionProvider)!.shop;
    _name = TextEditingController(text: shop.name);
    _phone = TextEditingController(text: shop.phone);
    _address = TextEditingController(text: shop.address ?? '');
    _shopType = shopTypeValues.contains(shop.shopType) ? shop.shopType : 'general';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _serverErrors = null;
    });
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final address = _address.text.trim();
      final shop = await ref.read(shopRepositoryProvider).update(
            name: _name.text.trim(),
            shopType: _shopType,
            phone: Phone.normalize(_phone.text)!,
            address: address.isEmpty ? null : address,
          );
      await ref.read(authControllerProvider.notifier).updateShop(shop);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.saved)));
      context.pop();
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
    final validators = Validators(l10n);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.editShop)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  MessageBanner(message: _error!),
                  const SizedBox(height: 16),
                ],
                AppTextField(
                  label: l10n.shopName,
                  controller: _name,
                  validator: validators.required,
                  serverError: _serverErrors?.fieldError('name'),
                  textCapitalization: TextCapitalization.words,
                  maxLength: 150,
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(l10n.shopType, style: Theme.of(context).textTheme.titleSmall),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _shopType,
                  isExpanded: true,
                  items: [
                    for (final type in shopTypeValues)
                      DropdownMenuItem(value: type, child: Text(shopTypeLabel(type, l10n))),
                  ],
                  onChanged: (value) => setState(() => _shopType = value ?? _shopType),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: l10n.shopPhone,
                  hint: l10n.phoneHint,
                  controller: _phone,
                  validator: validators.phone,
                  serverError: _serverErrors?.fieldError('phone'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: l10n.addressOptional,
                  controller: _address,
                  serverError: _serverErrors?.fieldError('address'),
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  maxLength: 255,
                ),
                const SizedBox(height: 24),
                PrimaryButton(label: l10n.save, busy: _busy, onPressed: _save),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
