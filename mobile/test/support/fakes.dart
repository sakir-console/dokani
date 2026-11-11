import 'package:dokani/core/network/api_exception.dart';
import 'package:dokani/core/storage/token_storage.dart';
import 'package:dokani/features/auth/data/auth_repository.dart';
import 'package:dokani/features/auth/data/session.dart';

class InMemoryTokenStorage implements TokenStorage {
  InMemoryTokenStorage([this.token]);

  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

Map<String, dynamic> sessionJson({
  String shopName = 'Rahim Store',
  String status = 'active',
  String role = 'owner',
  List<String> permissions = const ['*'],
  String planCode = 'free',
  String planName = 'Free',
}) =>
    {
      'user': {'id': 1, 'name': 'Rahim Uddin', 'phone': '01712345678', 'email': null, 'locale': 'bn'},
      'shop': {
        'id': 7,
        'name': shopName,
        'shop_type': 'grocery',
        'phone': '01712345678',
        'address': 'Mirpur 10, Dhaka',
        'logo_url': null,
        'status': status,
        'currency': 'BDT',
        'timezone': 'Asia/Dhaka',
      },
      'role': role,
      'permissions': permissions,
      'subscription': {
        'plan': {'code': planCode, 'name': planName},
        'billing_cycle': 'lifetime',
        'ends_at': null,
        'is_fallback': false,
      },
      'modules': ['products', 'pos', 'customers', 'offline', 'a_module_from_the_future'],
      'limits': {'max_products': 50, 'max_users': 1, 'max_monthly_sales': 300},
      'settings': {'allow_negative_stock': false},
    };

Session testSession({String shopName = 'Rahim Store', String status = 'active', String role = 'owner'}) =>
    Session.fromJson(sessionJson(shopName: shopName, status: status, role: role));

/// A scriptable stand-in for the real repository (no network, no storage).
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.token, this.cached, this.serverSession, this.fetchError, this.loginError});

  String? token;
  Session? cached;
  Session? serverSession;
  ApiException? fetchError;
  ApiException? loginError;

  int fetchCalls = 0;
  int logoutCalls = 0;
  String? lastLoginPhone;
  RegistrationData? lastRegistration;

  @override
  Future<bool> hasToken() async => token != null;

  @override
  Session? cachedSession() => cached;

  @override
  Future<Session> fetchSession() async {
    fetchCalls++;
    if (fetchError != null) throw fetchError!;
    cached = serverSession;
    return serverSession!;
  }

  @override
  Future<Session> login({required String phone, required String password}) async {
    lastLoginPhone = phone;
    if (loginError != null) throw loginError!;
    token = 'token';
    cached = serverSession;
    return serverSession!;
  }

  @override
  Future<Session> register(RegistrationData data) async {
    lastRegistration = data;
    token = 'token';
    cached = serverSession;
    return serverSession!;
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    await clearLocal();
  }

  @override
  Future<void> clearLocal() async {
    token = null;
    cached = null;
  }

  @override
  Future<void> cacheSession(Session session) async => cached = session;

  @override
  Future<void> requestPasswordReset(String phone) async {}

  @override
  Future<void> resetPassword({required String phone, required String otp, required String password}) async {}
}
