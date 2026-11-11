import 'package:dio/dio.dart';
import 'package:dokani/core/network/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final request = RequestOptions(path: '/x');

  test('parses the API error body', () {
    final error = ApiException.fromResponse(422, {
      'message': 'The phone has already been taken.',
      'code': 'VALIDATION_FAILED',
      'errors': {
        'phone': ['The phone has already been taken.'],
        'password': ['Too short.', 'Another problem.'],
      },
    });

    expect(error.kind, ApiErrorKind.server);
    expect(error.statusCode, 422);
    expect(error.code, 'VALIDATION_FAILED');
    expect(error.fieldError('phone'), 'The phone has already been taken.');
    expect(error.fieldError('password'), 'Too short.');
    expect(error.fieldError('shop_name'), isNull);
    expect(error.isOffline, isFalse);
  });

  test('a 401 is reported as unauthenticated', () {
    final error = ApiException.fromResponse(401, {'message': 'Please log in.', 'code': 'UNAUTHENTICATED'});
    expect(error.kind, ApiErrorKind.unauthenticated);
  });

  test('survives a body that is not the expected shape', () {
    for (final body in [null, 'Bad Gateway', <int>[1, 2], {'errors': 'nope'}, {'message': 42}]) {
      final error = ApiException.fromResponse(502, body);
      expect(error.kind, ApiErrorKind.server);
      expect(error.message, isNull);
      expect(error.fieldErrors, isEmpty);
    }
  });

  test('connection problems are reported as offline', () {
    final noNetwork = ApiException.fromDio(DioException.connectionError(requestOptions: request, reason: 'x'));
    final slow = ApiException.fromDio(DioException.receiveTimeout(timeout: Duration.zero, requestOptions: request));

    expect(noNetwork.kind, ApiErrorKind.network);
    expect(slow.kind, ApiErrorKind.timeout);
    expect(noNetwork.isOffline, isTrue);
    expect(slow.isOffline, isTrue);
  });

  test('a server response inside a DioException is parsed', () {
    final error = ApiException.fromDio(
      DioException.badResponse(
        statusCode: 403,
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 403,
          data: {'message': 'Suspended.', 'code': 'SHOP_SUSPENDED'},
        ),
      ),
    );

    expect(error.code, 'SHOP_SUSPENDED');
    expect(error.statusCode, 403);
  });
}
