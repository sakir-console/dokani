import 'package:dokani/app/app.dart';
import 'package:dokani/core/storage/preferences.dart';
import 'package:dokani/features/auth/data/auth_repository.dart';
import 'package:dokani/features/shop/data/shop_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Starts the real app (router, theme, localisation) with a fake repository
/// in place of the network. [locale] is the saved language; null means the
/// app default, which is Bangla.
Future<void> pumpApp(
  WidgetTester tester, {
  required FakeAuthRepository repository,
  String? locale,
  ShopRepository? shopRepository,
}) async {
  SharedPreferences.setMockInitialValues({'locale': ?locale});
  final preferences = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authRepositoryProvider.overrideWithValue(repository),
        if (shopRepository != null) shopRepositoryProvider.overrideWithValue(shopRepository),
      ],
      child: const DokaniApp(),
    ),
  );
  await tester.pumpAndSettle();
}
