import 'package:dokani/core/network/api_exception.dart';
import 'package:dokani/features/catalog/data/catalog_repository.dart';
import 'package:dokani/features/catalog/data/models.dart';
import 'package:dokani/features/vendors/data/vendor_repository.dart';

const piece = Unit(id: 1, name: 'Piece', nameBn: 'পিস', shortName: 'pc');
const kilogram = Unit(id: 2, name: 'Kilogram', nameBn: 'কেজি', shortName: 'kg', allowsDecimal: true);

Variant makeVariant({
  int id = 100,
  String? name,
  String price = '60.00',
  String cost = '50.00',
  String stock = '10.000',
  StockStatus status = StockStatus.inStock,
  List<String> barcodes = const [],
  String? sku,
}) =>
    Variant(
      id: id,
      name: name,
      sellingPrice: price,
      purchasePrice: cost,
      stockQuantity: stock,
      stockStatus: status,
      barcodes: barcodes,
      sku: sku,
    );

Product makeProduct({
  int id = 1,
  String name = 'Miniket Rice',
  Unit unit = piece,
  List<Variant>? variants,
  NamedRef? category,
  NamedRef? brand,
  NamedRef? vendor,
  String? storageLocation,
}) {
  final list = variants ?? [makeVariant(id: id * 100)];
  final total = list.fold<double>(0, (sum, v) => sum + double.parse(v.stockQuantity));
  return Product(
    id: id,
    name: name,
    unit: unit,
    variants: list,
    hasVariants: list.length > 1 || list.first.name != null,
    totalStock: total.toStringAsFixed(3),
    lowStockVariants: list.where((v) => v.stockStatus == StockStatus.low).length,
    outOfStockVariants: list.where((v) => v.stockStatus == StockStatus.out).length,
    category: category,
    brand: brand,
    vendor: vendor,
    storageLocation: storageLocation,
  );
}

/// An in-memory catalogue that behaves like the server closely enough for
/// screen tests, and records what the app asked it to do.
class FakeCatalogRepository implements CatalogRepository {
  FakeCatalogRepository({
    List<Product>? products,
    List<Category>? categories,
    List<NamedRef>? brands,
    this.pageSize = 30,
  })  : _products = [...?products],
        _categories = [...?categories],
        _brands = [...?brands];

  final List<Product> _products;
  final List<Category> _categories;
  final List<NamedRef> _brands;
  final int pageSize;
  int _nextId = 1000;

  /// When set, the next call that can fail throws this once.
  ApiException? failNext;

  final List<String> queries = [];
  final List<ProductDraft> created = [];
  final Map<int, ProductDraft> updated = {};
  final List<int> deleted = [];
  final List<String> stockCalls = [];
  final List<String> imageUploads = [];

  List<Product> get all => List.unmodifiable(_products);

  void _maybeFail() {
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
  }

  @override
  Future<List<Category>> categories() async {
    _maybeFail();
    return [..._categories];
  }

  @override
  Future<Category> createCategory(String name) async {
    _maybeFail();
    final category = Category(id: _nextId++, name: name);
    _categories.add(category);
    return category;
  }

  @override
  Future<Category> renameCategory(int id, String name) async {
    _maybeFail();
    final index = _categories.indexWhere((c) => c.id == id);
    return _categories[index] = Category(id: id, name: name);
  }

  @override
  Future<void> deleteCategory(int id) async {
    _maybeFail();
    _categories.removeWhere((c) => c.id == id);
  }

  @override
  Future<List<NamedRef>> brands() async => [..._brands];

  @override
  Future<NamedRef> createBrand(String name) async {
    final brand = NamedRef(id: _nextId++, name: name);
    _brands.add(brand);
    return brand;
  }

  @override
  Future<List<Unit>> units() async => const [piece, kilogram];

  @override
  Future<Paged<Product>> products({String query = '', StockFilter stock = StockFilter.all, int? categoryId, int page = 1}) async {
    queries.add('q=$query stock=${stock.name} page=$page');
    _maybeFail();

    final q = query.toLowerCase();
    final matches = _products.where((p) {
      final textMatch = q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          p.variants.any((v) => v.barcodes.contains(query) || v.sku == query);
      final stockMatch = switch (stock) {
        StockFilter.all => true,
        StockFilter.low => p.variants.any((v) => v.stockStatus == StockStatus.low),
        StockFilter.out => p.variants.any((v) => v.stockStatus == StockStatus.out),
      };
      return textMatch && stockMatch;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final lastPage = matches.isEmpty ? 1 : ((matches.length - 1) ~/ pageSize) + 1;
    final start = (page - 1) * pageSize;
    final items = start >= matches.length ? <Product>[] : matches.sublist(start, (start + pageSize).clamp(0, matches.length));

    return Paged(items: items, currentPage: page, lastPage: lastPage, total: matches.length);
  }

  @override
  Future<Product> product(int id) async {
    _maybeFail();
    return _products.firstWhere(
      (p) => p.id == id,
      orElse: () => throw const ApiException(kind: ApiErrorKind.server, statusCode: 404, code: 'NOT_FOUND', message: 'Not found.'),
    );
  }

  Product _build(int id, ProductDraft draft, {Product? existing}) {
    final unit = [piece, kilogram].firstWhere((u) => u.id == draft.unitId);
    final variants = [
      for (final v in draft.variants)
        Variant(
          id: v.id ?? _nextId++,
          name: v.name,
          sku: v.sku,
          purchasePrice: v.purchasePrice,
          sellingPrice: v.sellingPrice,
          stockQuantity: v.id != null
              ? existing!.variants.firstWhere((e) => e.id == v.id).stockQuantity
              : (double.tryParse(v.openingStock ?? '0') ?? 0).toStringAsFixed(3),
          barcodes: v.barcodes,
        ),
    ];
    return makeProduct(
      id: id,
      name: draft.name,
      unit: unit,
      variants: variants,
      category: draft.categoryId == null ? null : NamedRef(id: draft.categoryId!, name: _categories.firstWhere((c) => c.id == draft.categoryId).name),
      brand: draft.brandId == null ? null : _brands.firstWhere((b) => b.id == draft.brandId),
      storageLocation: draft.storageLocation,
    );
  }

  @override
  Future<Product> createProduct(ProductDraft draft) async {
    _maybeFail();
    created.add(draft);
    final saved = _build(_nextId++, draft);
    _products.add(saved);
    return saved;
  }

  @override
  Future<Product> updateProduct(int id, ProductDraft draft) async {
    _maybeFail();
    updated[id] = draft;
    final index = _products.indexWhere((p) => p.id == id);
    return _products[index] = _build(id, draft, existing: _products[index]);
  }

  @override
  Future<void> deleteProduct(int id) async {
    _maybeFail();
    deleted.add(id);
    _products.removeWhere((p) => p.id == id);
  }

  @override
  Future<Product> uploadProductImage(int id, String filePath) async {
    _maybeFail();
    imageUploads.add('$id:$filePath');
    return _products.firstWhere((p) => p.id == id);
  }

  @override
  Future<BarcodeMatch?> lookupBarcode(String code) async {
    _maybeFail();
    for (final p in _products) {
      for (final v in p.variants) {
        if (v.barcodes.contains(code)) return BarcodeMatch(variantId: v.id, product: p);
      }
    }
    return null;
  }

  @override
  Future<StockSummary> stockSummary() async => StockSummary(
        totalProducts: _products.length,
        lowStock: _products.where((p) => p.variants.any((v) => v.stockStatus == StockStatus.low)).length,
        outOfStock: _products.where((p) => p.variants.any((v) => v.stockStatus == StockStatus.out)).length,
      );

  void _setStock(int variantId, double Function(double current) change) {
    for (var i = 0; i < _products.length; i++) {
      final p = _products[i];
      if (p.variants.any((v) => v.id == variantId)) {
        _products[i] = makeProduct(
          id: p.id,
          name: p.name,
          unit: p.unit,
          category: p.category,
          variants: [
            for (final v in p.variants)
              v.id == variantId
                  ? makeVariant(id: v.id, name: v.name, price: v.sellingPrice, cost: v.purchasePrice, barcodes: v.barcodes, stock: change(double.parse(v.stockQuantity)).toStringAsFixed(3))
                  : v,
          ],
        );
      }
    }
  }

  @override
  Future<void> stockIn({required int variantId, required String quantity, String? unitCost, String? note}) async {
    _maybeFail();
    stockCalls.add('in $variantId $quantity cost=$unitCost note=$note');
    _setStock(variantId, (current) => current + double.parse(quantity));
  }

  @override
  Future<void> stockOut({required int variantId, required String quantity, required String note}) async {
    _maybeFail();
    stockCalls.add('out $variantId $quantity note=$note');
    _setStock(variantId, (current) => current - double.parse(quantity));
  }

  @override
  Future<void> adjustStock({required int variantId, required String countedQuantity, String? note}) async {
    _maybeFail();
    stockCalls.add('adjust $variantId $countedQuantity note=$note');
    _setStock(variantId, (_) => double.parse(countedQuantity));
  }
}

class FakeVendorRepository implements VendorRepository {
  FakeVendorRepository([List<Vendor>? vendors]) : _vendors = [...?vendors];

  final List<Vendor> _vendors;
  int _nextId = 500;
  final List<VendorDraft> created = [];
  final Map<int, VendorDraft> updated = {};

  @override
  Future<List<Vendor>> vendors({String query = ''}) async {
    final q = query.toLowerCase();
    return _vendors.where((v) => v.name.toLowerCase().contains(q) || (v.phone ?? '').contains(q)).toList();
  }

  Vendor _from(int id, VendorDraft d) =>
      Vendor(id: id, name: d.name, phone: d.phone, companyName: d.companyName, address: d.address, notes: d.notes, productsCount: 0);

  @override
  Future<Vendor> create(VendorDraft draft) async {
    created.add(draft);
    final vendor = _from(_nextId++, draft);
    _vendors.add(vendor);
    return vendor;
  }

  @override
  Future<Vendor> update(int id, VendorDraft draft) async {
    updated[id] = draft;
    final index = _vendors.indexWhere((v) => v.id == id);
    return _vendors[index] = _from(id, draft);
  }

  @override
  Future<void> delete(int id) async => _vendors.removeWhere((v) => v.id == id);
}
