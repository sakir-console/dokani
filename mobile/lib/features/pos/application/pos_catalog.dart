import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../../core/sync/sync_engine.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/data/models.dart';

/// Where the counter gets its products from.
///
/// Once the phone has synced, everything comes from the local database:
/// searching and scanning are instant and work without a connection.
/// Before the first sync (or if the local database is unavailable) it asks
/// the server directly.
class PosCatalog {
  PosCatalog({required this.database, required this.network});

  static const pageSize = 30;

  final LocalDatabase? database;
  final CatalogRepository network;

  Future<bool> get _hasLocalCopy async => database != null && await database!.productCount() > 0;

  /// One page of products matching [query] (name, or exact barcode / SKU).
  Future<({List<Product> items, bool hasMore})> search(String query, {int page = 1}) async {
    if (await _hasLocalCopy) {
      final rows = await database!.searchProducts(query, limit: pageSize + 1, offset: (page - 1) * pageSize);
      return (items: rows.take(pageSize).map(Product.fromJson).toList(), hasMore: rows.length > pageSize);
    }

    final result = await network.products(query: query, page: page);
    return (items: result.items, hasMore: result.hasMore);
  }

  /// The product and exact variant for a scanned code, or null.
  Future<BarcodeMatch?> lookupBarcode(String code) async {
    if (await _hasLocalCopy) {
      final match = await database!.productByBarcode(code);
      return match == null ? null : BarcodeMatch(variantId: match.variantId, product: Product.fromJson(match.product));
    }

    return network.lookupBarcode(code);
  }
}

final posCatalogProvider = Provider(
  (ref) => PosCatalog(database: ref.watch(localDatabaseProvider), network: ref.watch(catalogRepositoryProvider)),
);
