import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../catalog/data/models.dart';
import 'sale_models.dart';

class SalesRepository {
  SalesRepository(this._dio);

  final Dio _dio;

  /// [soldAt] is the moment the cashier completed the sale. [offlineRef] is the
  /// reference shown on the phone; the server ignores it for an online sale.
  Future<Sale> createSale(SaleDraft draft, {DateTime? soldAt, String? offlineRef}) => _one(
        () => _dio.post<Map<String, dynamic>>(
          '/sales',
          data: {...draft.toJson(), if (soldAt != null) 'sold_at': soldAt.toUtc().toIso8601String(), 'offline_ref': ?offlineRef},
        ),
      );

  Future<Sale> sale(int id) => _one(() => _dio.get<Map<String, dynamic>>('/sales/$id'));

  Future<Sale> voidSale(int id, String reason) =>
      _one(() => _dio.post<Map<String, dynamic>>('/sales/$id/void', data: {'reason': reason}));

  Future<Paged<Sale>> sales({int page = 1}) => _guard(() async {
        final response =
            await _dio.get<Map<String, dynamic>>('/sales', queryParameters: {'page': page, 'per_page': 30});
        return Paged.fromJson(response.data!, Sale.fromJson);
      });

  Future<DashboardData> dashboard() => _guard(() async {
        final response = await _dio.get<Map<String, dynamic>>('/dashboard');
        return DashboardData.fromJson((response.data!['data'] as Map).cast<String, dynamic>());
      });

  Future<Sale> _one(Future<Response<Map<String, dynamic>>> Function() request) => _guard(() async {
        final response = await request();
        return Sale.fromJson((response.data!['data'] as Map).cast<String, dynamic>());
      });

  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final salesRepositoryProvider = Provider((ref) => SalesRepository(ref.watch(dioProvider)));

final dashboardProvider =
    FutureProvider.autoDispose<DashboardData>((ref) => ref.watch(salesRepositoryProvider).dashboard());

final saleProvider = FutureProvider.autoDispose.family<Sale, int>((ref, id) => ref.watch(salesRepositoryProvider).sale(id));
