import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../data/auth_repository.dart';
import '../data/session.dart';

/// Signed in or not, and as whom.
class AuthState {
  const AuthState({this.session, this.isStale = false});

  const AuthState.signedOut() : this();

  final Session? session;

  /// True when [session] came from the phone's cache and the server could
  /// not be reached to confirm it (the app is offline).
  final bool isStale;

  bool get isSignedIn => session != null;
}

/// Owns the session for the whole app.
///
/// On start it restores the cached session immediately — so the app opens
/// without a connection — and then confirms it with the server.
class AuthController extends AsyncNotifier<AuthState> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  Future<AuthState> build() async {
    final notifier = ref.watch(unauthenticatedNotifierProvider);
    notifier.onUnauthenticated = _handleRejectedToken;
    ref.onDispose(() => notifier.onUnauthenticated = null);

    final repository = ref.watch(authRepositoryProvider);
    if (!await repository.hasToken()) {
      return const AuthState.signedOut();
    }

    final cached = repository.cachedSession();
    if (cached != null) {
      // Show the app now; check with the server in the background.
      unawaited(Future<void>.delayed(Duration.zero, refresh));
      return AuthState(session: cached, isStale: true);
    }

    try {
      return AuthState(session: await repository.fetchSession());
    } on ApiException catch (error) {
      if (error.kind == ApiErrorKind.unauthenticated) {
        await repository.clearLocal();
        return const AuthState.signedOut();
      }
      rethrow; // No cache and no server: the splash screen offers a retry.
    }
  }

  Future<void> login({required String phone, required String password}) async {
    final session = await _repository.login(phone: phone, password: password);
    state = AsyncData(AuthState(session: session));
  }

  Future<void> register(RegistrationData data) async {
    final session = await _repository.register(data);
    state = AsyncData(AuthState(session: session));
  }

  /// Re-reads the session from the server. Keeps the current one when offline.
  Future<void> refresh() async {
    try {
      final session = await _repository.fetchSession();
      state = AsyncData(AuthState(session: session));
    } on ApiException catch (error) {
      if (error.kind == ApiErrorKind.unauthenticated) {
        await _signOutLocally();
      } else if (state.value?.session != null) {
        state = AsyncData(AuthState(session: state.value!.session, isStale: error.isOffline));
      }
    }
  }

  /// Replaces the shop in the current session after it was edited.
  Future<void> updateShop(Shop shop) async {
    final current = state.value?.session;
    if (current == null) return;
    final updated = current.copyWith(shop: shop);
    await _repository.cacheSession(updated);
    state = AsyncData(AuthState(session: updated));
  }

  Future<void> logout() async {
    await _repository.logout();
    state = const AsyncData(AuthState.signedOut());
  }

  void _handleRejectedToken() {
    if (state.value?.isSignedIn ?? false) {
      unawaited(_signOutLocally());
    }
  }

  Future<void> _signOutLocally() async {
    await _repository.clearLocal();
    state = const AsyncData(AuthState.signedOut());
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
  // No automatic retries: when the session cannot be restored the splash
  // screen shows the reason and a retry button straight away.
  retry: (_, _) => null,
);

/// The current session, or null when signed out or still loading.
final sessionProvider = Provider<Session?>((ref) => ref.watch(authControllerProvider).value?.session);
