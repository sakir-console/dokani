import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';

class Vendor {
  const Vendor({
    required this.id,
    required this.name,
    this.phone,
    this.companyName,
    this.address,
    this.notes,
    this.productsCount,
  });

  final int id;
  final String name;
  final String? phone;
  final String? companyName;
  final String? address;
  final String? notes;
  final int? productsCount;

  factory Vendor.fromJson(Map<String, dynamic> json) => Vendor(
        id: json['id'] as int,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        companyName: json['company_name'] as String?,
        address: json['address'] as String?,
        notes: json['notes'] as String?,
        productsCount: json['products_count'] as int?,
      );
}

class VendorDraft {
  const VendorDraft({required this.name, this.phone, this.companyName, this.address, this.notes});

  final String name;
  final String? phone;
  final String? companyName;
  final String? address;
  final String? notes;

  Map<String, dynamic> toJson() =>
      {'name': name, 'phone': phone, 'company_name': companyName, 'address': address, 'notes': notes};
}

class VendorRepository {
  VendorRepository(this._dio);

  final Dio _dio;

  /// The first 100 matches; a shop's vendor list is short and search narrows it.
  Future<List<Vendor>> vendors({String query = ''}) => _guard(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/vendors',
          queryParameters: {if (query.isNotEmpty) 'q': query, 'per_page': 100},
        );
        return (response.data!['data'] as List)
            .map((e) => Vendor.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  Future<Vendor> create(VendorDraft draft) => _save('POST', '/vendors', draft);

  Future<Vendor> update(int id, VendorDraft draft) => _save('PATCH', '/vendors/$id', draft);

  Future<void> delete(int id) => _guard(() => _dio.delete<void>('/vendors/$id'));

  Future<Vendor> _save(String method, String path, VendorDraft draft) => _guard(() async {
        final response =
            await _dio.request<Map<String, dynamic>>(path, data: draft.toJson(), options: Options(method: method));
        return Vendor.fromJson((response.data!['data'] as Map).cast<String, dynamic>());
      });

  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final vendorRepositoryProvider = Provider((ref) => VendorRepository(ref.watch(dioProvider)));

/// Vendors matching a search term ('' = all).
final vendorsProvider =
    FutureProvider.autoDispose.family<List<Vendor>, String>((ref, query) => ref.watch(vendorRepositoryProvider).vendors(query: query));
