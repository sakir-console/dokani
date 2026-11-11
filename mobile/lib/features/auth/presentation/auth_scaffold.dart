import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/language_toggle.dart';

/// Shared frame for the signed-out screens: language switch, title, form.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBack = false,
    this.showBrand = false,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool showBack;
  final bool showBrand;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: showBack,
        actions: const [Padding(padding: EdgeInsets.only(right: 16), child: LanguageToggle())],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showBrand) ...[
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(16)),
                      child: const Text(
                        'দো',
                        style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Semantics(header: true, child: Text(title, style: text.headlineMedium)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: text.bodyLarge?.copyWith(color: AppColors.textMuted)),
                  const SizedBox(height: 24),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
