import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/message_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/app_localizations.dart';
import '../data/auth_repository.dart';
import 'auth_scaffold.dart';

/// Step 2 of a password reset: enter the code and choose a new password.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.phone});

  final String phone;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otp = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  ApiException? _serverErrors;

  @override
  void dispose() {
    _otp.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _serverErrors = null;
    });
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).resetPassword(
            phone: widget.phone,
            otp: _otp.text.trim(),
            password: _password.text,
          );
      if (mounted) context.go('/login', extra: l10n.passwordResetDone);
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

    return AuthScaffold(
      showBack: true,
      title: l10n.resetTitle,
      subtitle: l10n.resetSubtitle(widget.phone),
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
              label: l10n.otpCode,
              controller: _otp,
              validator: validators.otp,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: Validators.otpLength,
            ),
            const SizedBox(height: 16),
            PasswordField(
              label: l10n.newPassword,
              controller: _password,
              validator: validators.password,
              serverError: _serverErrors?.fieldError('password'),
              isNew: true,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            PrimaryButton(label: l10n.resetPassword, busy: _busy, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
