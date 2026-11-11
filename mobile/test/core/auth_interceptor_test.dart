import 'package:dio/dio.dart';
import 'package:dokani/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Answers every request without touching the network.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.statusCode);

  final int statusCode;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    lastRequest = options;
    return ResponseBody.fromString('{}', statusCode, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  (Dio, _StubAdapter, UnauthenticatedNotifier) build({String? token, int statusCode = 200, String language = 'bn'}) {
    final notifier = UnauthenticatedNotifier();
    final adapter = _StubAdapter(statusCode);
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(
        AuthInterceptor(
          tokenStorage: InMemoryTokenStorage(token),
          languageCode: () => language,
          notifier: notifier,
        ),
      );
    return (dio, adapter, notifier);
  }

  test('adds the bearer token and the app language', () async {
    final (dio, adapter, _) = build(token: 'abc123', language: 'en');

    await dio.get<void>('/me');

    expect(adapter.lastRequest!.headers['Authorization'], 'Bearer abc123');
    expect(adapter.lastRequest!.headers['Accept-Language'], 'en');
  });

  test('sends no Authorization header when signed out', () async {
    final (dio, adapter, _) = build();

    await dio.post<void>('/auth/login');

    expect(adapter.lastRequest!.headers.containsKey('Authorization'), isFalse);
  });

  test('reports a rejected token', () async {
    final (dio, _, notifier) = build(token: 'expired', statusCode: 401);
    var rejected = 0;
    notifier.onUnauthenticated = () => rejected++;

    await expectLater(dio.get<void>('/me'), throwsA(isA<DioException>()));

    expect(rejected, 1);
  });

  test('a 401 on a request without a token is not a rejected token', () async {
    // e.g. wrong password on the login form must not trigger a sign-out.
    final (dio, _, notifier) = build(statusCode: 401);
    var rejected = 0;
    notifier.onUnauthenticated = () => rejected++;

    await expectLater(dio.post<void>('/auth/login'), throwsA(isA<DioException>()));

    expect(rejected, 0);
  });
}
