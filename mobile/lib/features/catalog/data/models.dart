/// Catalogue models. Money and quantities stay as the decimal strings the
/// server sends; see Formatters for display.
library;

class NamedRef {
  const NamedRef({required this.id, required this.name});

  final int id;
  final String name;

  static NamedRef? fromJson(Object? json) {
    if (json is! Map) return null;
    return NamedRef(id: json['id'] as int, name: json['name'] as String);
  }
}

class Category {
  const Category({required this.id, required this.name, this.parentId});

  final int id;
  final String name;
  final int? parentId;

  factory Category.fromJson(Map<String, dynamic> json) =>
      Category(id: json['id'] as int, name: json['name'] as String, parentId: json['parent_id'] as int?);
}

class Unit {
  const Unit({
    required this.id,
    required this.name,
    required this.shortName,
    this.nameBn,
    this.allowsDecimal = false,
    this.isBuiltIn = true,
  });

  final int id;
  final String name;
  final String? nameBn;
  final String shortName;
  final bool allowsDecimal;
  final bool isBuiltIn;

  /// Built-in units have a Bangla name; a shop's own units are shown as typed.
  String label(String languageCode) => languageCode == 'bn' && nameBn != null ? nameBn! : name;

  factory Unit.fromJson(Map<String, dynamic> json) => Unit(
        id: json['id'] as int,
        name: json['name'] as String,
        nameBn: json['name_bn'] as String?,
        shortName: json['short_name'] as String? ?? '',
        allowsDecimal: json['allows_decimal'] as bool? ?? false,
        isBuiltIn: json['is_built_in'] as bool? ?? true,
      );
}

enum StockStatus {
  inStock,
  low,
  out;

  static StockStatus parse(String? value) => switch (value) {
        'low' => StockStatus.low,
        'out' => StockStatus.out,
        _ => StockStatus.inStock,
      };
}

class Variant {
  const Variant({
    required this.id,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.stockQuantity,
    this.name,
    this.sku,
    this.stockStatus = StockStatus.inStock,
    this.barcodes = const [],
  });

  final int id;
  final String? name;
  final String? sku;
  final String purchasePrice;
  final String sellingPrice;
  final String stockQuantity;
  final StockStatus stockStatus;
  final List<String> barcodes;

  factory Variant.fromJson(Map<String, dynamic> json) => Variant(
        id: json['id'] as int,
        name: json['name'] as String?,
        sku: json['sku'] as String?,
        // Not sent to roles that may not see what the shop paid.
        purchasePrice: json['purchase_price'] == null ? '0.00' : '${json['purchase_price']}',
        sellingPrice: '${json['selling_price']}',
        stockQuantity: '${json['stock_quantity']}',
        stockStatus: StockStatus.parse(json['stock_status'] as String?),
        barcodes: (json['barcodes'] as List? ?? const []).map((e) => '$e').toList(),
      );
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.unit,
    required this.variants,
    required this.totalStock,
    this.description,
    this.imageUrl,
    this.storageLocation,
    this.hasVariants = false,
    this.lowStockThreshold,
    this.category,
    this.brand,
    this.vendor,
    this.lowStockVariants = 0,
    this.outOfStockVariants = 0,
  });

  final int id;
  final String name;
  final String? description;
  final String? imageUrl;
  final String? storageLocation;
  final bool hasVariants;
  final String? lowStockThreshold;
  final NamedRef? category;
  final NamedRef? brand;
  final NamedRef? vendor;
  final Unit unit;
  final String totalStock;
  final int lowStockVariants;
  final int outOfStockVariants;
  final List<Variant> variants;

  /// The worst state among the variants, for the badge on a list row.
  StockStatus get stockStatus {
    if (variants.isNotEmpty && outOfStockVariants == variants.length) return StockStatus.out;
    if (outOfStockVariants > 0 || lowStockVariants > 0) return StockStatus.low;
    return StockStatus.inStock;
  }

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as int,
        name: json['name'] as String,
        description: json['description'] as String?,
        imageUrl: json['image_url'] as String?,
        storageLocation: json['storage_location'] as String?,
        hasVariants: json['has_variants'] as bool? ?? false,
        lowStockThreshold: json['low_stock_threshold'] == null ? null : '${json['low_stock_threshold']}',
        category: NamedRef.fromJson(json['category']),
        brand: NamedRef.fromJson(json['brand']),
        vendor: NamedRef.fromJson(json['vendor']),
        unit: Unit.fromJson((json['unit'] as Map).cast<String, dynamic>()),
        totalStock: '${json['total_stock']}',
        lowStockVariants: json['low_stock_variants'] as int? ?? 0,
        outOfStockVariants: json['out_of_stock_variants'] as int? ?? 0,
        variants: (json['variants'] as List? ?? const [])
            .map((e) => Variant.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// One page of a server-side paginated list.
class Paged<T> {
  const Paged({required this.items, required this.currentPage, required this.lastPage, required this.total});

  final List<T> items;
  final int currentPage;
  final int lastPage;
  final int total;

  bool get hasMore => currentPage < lastPage;

  factory Paged.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) {
    final meta = (json['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Paged(
      items: (json['data'] as List).map((e) => parse((e as Map).cast<String, dynamic>())).toList(),
      currentPage: meta['current_page'] as int? ?? 1,
      lastPage: meta['last_page'] as int? ?? 1,
      total: meta['total'] as int? ?? 0,
    );
  }
}

class StockSummary {
  const StockSummary({required this.totalProducts, required this.lowStock, required this.outOfStock});

  final int totalProducts;
  final int lowStock;
  final int outOfStock;

  factory StockSummary.fromJson(Map<String, dynamic> json) => StockSummary(
        totalProducts: json['total_products'] as int? ?? 0,
        lowStock: json['low_stock_products'] as int? ?? 0,
        outOfStock: json['out_of_stock_products'] as int? ?? 0,
      );
}

/// A scanned code resolved to a product and the exact variant it belongs to.
class BarcodeMatch {
  const BarcodeMatch({required this.variantId, required this.product});

  final int variantId;
  final Product product;
}

enum StockFilter {
  all,
  low,
  out;

  String? get query => switch (this) {
        StockFilter.all => null,
        StockFilter.low => 'low',
        StockFilter.out => 'out',
      };
}

/// What the product form sends. Built from validated input, so every number
/// is already a canonical decimal string.
class VariantDraft {
  const VariantDraft({
    required this.purchasePrice,
    required this.sellingPrice,
    this.id,
    this.name,
    this.sku,
    this.openingStock,
    this.barcodes = const [],
  });

  final int? id;
  final String? name;
  final String? sku;
  final String purchasePrice;
  final String sellingPrice;

  /// Only used for variants being created; the server ignores it otherwise.
  final String? openingStock;
  final List<String> barcodes;

  Map<String, dynamic> toJson() => {
        'id': ?id,
        'name': name,
        'sku': sku,
        'purchase_price': purchasePrice,
        'selling_price': sellingPrice,
        'stock_quantity': ?openingStock,
        'barcodes': barcodes,
      };
}

class ProductDraft {
  const ProductDraft({
    required this.name,
    required this.unitId,
    required this.hasVariants,
    required this.variants,
    this.categoryId,
    this.brandId,
    this.vendorId,
    this.description,
    this.storageLocation,
    this.lowStockThreshold,
  });

  final String name;
  final int unitId;
  final bool hasVariants;
  final List<VariantDraft> variants;
  final int? categoryId;
  final int? brandId;
  final int? vendorId;
  final String? description;
  final String? storageLocation;
  final String? lowStockThreshold;

  Map<String, dynamic> toJson() => {
        'name': name,
        'unit_id': unitId,
        'category_id': categoryId,
        'brand_id': brandId,
        'vendor_id': vendorId,
        'description': description,
        'storage_location': storageLocation,
        'low_stock_threshold': lowStockThreshold,
        'has_variants': hasVariants,
        'variants': [for (final variant in variants) variant.toJson()],
      };
}
