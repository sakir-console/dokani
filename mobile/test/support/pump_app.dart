import 'package:dokani/app/app.dart';
import 'package:dokani/core/database/local_database.dart';
import 'package:dokani/core/storage/preferences.dart';
import 'package:dokani/core/sync/sync_api.dart';
import 'package:dokani/core/sync/sync_engine.dart';
import 'package:dokani/features/auth/data/auth_repository.dart';
import 'package:dokani/core/utils/external.dart';
import 'package:dokani/features/catalog/data/catalog_repository.dart';
import 'package:dokani/features/customers/data/customer_repository.dart';
import 'package:dokani/features/notifications/data/notification_repository.dart';
import 'package:dokani/features/pos/data/sales_repository.dart';
import 'package:dokani/features/reports/data/report_repository.dart';
import 'package:dokani/features/scanner/barcode_scan.dart';
import 'package:dokani/features/shop/data/shop_repository.dart';
import 'package:dokani/features/vendors/data/vendor_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_fakes.dart';
import 'fakes.dart';
import 'report_fakes.dart';
import 'sales_fakes.dart';
import 'sync_fakes.dart';

/// What the app tried to hand to the phone: text for the share sheet, links for the browser.
class Outbox {
  final List<String> shared = [];
  final List<Uri> opened = [];
  final List<String> files = [];
}

/// Starts the real app (router, theme, localisation) with fake repositories
/// in place of the network. [locale] is the saved language; null means the
/// app default, which is Bangla. [scanResult] is what the "camera" returns for
/// a single scan; [scanCodes] are the codes seen by a continuous scan.
/// Without a [database] the app has no local copy and talks to the (fake)
/// server for everything, as it did before offline mode.
Future<void> pumpApp(
  WidgetTester tester, {
  required FakeAuthRepository repository,
  String? locale,
  ShopRepository? shopRepository,
  CatalogRepository? catalog,
  VendorRepository? vendors,
  FakeCustomerRepository? customers,
  FakeSalesRepository? sales,
  FakeReportRepository? reports,
  String? scanResult,
  List<String> scanCodes = const [],
  Outbox? outbox,
  LocalDatabase? database,
  FakeSyncApi? syncApi,
  FakeNotificationRepository? notices,
}) async {
  final catalogRepository = catalog ?? FakeCatalogRepository();
  final customerRepository = customers ?? sales?.customers ?? FakeCustomerRepository();
  final salesRepository = sales ??
      FakeSalesRepository(
        catalog: catalogRepository is FakeCatalogRepository ? catalogRepository : FakeCatalogRepository(),
        customers: customerRepository,
      );

  SharedPreferences.setMockInitialValues({'locale': ?locale});
  final preferences = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        localDatabaseProvider.overrideWithValue(database),
        syncApiProvider.overrideWithValue(syncApi ?? FakeSyncApi()),
        notificationRepositoryProvider.overrideWithValue(notices ?? FakeNotificationRepository()),
        authRepositoryProvider.overrideWithValue(repository),
        catalogRepositoryProvider.overrideWithValue(catalogRepository),
        vendorRepositoryProvider.overrideWithValue(vendors ?? FakeVendorRepository()),
        customerRepositoryProvider.overrideWithValue(customerRepository),
        salesRepositoryProvider.overrideWithValue(salesRepository),
        barcodeScanProvider.overrideWithValue((_) async => scanResult),
        continuousScanProvider.overrideWithValue((_, onCode) async {
          for (final code in scanCodes) {
            await onCode(code);
          }
        }),
        reportRepositoryProvider.overrideWithValue(reports ?? FakeReportRepository()),
        shareTextProvider.overrideWithValue((text) async => outbox?.shared.add(text)),
        shareFileProvider.overrideWithValue((path, name) async => outbox?.files.add(name)),
        openUrlProvider.overrideWithValue((url) async {
          outbox?.opened.add(url);
          return true;
        }),
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
