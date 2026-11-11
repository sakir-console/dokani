import 'package:dokani/core/network/api_client.dart';
import 'package:dokani/core/network/api_exception.dart';
import 'package:dokani/features/auth/application/auth_controller.dart';
import 'package:dokani/features/auth/data/auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  ProviderContainer containerWith(FakeAuthRepository repository) {
    final container = ProviderContainer(overrides: [authRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    // Keep the provider alive for the whole test, as the router does in the app.
    container.listen(authControllerProvider, (_, _) {});
    return container;
  }

  /// Lets the background refresh scheduled by build() run.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

  const offline = ApiException(kind: ApiErrorKind.network);
  const rejected = ApiException(kind: ApiErrorKind.unauthenticated, statusCode: 401);

  test('starts signed out when there is no token', () async {
    final repository = FakeAuthRepository();
    final container = containerWith(repository);

    final state = await container.read(authControllerProvider.future);

    expect(state.isSignedIn, isFalse);
    expect(repository.fetchCalls, 0);
  });

  test('restores the cached session at once, then confirms it with the server', () async {
    final repository = FakeAuthRepository(
      token: 't',
      cached: testSession(shopName: 'Old name'),
      serverSession: testSession(shopName: 'New name'),
    );
    final container = containerWith(repository);

    final first = await container.read(authControllerProvider.future);
    expect(first.session!.shop.name, 'Old name');
    expect(first.isStale, isTrue);

    await settle();

    final refreshed = container.read(authControllerProvider).value!;
    expect(refreshed.session!.shop.name, 'New name');
    expect(refreshed.isStale, isFalse);
  });

  test('stays signed in from the cache when offline', () async {
    final repository = FakeAuthRepository(token: 't', cached: testSession(), fetchError: offline);
    final container = containerWith(repository);

    await container.read(authControllerProvider.future);
    await settle();

    final state = container.read(authControllerProvider).value!;
    expect(state.isSignedIn, isTrue);
    expect(state.isStale, isTrue);
    expect(repository.token, isNotNull, reason: 'Being offline must never sign the user out.');
  });

  test('signs out when the server rejects the saved token', () async {
    final repository = FakeAuthRepository(token: 't', cached: testSession(), fetchError: rejected);
    final container = containerWith(repository);

    await container.read(authControllerProvider.future);
    await settle();

    expect(container.read(authControllerProvider).value!.isSignedIn, isFalse);
    expect(repository.token, isNull);
    expect(repository.cached, isNull);
  });

  test('with a token but no cache and no connection, surfaces the error for a retry', () async {
    final repository = FakeAuthRepository(token: 't', fetchError: offline);
    final container = containerWith(repository);

    await expectLater(container.read(authControllerProvider.future), throwsA(isA<ApiException>()));
    expect(repository.token, isNotNull);
  });

  test('login signs in; a failed login leaves the state signed out', () async {
    final repository = FakeAuthRepository(
      serverSession: testSession(),
      loginError: const ApiException(kind: ApiErrorKind.server, statusCode: 422, code: 'INVALID_CREDENTIALS'),
    );
    final container = containerWith(repository);
    await container.read(authControllerProvider.future);
    final controller = container.read(authControllerProvider.notifier);

    await expectLater(controller.login(phone: '01712345678', password: 'wrong'), throwsA(isA<ApiException>()));
    expect(container.read(authControllerProvider).value!.isSignedIn, isFalse);

    repository.loginError = null;
    await controller.login(phone: '01712345678', password: 'right');

    expect(container.read(authControllerProvider).value!.session!.shop.name, 'Rahim Store');
    expect(repository.lastLoginPhone, '01712345678');
  });

  test('logout clears the session and the token', () async {
    final repository = FakeAuthRepository(token: 't', cached: testSession(), serverSession: testSession());
    final container = containerWith(repository);
    await container.read(authControllerProvider.future);
    await settle();

    await container.read(authControllerProvider.notifier).logout();

    expect(container.read(authControllerProvider).value!.isSignedIn, isFalse);
    expect(repository.logoutCalls, 1);
    expect(repository.token, isNull);
  });

  test('a token rejected during any request signs the user out', () async {
    final repository = FakeAuthRepository(token: 't', cached: testSession(), serverSession: testSession());
    final container = containerWith(repository);
    await container.read(authControllerProvider.future);
    await settle();

    // What the Dio interceptor does on a 401.
    container.read(unauthenticatedNotifierProvider).onUnauthenticated!();
    await settle();

    expect(container.read(authControllerProvider).value!.isSignedIn, isFalse);
    expect(repository.token, isNull);
  });

  test('editing the shop updates the session and its cache', () async {
    final repository = FakeAuthRepository(token: 't', cached: testSession(), serverSession: testSession());
    final container = containerWith(repository);
    await container.read(authControllerProvider.future);
    await settle();

    await container.read(authControllerProvider.notifier).updateShop(testSession(shopName: 'Renamed').shop);

    expect(container.read(sessionProvider)!.shop.name, 'Renamed');
    expect(repository.cached!.shop.name, 'Renamed');
  });
}
