import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'models.dart';

/// Products, categories, brands, units, barcodes and stock.
class CatalogRepository {
  CatalogRepository(this._dio);

  final Dio _dio;

  // --- Reference lists -----------------------------------------------------

  Future<List<Category>> categories() => _list('/categories', Category.fromJson);

  Future<Category> createCategory(String name) => _send('POST', '/categories', {'name': name}, Category.fromJson);

  Future<Category> renameCategory(int id, String name) =>
      _send('PATCH', '/categories/$id', {'name': name}, Category.fromJson);

  Future<void> deleteCategory(int id) => _guard(() => _dio.delete<void>('/categories/$id'));

  Future<List<NamedRef>> brands() => _list('/brands', (json) => NamedRef.fromJson(json)!);

  Future<NamedRef> createBrand(String name) =>
      _send('POST', '/brands', {'name': name}, (json) => NamedRef.fromJson(json)!);

  Future<List<Unit>> units() => _list('/units', Unit.fromJson);

  // --- Products ------------------------------------------------------------

  Future<Paged<Product>> products({String query = '', StockFilter stock = StockFilter.all, int? categoryId, int page = 1}) {
    return _guard(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/products',
        queryParameters: {
          if (query.isNotEmpty) 'q': query,
          'stock': ?stock.query,
          'category_id': ?categoryId,
          'page': page,
          'per_page': 30,
        },
      );
      return Paged.fromJson(response.data!, Product.fromJson);
    });
  }

  Future<Product> product(int id) => _send('GET', '/products/$id', null, Product.fromJson);

  Future<Product> createProduct(ProductDraft draft) => _send('POST', '/products', draft.toJson(), Product.fromJson);

  Future<Product> updateProduct(int id, ProductDraft draft) =>
      _send('PATCH', '/products/$id', draft.toJson(), Product.fromJson);

  Future<void> deleteProduct(int id) => _guard(() => _dio.delete<void>('/products/$id'));

  Future<Product> uploadProductImage(int id, String filePath) {
    return _guard(() async {
      final form = FormData.fromMap({'image': await MultipartFile.fromFile(filePath)});
      final response = await _dio.post<Map<String, dynamic>>('/products/$id/image', data: form);
      return Product.fromJson(_data(response));
    });
  }

  /// Null when no product in this shop has the code.
  Future<BarcodeMatch?> lookupBarcode(String code) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/barcodes/lookup', queryParameters: {'code': code});
      final data = _data(response);
      return BarcodeMatch(
        variantId: data['variant_id'] as int,
        product: Product.fromJson((data['product'] as Map).cast<String, dynamic>()),
      );
    } on DioException catch (error) {
      final failure = ApiException.fromDio(error);
      if (failure.code == 'BARCODE_NOT_FOUND') return null;
      throw failure;
    }
  }

  // --- Stock ---------------------------------------------------------------

  Future<StockSummary> stockSummary() => _send('GET', '/stock/summary', null, StockSummary.fromJson);

  Future<void> stockIn({required int variantId, required String quantity, String? unitCost, String? note}) => _guard(
        () => _dio.post<void>(
          '/stock/in',
          data: {'variant_id': variantId, 'quantity': quantity, 'unit_cost': ?unitCost, 'note': ?note},
        ),
      );

  Future<void> stockOut({required int variantId, required String quantity, required String note}) => _guard(
        () => _dio.post<void>('/stock/out', data: {'variant_id': variantId, 'quantity': quantity, 'note': note}),
      );

  Future<void> adjustStock({required int variantId, required String countedQuantity, String? note}) => _guard(
        () => _dio.post<void>(
          '/stock/adjust',
          data: {'variant_id': variantId, 'new_quantity': countedQuantity, 'note': ?note},
        ),
      );

  // --- Plumbing ------------------------------------------------------------

  Map<String, dynamic> _data(Response<Map<String, dynamic>> response) =>
      (response.data!['data'] as Map).cast<String, dynamic>();

  Future<List<T>> _list<T>(String path, T Function(Map<String, dynamic>) parse) {
    return _guard(() async {
      final response = await _dio.get<Map<String, dynamic>>(path);
      return (response.data!['data'] as List).map((e) => parse((e as Map).cast<String, dynamic>())).toList();
    });
  }

  Future<T> _send<T>(String method, String path, Object? body, T Function(Map<String, dynamic>) parse) {
    return _guard(() async {
      final response = await _dio.request<Map<String, dynamic>>(path, data: body, options: Options(method: method));
      return parse(_data(response));
    });
  }

  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final catalogRepositoryProvider = Provider((ref) => CatalogRepository(ref.watch(dioProvider)));
