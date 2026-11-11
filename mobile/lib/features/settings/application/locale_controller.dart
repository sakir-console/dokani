import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/preferences.dart';

/// The app language. Bangla by default; the choice is remembered on the phone.
class LocaleController extends Notifier<Locale> {
  static const _key = 'locale';
  static const supported = [Locale('bn'), Locale('en')];

  @override
  Locale build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(_key);
    return supported.firstWhere((l) => l.languageCode == saved, orElse: () => supported.first);
  }

  Future<void> set(Locale locale) async {
    if (!supported.contains(locale)) return;
    state = locale;
    await ref.read(sharedPreferencesProvider).setString(_key, locale.languageCode);
  }
}

final localeControllerProvider = NotifierProvider<LocaleController, Locale>(LocaleController.new);
