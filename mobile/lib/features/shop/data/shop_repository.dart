import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/data/session.dart';

class ShopRepository {
  ShopRepository(this._dio);

  final Dio _dio;

  Future<Shop> update({
    required String name,
    required String shopType,
    required String phone,
    String? address,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/shop',
        data: {'name': name, 'shop_type': shopType, 'phone': phone, 'address': address},
      );
      return Shop.fromJson((response.data!['data'] as Map).cast<String, dynamic>());
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final shopRepositoryProvider = Provider((ref) => ShopRepository(ref.watch(dioProvider)));
