import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/catalog/data/models.dart';
import '../features/catalog/presentation/categories_screen.dart';
import '../features/catalog/presentation/product_detail_screen.dart';
import '../features/catalog/presentation/product_form_screen.dart';
import '../features/catalog/presentation/products_screen.dart';
import '../features/customers/presentation/customer_detail_screen.dart';
import '../features/customers/presentation/customers_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/pos/presentation/cart_screen.dart';
import '../features/pos/presentation/checkout_screen.dart';
import '../features/pos/presentation/invoice_screen.dart';
import '../features/pos/presentation/pos_screen.dart';
import '../features/pos/presentation/sales_screen.dart';
import '../features/scanner/scanner_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/shop/presentation/edit_shop_screen.dart';
import '../features/vendors/presentation/vendors_screen.dart';

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
        path: '/products',
        builder: (_, state) => ProductsScreen(
          initialFilter: switch (state.uri.queryParameters['stock']) {
            'low' => StockFilter.low,
            'out' => StockFilter.out,
            _ => StockFilter.all,
          },
        ),
        routes: [
          // "new" is declared before ":id" so it is not read as a product id.
          GoRoute(
            path: 'new',
            builder: (_, state) => ProductFormScreen(initialBarcode: state.extra is String ? state.extra! as String : null),
          ),
          GoRoute(
            path: ':id',
            redirect: (_, state) => int.tryParse(state.pathParameters['id']!) == null ? '/products' : null,
            builder: (_, state) => ProductDetailScreen(productId: int.parse(state.pathParameters['id']!)),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (_, state) => ProductFormScreen(productId: int.parse(state.pathParameters['id']!)),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/pos',
        builder: (_, _) => const PosScreen(),
        routes: [
          GoRoute(path: 'cart', builder: (_, _) => const CartScreen()),
          GoRoute(path: 'checkout', builder: (_, _) => const CheckoutScreen()),
        ],
      ),
      GoRoute(
        path: '/sales',
        builder: (_, _) => const SalesScreen(),
        routes: [
          GoRoute(
            path: ':id',
            redirect: (_, state) => int.tryParse(state.pathParameters['id']!) == null ? '/sales' : null,
            builder: (_, state) => InvoiceScreen(
              saleId: int.parse(state.pathParameters['id']!),
              justCompleted: state.uri.queryParameters['new'] == '1',
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/customers',
        builder: (_, state) => CustomersScreen(dueOnly: state.uri.queryParameters['due'] == '1'),
        routes: [
          GoRoute(
            path: ':id',
            redirect: (_, state) => int.tryParse(state.pathParameters['id']!) == null ? '/customers' : null,
            builder: (_, state) => CustomerDetailScreen(customerId: int.parse(state.pathParameters['id']!)),
          ),
        ],
      ),
      GoRoute(path: '/categories', builder: (_, _) => const CategoriesScreen()),
      GoRoute(path: '/vendors', builder: (_, _) => const VendorsScreen()),
      GoRoute(path: '/scan', builder: (_, _) => const ScannerScreen()),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsScreen(),
        routes: [GoRoute(path: 'shop', builder: (_, _) => const EditShopScreen())],
      ),
    ],
  );
});
