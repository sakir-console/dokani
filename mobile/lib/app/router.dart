import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/shop/presentation/edit_shop_screen.dart';

const _publicPaths = {'/login', '/register', '/forgot-password', '/reset-password'};

/// Where a visitor in the given auth state should be, or null to stay put.
///
/// Kept as a plain function so the rules can be unit tested without widgets.
String? redirectFor({required AsyncValue<AuthState> auth, required String location}) {
  // Still restoring the session, or it failed with nothing cached: splash.
  if (auth.isLoading && !auth.hasValue) return location == '/splash' ? null : '/splash';
  if (auth.hasError && !auth.hasValue) return location == '/splash' ? null : '/splash';

  final signedIn = auth.value?.isSignedIn ?? false;
  final onPublicPage = _publicPaths.contains(location);

  if (!signedIn) return onPublicPage ? null : '/login';
  if (onPublicPage || location == '/splash') return '/home';
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run the redirect whenever the auth state changes.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(
      auth: ref.read(authControllerProvider),
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: '/login',
        builder: (_, state) => LoginScreen(notice: state.extra is String ? state.extra! as String : null),
      ),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/reset-password',
        // Opened without a phone number (e.g. a restored route): start over.
        redirect: (_, state) => state.extra is String ? null : '/forgot-password',
        builder: (_, state) => ResetPasswordScreen(phone: state.extra! as String),
      ),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsScreen(),
        routes: [GoRoute(path: 'shop', builder: (_, _) => const EditShopScreen())],
      ),
    ],
  );
});
