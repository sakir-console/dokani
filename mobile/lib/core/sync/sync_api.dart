import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../network/api_exception.dart';

/// One page of a pull: changed rows, ids deleted on the server, and paging.
class PullPage {
  const PullPage({required this.rows, required this.deletedIds, required this.lastPage, required this.cursor});

  final List<Map<String, dynamic>> rows;
  final List<int> deletedIds;
  final int lastPage;

  /// Where the next sync should start from.
  final String cursor;
}

/// The server's answer for one pushed record.
class PushResult {
  const PushResult({required this.clientUuid, required this.status, this.code, this.message, this.server = const {}});

  final String? clientUuid;

  /// created, duplicate or failed
  final String status;
  final String? code;
  final String? message;
  final Map<String, dynamic> server;

  /// Stored on the server, now or by an earlier attempt.
  bool get accepted => status == 'created' || status == 'duplicate';

  factory PushResult.fromJson(Map<String, dynamic> json) => PushResult(
        clientUuid: json['client_uuid'] as String?,
        status: json['status'] as String? ?? 'failed',
        code: json['code'] as String?,
        message: json['message'] as String?,
        server: (json['server'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

/// The sync endpoints, and nothing else.
class SyncApi {
  SyncApi(this._dio);

  final Dio _dio;

  Future<PullPage> pull(String what, {String? since, int page = 1}) => _guard(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/sync/$what',
          queryParameters: {'since': ?since, 'page': page},
        );
        final body = response.data!;
        final meta = (body['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
        return PullPage(
          rows: (body['data'] as List).map((e) => (e as Map).cast<String, dynamic>()).toList(),
          deletedIds: (body['deleted_ids'] as List? ?? const []).map((e) => e as int).toList(),
          lastPage: meta['last_page'] as int? ?? 1,
          cursor: meta['cursor'] as String,
        );
      });

  /// Sends queued records. Returns one result per record, in the order sent.
  Future<({List<PushResult> sales, List<PushResult> dueCollections})> push({
    required String deviceUuid,
    List<Map<String, dynamic>> sales = const [],
    List<Map<String, dynamic>> dueCollections = const [],
  }) =>
      _guard(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/sync/push',
          data: {
            'device': {'uuid': deviceUuid, 'platform': 'android'},
            'sales': sales,
            'due_collections': dueCollections,
          },
        );
        final data = (response.data!['data'] as Map).cast<String, dynamic>();
        List<PushResult> parse(String key) =>
            (data[key] as List? ?? const []).map((e) => PushResult.fromJson((e as Map).cast<String, dynamic>())).toList();
        return (sales: parse('sales'), dueCollections: parse('due_collections'));
      });

  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final syncApiProvider = Provider((ref) => SyncApi(ref.watch(dioProvider)));
