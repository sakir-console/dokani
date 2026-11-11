import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/phone.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/message_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/application/locale_controller.dart';
import '../../shop/data/shop_types.dart';
import '../application/auth_controller.dart';
import '../data/auth_repository.dart';
import 'auth_scaffold.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shopName = TextEditingController();
  final _ownerName = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _address = TextEditingController();

  String? _shopType;
  String? _logoPath;
  bool _busy = false;
  String? _error;
  ApiException? _serverErrors;

  @override
  void dispose() {
    for (final controller in [_shopName, _ownerName, _phone, _password, _address]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      // Downscaled on the phone so the upload is small on a slow connection.
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
      if (picked != null && mounted) setState(() => _logoPath = picked.path);
    } catch (_) {
      // The picker was unavailable or permission was denied. The logo is optional.
    }
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _serverErrors = null;
    });
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).register(
            RegistrationData(
              shopName: _shopName.text.trim(),
              ownerName: _ownerName.text.trim(),
              phone: Phone.normalize(_phone.text)!,
              password: _password.text,
              shopType: _shopType!,
              address: _address.text.trim(),
              locale: ref.read(localeControllerProvider).languageCode,
              logoPath: _logoPath,
            ),
          );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _serverErrors = error is ApiException ? error : null;
        _error = describeError(error, AppLocalizations.of(context));
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final validators = Validators(l10n);

    return AuthScaffold(
      showBack: true,
      title: l10n.registerTitle,
      subtitle: l10n.registerSubtitle,
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
              controller: _shopName,
              validator: validators.required,
              serverError: _serverErrors?.fieldError('shop_name'),
              textCapitalization: TextCapitalization.words,
              maxLength: 150,
            ),
            const SizedBox(height: 16),
            _ShopTypeField(
              label: l10n.shopType,
              value: _shopType,
              errorText: _serverErrors?.fieldError('shop_type'),
              validator: (value) => value == null ? l10n.errRequired : null,
              onChanged: (value) => setState(() => _shopType = value),
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: l10n.ownerName,
              controller: _ownerName,
              validator: validators.required,
              serverError: _serverErrors?.fieldError('owner_name'),
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              maxLength: 120,
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: l10n.phone,
              hint: l10n.phoneHint,
              controller: _phone,
              validator: validators.phone,
              serverError: _serverErrors?.fieldError('phone'),
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
            ),
            const SizedBox(height: 16),
            PasswordField(
              label: l10n.password,
              controller: _password,
              validator: validators.password,
              serverError: _serverErrors?.fieldError('password'),
              textInputAction: TextInputAction.next,
              isNew: true,
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: l10n.addressOptional,
              controller: _address,
              serverError: _serverErrors?.fieldError('address'),
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.fullStreetAddress],
              maxLength: 255,
            ),
            const SizedBox(height: 16),
            _LogoPicker(
              label: l10n.shopLogoOptional,
              path: _logoPath,
              onPick: _busy ? null : _pickLogo,
              onRemove: _busy ? null : () => setState(() => _logoPath = null),
            ),
            const SizedBox(height: 24),
            PrimaryButton(label: l10n.register, busy: _busy, onPressed: _submit),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: Text(l10n.haveAccount)),
                TextButton(onPressed: _busy ? null : () => context.pop(), child: Text(l10n.login)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopTypeField extends StatelessWidget {
  const _ShopTypeField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.validator,
    this.errorText,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final FormFieldValidator<String> validator;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: Theme.of(context).textTheme.titleSmall),
        ),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          validator: validator,
          decoration: InputDecoration(errorText: errorText),
          items: [
            for (final type in shopTypeValues) DropdownMenuItem(value: type, child: Text(shopTypeLabel(type, l10n))),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _LogoPicker extends StatelessWidget {
  const _LogoPicker({required this.label, required this.path, required this.onPick, required this.onRemove});

  final String label;
  final String? path;
  final VoidCallback? onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: Theme.of(context).textTheme.titleSmall),
        ),
        if (path == null)
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(l10n.chooseLogo),
          )
        else
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(path!),
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  cacheWidth: 192,
                  errorBuilder: (_, _, _) => Container(
                    width: 64,
                    height: 64,
                    color: AppColors.surfaceMuted,
                    child: const Icon(Icons.image_not_supported_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(onPressed: onPick, child: Text(l10n.changeLogo)),
              TextButton(onPressed: onRemove, child: Text(l10n.removeLogo)),
            ],
          ),
      ],
    );
  }
}
