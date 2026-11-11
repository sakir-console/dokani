import 'package:dokani/core/network/api_exception.dart';
import 'package:dokani/features/auth/data/session.dart';
import 'package:dokani/features/shop/data/shop_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';

class _FakeShopRepository implements ShopRepository {
  String? savedName;
  String? savedPhone;

  @override
  Future<Shop> update({required String name, required String shopType, required String phone, String? address}) async {
    savedName = name;
    savedPhone = phone;
    return Shop(id: 7, name: name, shopType: shopType, phone: phone, address: address, status: ShopStatus.active);
  }
}

FakeAuthRepository signedIn({String status = 'active', String role = 'owner', ApiException? fetchError}) {
  final session = role == 'owner'
      ? testSession(status: status)
      : Session.fromJson(sessionJson(status: status, role: role, permissions: ['shop.view', 'pos.sell']));
  return FakeAuthRepository(token: 't', cached: session, serverSession: session, fetchError: fetchError);
}

void main() {
  testWidgets('a returning user lands on the home screen with shop and plan', (tester) async {
    await pumpApp(tester, repository: signedIn(), locale: 'en');

    expect(find.text('Rahim Store'), findsOneWidget);
    expect(find.text('Free plan'), findsOneWidget);
    expect(find.text('No expiry'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('Sales (POS)'), findsOneWidget);
    expect(find.text('a_module_from_the_future'), findsNothing, reason: 'Unknown modules are not shown raw.');
  });

  testWidgets('the home screen is in Bangla by default', (tester) async {
    await pumpApp(tester, repository: signedIn());

    expect(find.text('Free প্যাকেজ'), findsOneWidget);
    expect(find.text('বিক্রয় (POS)'), findsOneWidget);
  });

  testWidgets('a suspended shop sees why, and cannot open shop editing', (tester) async {
    await pumpApp(tester, repository: signedIn(status: 'suspended'), locale: 'en');

    expect(find.text('Shop suspended'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shop profile'));
    await tester.pumpAndSettle();
    expect(find.text('Edit shop'), findsNothing);
  });

  testWidgets('opening offline keeps the user signed in and says so', (tester) async {
    await pumpApp(
      tester,
      repository: signedIn(fetchError: const ApiException(kind: ApiErrorKind.network)),
      locale: 'en',
    );

    expect(find.text('Rahim Store'), findsOneWidget);
    expect(find.text('You are offline. Showing saved information.'), findsOneWidget);
  });

  testWidgets('a cashier cannot open shop editing', (tester) async {
    await pumpApp(tester, repository: signedIn(role: 'cashier'), locale: 'en');

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shop profile'));
    await tester.pumpAndSettle();

    expect(find.text('Edit shop'), findsNothing);
  });

  testWidgets('the owner can edit the shop and sees the change on home', (tester) async {
    final shops = _FakeShopRepository();
    await pumpApp(tester, repository: signedIn(), locale: 'en', shopRepository: shops);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shop profile'));
    await tester.pumpAndSettle();
    expect(find.text('Edit shop'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Rahim Super Shop');
    await tester.enterText(find.byType(TextFormField).at(1), '+8801811111111');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(shops.savedName, 'Rahim Super Shop');
    expect(shops.savedPhone, '01811111111');
    expect(find.text('Rahim Super Shop'), findsOneWidget, reason: 'Back on settings, showing the new name.');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Rahim Super Shop'), findsOneWidget);
  });

  testWidgets('logout asks first, then returns to the login screen', (tester) async {
    final repository = signedIn();
    await pumpApp(tester, repository: repository, locale: 'en');

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Log out'));
    await tester.pumpAndSettle();
    expect(find.text('Log out of this phone?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(repository.logoutCalls, 0);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await tester.pumpAndSettle();

    expect(repository.logoutCalls, 1);
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
