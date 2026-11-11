import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/preferences.dart';
import '../../../core/storage/token_storage.dart';
import 'session.dart';

class RegistrationData {
  const RegistrationData({
    required this.shopName,
    required this.ownerName,
    required this.phone,
    required this.password,
    required this.shopType,
    required this.locale,
    this.address,
    this.logoPath,
  });

  final String shopName;
  final String ownerName;
  final String phone;
  final String password;
  final String shopType;
  final String locale;
  final String? address;

  /// Path of an image picked on the phone, if any.
  final String? logoPath;
}

/// Talks to the auth endpoints, and keeps the token and the last known
/// session on the phone so the app can open without a connection.
class AuthRepository {
  AuthRepository({required this._dio, required this._tokenStorage, required this._preferences});

  static const _sessionKey = 'cached_session';
  static const _deviceName = 'Android phone';

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final SharedPreferences _preferences;

  Future<bool> hasToken() async => (await _tokenStorage.read()) != null;

  /// The session saved after the last successful sign-in or refresh.
  Session? cachedSession() {
    final raw = _preferences.getString(_sessionKey);
    if (raw == null) return null;
    try {
      return Session.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return null; // An unreadable cache is the same as no cache.
    }
  }

  Future<Session> login({required String phone, required String password}) {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'phone': phone, 'password': password, 'device_name': _deviceName},
      );
      return _storeAuthenticated(response.data!);
    });
  }

  Future<Session> register(RegistrationData data) {
    return _guard(() async {
      final form = FormData.fromMap({
        'shop_name': data.shopName,
        'owner_name': data.ownerName,
        'phone': data.phone,
        'password': data.password,
        'shop_type': data.shopType,
        'locale': data.locale,
        if (data.address != null && data.address!.isNotEmpty) 'address': data.address,
        'device_name': _deviceName,
        if (data.logoPath != null) 'logo': await MultipartFile.fromFile(data.logoPath!),
      });
      final response = await _dio.post<Map<String, dynamic>>('/auth/register', data: form);
      return _storeAuthenticated(response.data!);
    });
  }

  /// Fetches the current session from the server and refreshes the cache.
  Future<Session> fetchSession() {
    return _guard(() async {
      final response = await _dio.get<Map<String, dynamic>>('/me');
      final session = Session.fromJson((response.data!['data'] as Map).cast<String, dynamic>());
      await cacheSession(session);
      return session;
    });
  }

  Future<void> requestPasswordReset(String phone) {
    return _guard(() => _dio.post<void>('/auth/forgot-password', data: {'phone': phone}));
  }

  Future<void> resetPassword({required String phone, required String otp, required String password}) {
    return _guard(
      () => _dio.post<void>('/auth/reset-password', data: {'phone': phone, 'otp': otp, 'password': password}),
    );
  }

  /// Revokes the token on the server when possible, and always forgets it locally.
  Future<void> logout() async {
    try {
      await _dio.post<void>('/auth/logout');
    } on DioException {
      // Offline or already revoked: signing out locally is still correct.
    }
    await clearLocal();
  }

  Future<void> clearLocal() async {
    await _tokenStorage.clear();
    await _preferences.remove(_sessionKey);
  }

  Future<void> cacheSession(Session session) => _preferences.setString(_sessionKey, jsonEncode(session.toJson()));

  Future<Session> _storeAuthenticated(Map<String, dynamic> body) async {
    final data = (body['data'] as Map).cast<String, dynamic>();
    final session = Session.fromJson(data);
    await _tokenStorage.write(data['token'] as String);
    await cacheSession(session);
    return session;
  }

  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    dio: ref.watch(dioProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
    preferences: ref.watch(sharedPreferencesProvider),
  ),
);
