import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// A labelled text field. The label sits above the field so it stays visible
/// while typing, and server-side errors can be shown under it.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.validator,
    this.serverError,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.inputFormatters,
    this.autofillHints,
    this.obscureText = false,
    this.suffixIcon,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
    this.onFieldSubmitted,
    this.enabled = true,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final String? serverError;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final Widget? suffixIcon;
  final int? maxLength;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onFieldSubmitted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: Theme.of(context).textTheme.titleSmall),
        ),
        TextFormField(
          controller: controller,
          enabled: enabled,
          validator: validator,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          inputFormatters: inputFormatters,
          autofillHints: autofillHints,
          obscureText: obscureText,
          maxLength: maxLength,
          textCapitalization: textCapitalization,
          onFieldSubmitted: onFieldSubmitted,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: hint,
            errorText: serverError,
            suffixIcon: suffixIcon,
            counterText: '',
            // The visible label is a separate Text; this names the field for screen readers.
            semanticCounterText: '',
          ),
        ),
      ],
    );
  }
}

/// A password field with a show/hide toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.label,
    required this.controller,
    this.validator,
    this.serverError,
    this.textInputAction = TextInputAction.done,
    this.onFieldSubmitted,
    this.isNew = false,
  });

  final String label;
  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final String? serverError;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  /// True when choosing a password (register / reset) rather than entering one.
  final bool isNew;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppTextField(
      label: widget.label,
      controller: widget.controller,
      validator: widget.validator,
      serverError: widget.serverError,
      obscureText: _hidden,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      autofillHints: [widget.isNew ? AutofillHints.newPassword : AutofillHints.password],
      suffixIcon: IconButton(
        tooltip: _hidden ? l10n.showPassword : l10n.hidePassword,
        icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
    );
  }
}
