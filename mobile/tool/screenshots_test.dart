// Renders the main screens to PNG files without a phone or emulator.
//
//   flutter test tool/screenshots_test.dart --update-goldens
//
// Images are written to tool/screenshots/ (git-ignored). This is a way to
// look at the UI during development, not a regression test: it is not part
// of the normal `flutter test` run.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/fakes.dart';
import '../test/support/pump_app.dart';

/// Tests draw text with a placeholder font unless real fonts are loaded.
Future<void> loadFonts() async {
  final hind = FontLoader('HindSiliguri');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/HindSiliguri-$weight.ttf').readAsBytesSync();
    hind.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await hind.load();

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await loader.load();
    }
  }
}

Future<void> shoot(WidgetTester tester, String name) async {
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/$name.png'));
}

void main() {
  setUpAll(loadFonts);

  // A small, low-end Android screen: 360 x 720 logical pixels.
  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(720, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('login', (tester) async {
    usePhone(tester);
    await pumpApp(tester, repository: FakeAuthRepository());
    await shoot(tester, 'login_bn');

    await tester.tap(find.widgetWithText(FilledButton, 'লগ ইন'));
    await tester.pumpAndSettle();
    await shoot(tester, 'login_bn_errors');
  });

  testWidgets('register', (tester) async {
    usePhone(tester);
    await pumpApp(tester, repository: FakeAuthRepository());
    await tester.tap(find.widgetWithText(TextButton, 'অ্যাকাউন্ট খুলুন'));
    await tester.pumpAndSettle();
    await shoot(tester, 'register_bn');
  });

  testWidgets('home and settings', (tester) async {
    usePhone(tester);
    final session = testSession(shopName: 'রহিম স্টোর');
    await pumpApp(tester, repository: FakeAuthRepository(token: 't', cached: session, serverSession: session));
    await shoot(tester, 'home_bn');

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await shoot(tester, 'settings_bn');

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await shoot(tester, 'home_en');
  });

  testWidgets('suspended shop', (tester) async {
    usePhone(tester);
    final session = testSession(status: 'suspended');
    await pumpApp(tester, repository: FakeAuthRepository(token: 't', cached: session, serverSession: session));
    await shoot(tester, 'home_suspended_bn');
  });
}
