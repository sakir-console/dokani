import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sync/sync_engine.dart';
import '../features/settings/application/locale_controller.dart';
import '../l10n/app_localizations.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class DokaniApp extends ConsumerStatefulWidget {
  const DokaniApp({super.key});

  @override
  ConsumerState<DokaniApp> createState() => _DokaniAppState();
}

class _DokaniAppState extends ConsumerState<DokaniApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Coming back to the app is the likeliest moment for the connection to
    // have returned: send what is waiting and fetch what changed.
    _lifecycle = AppLifecycleListener(onResume: () => ref.read(syncEngineProvider.notifier).sync());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the sync engine alive for the whole session; it starts a sync by
    // itself when a shop signs in.
    ref.watch(syncEngineProvider.select((status) => status.lastSyncedAt));

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: ref.watch(localeControllerProvider),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
