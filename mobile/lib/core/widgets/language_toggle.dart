import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/application/locale_controller.dart';

/// Switches between Bangla and English. Each option is written in its own
/// language so it can be found by someone who cannot read the current one.
class LanguageToggle extends ConsumerWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider);

    return SegmentedButton<String>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(value: 'bn', label: Text('বাংলা')),
        ButtonSegment(value: 'en', label: Text('English')),
      ],
      selected: {locale.languageCode},
      onSelectionChanged: (selection) => ref.read(localeControllerProvider.notifier).set(Locale(selection.first)),
    );
  }
}
