import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/sync/sync_engine.dart';

/// Something the shop should look at, raised by the server. Today that is an
/// offline sale that sold more than was in stock.
class ShopNotice {
  const ShopNotice({
    required this.id,
    required this.type,
    required this.title,
    required this.read,
    required this.createdAt,
    this.body,
    this.saleId,
  });

  final int id;
  final String type;
  final String title;
  final String? body;
  final bool read;
  final DateTime createdAt;

  /// The sale the notice is about, when there is one.
  final int? saleId;

  factory ShopNotice.fromJson(Map<String, dynamic> json) => ShopNotice(
        id: json['id'] as int,
        type: json['type'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String?,
        read: json['read'] as bool? ?? false,
        createdAt: DateTime.tryParse('${json['created_at']}') ?? DateTime.now(),
        saleId: json['data'] is Map && (json['data'] as Map)['sale_id'] is int ? (json['data'] as Map)['sale_id'] as int : null,
      );
}

class NoticeList {
  const NoticeList({this.items = const [], this.unread = 0});

  final List<ShopNotice> items;
  final int unread;
}

class NotificationRepository {
  NotificationRepository(this._dio);

  final Dio _dio;

  /// The latest notices and how many are unread.
  Future<NoticeList> latest() => _guard(() async {
        final response = await _dio.get<Map<String, dynamic>>('/notifications', queryParameters: {'per_page': 50});
        final meta = (response.data!['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
        return NoticeList(
          items: (response.data!['data'] as List).map((e) => ShopNotice.fromJson((e as Map).cast<String, dynamic>())).toList(),
          unread: meta['unread'] as int? ?? 0,
        );
      });

  Future<void> markAllRead() => _guard(() => _dio.post<void>('/notifications/read-all'));

  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final notificationRepositoryProvider = Provider((ref) => NotificationRepository(ref.watch(dioProvider)));

/// Fetched again after every completed sync, because a sync is what raises them.
final noticesProvider = FutureProvider.autoDispose<NoticeList>((ref) {
  ref.watch(syncEngineProvider.select((status) => status.lastSyncedAt));
  return ref.watch(notificationRepositoryProvider).latest();
});
