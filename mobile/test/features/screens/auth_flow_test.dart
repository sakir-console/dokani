import 'package:dokani/core/network/api_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';

Finder field(int index) => find.byType(TextFormField).at(index);

void main() {
  testWidgets('opens in Bangla on the login screen when signed out', (tester) async {
    await pumpApp(tester, repository: FakeAuthRepository());

    expect(find.text('স্বাগতম'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'লগ ইন'), findsOneWidget);
  });

  testWidgets('the language can be switched to English and back', (tester) async {
    await pumpApp(tester, repository: FakeAuthRepository());

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);

    await tester.tap(find.text('বাংলা'));
    await tester.pumpAndSettle();
    expect(find.text('স্বাগতম'), findsOneWidget);
  });

  testWidgets('login validates before calling the server', (tester) async {
    final repository = FakeAuthRepository(serverSession: testSession());
    await pumpApp(tester, repository: repository, locale: 'en');

    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
    expect(find.text('This is required'), findsNWidgets(2));

    await tester.enterText(field(0), '12345');
    await tester.enterText(field(1), 'secret-pass');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid mobile number, like 01712345678'), findsOneWidget);
    expect(repository.lastLoginPhone, isNull, reason: 'No request for invalid input.');
  });

  testWidgets('a successful login opens the home screen with the normalised phone', (tester) async {
    final repository = FakeAuthRepository(serverSession: testSession());
    await pumpApp(tester, repository: repository, locale: 'en');

    await tester.enterText(field(0), '+880 1712-345678');
    await tester.enterText(field(1), 'secret-pass');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(repository.lastLoginPhone, '01712345678');
    expect(find.text('Rahim Store'), findsOneWidget);
    expect(find.text('Free plan'), findsOneWidget);
  });

  testWidgets('a server error is shown on the form and the user stays signed out', (tester) async {
    final repository = FakeAuthRepository(
      loginError: const ApiException(
        kind: ApiErrorKind.server,
        statusCode: 422,
        code: 'INVALID_CREDENTIALS',
        message: 'The phone number or password is incorrect.',
      ),
    );
    await pumpApp(tester, repository: repository, locale: 'en');

    await tester.enterText(field(0), '01712345678');
    await tester.enterText(field(1), 'wrong-pass');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(find.text('The phone number or password is incorrect.'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('being offline is explained in plain words', (tester) async {
    final repository = FakeAuthRepository(loginError: const ApiException(kind: ApiErrorKind.network));
    await pumpApp(tester, repository: repository);

    await tester.enterText(field(0), '01712345678');
    await tester.enterText(field(1), 'secret-pass');
    await tester.tap(find.widgetWithText(FilledButton, 'লগ ইন'));
    await tester.pumpAndSettle();

    expect(find.text('ইন্টারনেট সংযোগ নেই। সংযোগ দেখে আবার চেষ্টা করুন।'), findsOneWidget);
  });

  testWidgets('registration checks every required field and sends the form', (tester) async {
    final repository = FakeAuthRepository(serverSession: testSession());
    await pumpApp(tester, repository: repository, locale: 'en');

    await tester.tap(find.widgetWithText(TextButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Open your shop'), findsOneWidget);

    final submit = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    // Shop name, shop type, owner name, phone, password.
    expect(find.text('This is required'), findsNWidgets(5));
    expect(repository.lastRegistration, isNull);

    await tester.enterText(field(0), 'Rahim Store');
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pharmacy').last);
    await tester.pumpAndSettle();
    await tester.enterText(field(1), 'Rahim Uddin');
    await tester.enterText(field(2), '01712345678');
    await tester.enterText(field(3), 'short');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Use at least 8 characters'), findsOneWidget);

    await tester.enterText(field(3), 'secret-pass');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    final sent = repository.lastRegistration!;
    expect(sent.shopName, 'Rahim Store');
    expect(sent.shopType, 'pharmacy');
    expect(sent.phone, '01712345678');
    expect(sent.locale, 'en');
    expect(find.text('Free plan'), findsOneWidget, reason: 'Registration signs the owner in.');
  });

  testWidgets('forgot password leads to the code screen and back to login', (tester) async {
    await pumpApp(tester, repository: FakeAuthRepository(), locale: 'en');

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.enterText(field(0), '01712345678');
    await tester.tap(find.widgetWithText(FilledButton, 'Send code'));
    await tester.pumpAndSettle();

    expect(find.text('We sent a code to 01712345678'), findsOneWidget);

    await tester.enterText(field(0), '123');
    await tester.enterText(field(1), 'brand-new-pass');
    await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the 6-digit code'), findsOneWidget);

    await tester.enterText(field(0), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
    await tester.pumpAndSettle();

    expect(find.text('Password changed. Log in with your new password.'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
