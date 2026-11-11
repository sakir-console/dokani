import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/application/locale_controller.dart';
import '../config/env.dart';
import '../storage/token_storage.dart';

/// Called when the server rejects the token (HTTP 401) on an authenticated
/// request. The auth layer registers itself here to sign the user out.
typedef UnauthenticatedCallback = void Function();

class UnauthenticatedNotifier {
  UnauthenticatedCallback? onUnauthenticated;
}

final unauthenticatedNotifierProvider = Provider((ref) => UnauthenticatedNotifier());

/// The single Dio instance used for every API call.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(
    AuthInterceptor(
      tokenStorage: ref.watch(tokenStorageProvider),
      languageCode: () => ref.read(localeControllerProvider).languageCode,
      notifier: ref.watch(unauthenticatedNotifierProvider),
    ),
  );

  ref.onDispose(dio.close);
  return dio;
});

/// Adds the bearer token and the app language to every request, and reports
/// rejected tokens.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.tokenStorage, required this.languageCode, required this.notifier});

  final TokenStorage tokenStorage;
  final String Function() languageCode;
  final UnauthenticatedNotifier notifier;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await tokenStorage.read();
    if (token != null && !options.headers.containsKey('Authorization')) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    options.headers['Accept-Language'] = languageCode();
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final sentToken = err.requestOptions.headers.containsKey('Authorization');
    if (err.response?.statusCode == 401 && sentToken) {
      notifier.onUnauthenticated?.call();
    }
    handler.next(err);
  }
}
