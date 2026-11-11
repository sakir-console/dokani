import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

enum BannerTone { error, warning, info }

/// An inline message: a form error, an offline notice, a suspended-shop notice.
class MessageBanner extends StatelessWidget {
  const MessageBanner({super.key, required this.message, this.title, this.tone = BannerTone.error, this.action});

  final String message;
  final String? title;
  final BannerTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final (Color foreground, Color background, IconData icon) = switch (tone) {
      BannerTone.error => (AppColors.danger, AppColors.dangerSurface, Icons.error_outline),
      BannerTone.warning => (AppColors.warning, AppColors.warningSurface, Icons.warning_amber_rounded),
      BannerTone.info => (AppColors.brandDark, const Color(0xFFECFDF5), Icons.info_outline),
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: foreground.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(title!, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: foreground)),
                  Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: foreground)),
                  ?action,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
