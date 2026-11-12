import 'package:dokani/app/app.dart';
import 'package:dokani/core/storage/preferences.dart';
import 'package:dokani/features/auth/data/auth_repository.dart';
import 'package:dokani/features/catalog/data/catalog_repository.dart';
import 'package:dokani/features/scanner/barcode_scan.dart';
import 'package:dokani/features/shop/data/shop_repository.dart';
import 'package:dokani/features/vendors/data/vendor_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_fakes.dart';
import 'fakes.dart';

/// Starts the real app (router, theme, localisation) with fake repositories
/// in place of the network. [locale] is the saved language; null means the
/// app default, which is Bangla. [scanResult] is what the "camera" returns.
Future<void> pumpApp(
  WidgetTester tester, {
  required FakeAuthRepository repository,
  String? locale,
  ShopRepository? shopRepository,
  CatalogRepository? catalog,
  VendorRepository? vendors,
  String? scanResult,
}) async {
  SharedPreferences.setMockInitialValues({'locale': ?locale});
  final preferences = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authRepositoryProvider.overrideWithValue(repository),
        catalogRepositoryProvider.overrideWithValue(catalog ?? FakeCatalogRepository()),
        vendorRepositoryProvider.overrideWithValue(vendors ?? FakeVendorRepository()),
        barcodeScanProvider.overrideWithValue((_) async => scanResult),
        if (shopRepository != null) shopRepositoryProvider.overrideWithValue(shopRepository),
      ],
      child: const DokaniApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// A signed-in owner on the free plan, unless told otherwise.
FakeAuthRepository signedInAs({
  String status = 'active',
  String role = 'owner',
  List<String>? permissions,
  List<String>? modules,
}) {
  final json = sessionJson(
    status: status,
    role: role,
    permissions: permissions ?? (role == 'owner' ? const ['*'] : const ['shop.view', 'pos.sell']),
  );
  if (modules != null) json['modules'] = modules;
  final session = sessionFromJson(json);
  return FakeAuthRepository(token: 't', cached: session, serverSession: session);
}

/// Taps one of the home screen's quick actions: products, add-product, scan,
/// categories or vendors.
Future<void> tapQuickAction(WidgetTester tester, String id) async {
  final button = find.byKey(ValueKey('quick-$id'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}
