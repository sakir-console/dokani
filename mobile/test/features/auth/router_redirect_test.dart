import 'package:dokani/app/router.dart';
import 'package:dokani/features/auth/application/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  const loading = AsyncLoading<AuthState>();
  const signedOut = AsyncData(AuthState.signedOut());
  final signedIn = AsyncData(AuthState(session: testSession()));
  final failed = AsyncError<AuthState>(Exception('offline'), StackTrace.empty);

  test('while the session is being restored everything waits on the splash screen', () {
    expect(redirectFor(auth: loading, location: '/home'), '/splash');
    expect(redirectFor(auth: loading, location: '/login'), '/splash');
    expect(redirectFor(auth: loading, location: '/splash'), isNull);
  });

  test('a failed restore stays on the splash screen, which offers a retry', () {
    expect(redirectFor(auth: failed, location: '/home'), '/splash');
    expect(redirectFor(auth: failed, location: '/splash'), isNull);
  });

  test('signed-out visitors can only reach the public screens', () {
    expect(redirectFor(auth: signedOut, location: '/splash'), '/login');
    expect(redirectFor(auth: signedOut, location: '/home'), '/login');
    expect(redirectFor(auth: signedOut, location: '/settings'), '/login');
    expect(redirectFor(auth: signedOut, location: '/settings/shop'), '/login');

    for (final path in ['/login', '/register', '/forgot-password', '/reset-password']) {
      expect(redirectFor(auth: signedOut, location: path), isNull, reason: path);
    }
  });

  test('signed-in users are sent away from the sign-in screens', () {
    expect(redirectFor(auth: signedIn, location: '/splash'), '/home');
    expect(redirectFor(auth: signedIn, location: '/login'), '/home');
    expect(redirectFor(auth: signedIn, location: '/register'), '/home');
    expect(redirectFor(auth: signedIn, location: '/home'), isNull);
    expect(redirectFor(auth: signedIn, location: '/settings/shop'), isNull);
  });
}
