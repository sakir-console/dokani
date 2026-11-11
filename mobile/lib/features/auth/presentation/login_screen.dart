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
import '../application/auth_controller.dart';
import 'auth_scaffold.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.notice});

  /// Shown above the form, e.g. after a successful password reset.
  final String? notice;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).login(
            phone: Phone.normalize(_phone.text)!,
            password: _password.text,
          );
      // The router sends a signed-in user to the home screen.
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error, AppLocalizations.of(context)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final validators = Validators(l10n);

    return AuthScaffold(
      showBrand: true,
      title: l10n.loginTitle,
      subtitle: l10n.loginSubtitle,
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.notice != null) ...[
                MessageBanner(message: widget.notice!, tone: BannerTone.info),
                const SizedBox(height: 16),
              ],
              if (_error != null) ...[
                MessageBanner(message: _error!),
                const SizedBox(height: 16),
              ],
              AppTextField(
                label: l10n.phone,
                hint: l10n.phoneHint,
                controller: _phone,
                validator: validators.phone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber, AutofillHints.username],
              ),
              const SizedBox(height: 16),
              PasswordField(
                label: l10n.password,
                controller: _password,
                validator: validators.required,
                onFieldSubmitted: (_) => _submit(),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: _busy ? null : () => context.push('/forgot-password'),
                  child: Text(l10n.forgotPassword),
                ),
              ),
              const SizedBox(height: 8),
              PrimaryButton(label: l10n.login, busy: _busy, onPressed: _submit),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(child: Text(l10n.noAccount)),
                  TextButton(
                    onPressed: _busy ? null : () => context.push('/register'),
                    child: Text(l10n.register),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
