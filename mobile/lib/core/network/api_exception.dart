import 'package:dio/dio.dart';

/// What went wrong with a request, in a form the UI can act on.
enum ApiErrorKind {
  /// No connection, DNS failure, connection refused.
  network,

  /// The server did not answer in time.
  timeout,

  /// The token is missing, expired or revoked (HTTP 401).
  unauthenticated,

  /// The server answered with an error (4xx/5xx) and, usually, a code.
  server,

  /// Anything else.
  unknown,
}

/// Every failure from the API layer is converted to this type, so screens
/// never deal with Dio directly.
class ApiException implements Exception {
  const ApiException({
    required this.kind,
    this.statusCode,
    this.code,
    this.message,
    this.fieldErrors = const {},
  });

  final ApiErrorKind kind;
  final int? statusCode;

  /// Machine-readable code from the server, e.g. `INVALID_CREDENTIALS`,
  /// `SHOP_SUSPENDED`, `VALIDATION_FAILED`.
  final String? code;

  /// Message from the server, already in the language the app asked for.
  final String? message;

  /// Validation errors keyed by field name.
  final Map<String, List<String>> fieldErrors;

  bool get isOffline => kind == ApiErrorKind.network || kind == ApiErrorKind.timeout;

  /// First validation message for [field], if the server sent one.
  String? fieldError(String field) => fieldErrors[field]?.firstOrNull;

  factory ApiException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException(kind: ApiErrorKind.timeout);
      case DioExceptionType.connectionError:
        return const ApiException(kind: ApiErrorKind.network);
      case DioExceptionType.badResponse:
        return ApiException.fromResponse(error.response?.statusCode, error.response?.data);
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.unknown:
        return const ApiException(kind: ApiErrorKind.unknown);
    }
  }

  /// Parses the API's error body: `{ "message": …, "code": …, "errors": { field: [..] } }`.
  factory ApiException.fromResponse(int? statusCode, Object? body) {
    String? code;
    String? message;
    final fieldErrors = <String, List<String>>{};

    if (body is Map) {
      if (body['code'] is String) code = body['code'] as String;
      if (body['message'] is String) message = body['message'] as String;

      final errors = body['errors'];
      if (errors is Map) {
        errors.forEach((key, value) {
          if (value is List) {
            fieldErrors['$key'] = value.map((e) => '$e').toList();
          }
        });
      }
    }

    return ApiException(
      kind: statusCode == 401 ? ApiErrorKind.unauthenticated : ApiErrorKind.server,
      statusCode: statusCode,
      code: code,
      message: message,
      fieldErrors: fieldErrors,
    );
  }

  @override
  String toString() => 'ApiException($kind, status: $statusCode, code: $code, message: $message)';
}
