import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/utils/phone.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/message_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/app_localizations.dart';
import '../data/auth_repository.dart';
import 'auth_scaffold.dart';

/// Step 1 of a password reset: ask for the phone number and send a code.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final phone = Phone.normalize(_phone.text)!;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).requestPasswordReset(phone);
      if (mounted) unawaited(context.push('/reset-password', extra: phone));
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error, AppLocalizations.of(context)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AuthScaffold(
      showBack: true,
      title: l10n.forgotTitle,
      subtitle: l10n.forgotSubtitle,
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
              label: l10n.phone,
              hint: l10n.phoneHint,
              controller: _phone,
              validator: Validators(l10n).phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            PrimaryButton(label: l10n.sendCode, busy: _busy, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
