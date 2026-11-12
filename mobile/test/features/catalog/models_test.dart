import 'package:dokani/features/catalog/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shape the API returns for one product (ProductResource).
Map<String, dynamic> productJson() => {
      'id': 9,
      'name': 'Polo T-shirt',
      'description': null,
      'image_url': null,
      'storage_location': 'Rack 3',
      'has_variants': true,
      'is_active': true,
      'low_stock_threshold': null,
      'effective_low_stock_threshold': '5.000',
      'category': {'id': 2, 'name': 'Clothing'},
      'brand': null,
      'unit': {'id': 1, 'name': 'Piece', 'name_bn': 'পিস', 'short_name': 'pc', 'allows_decimal': false, 'is_built_in': true},
      'vendor': null,
      'total_stock': '13.000',
      'low_stock_variants': 1,
      'out_of_stock_variants': 1,
      'variants': [
        {'id': 1, 'name': 'S', 'attributes': {'size': 'S'}, 'sku': null, 'purchase_price': '200.00', 'selling_price': '350.00', 'stock_quantity': '4.000', 'stock_status': 'low', 'is_default': true, 'barcodes': ['TS-S']},
        {'id': 2, 'name': 'M', 'attributes': null, 'sku': 'TS-M', 'purchase_price': '210.00', 'selling_price': '360.00', 'stock_quantity': '0.000', 'stock_status': 'out', 'is_default': false, 'barcodes': <String>[]},
        {'id': 3, 'name': 'L', 'attributes': null, 'sku': null, 'purchase_price': '220.00', 'selling_price': '370.00', 'stock_quantity': '9.000', 'stock_status': 'in', 'is_default': false, 'barcodes': <String>[]},
      ],
      'from_global_catalog': false,
      'updated_at': '2026-11-12T10:00:00+00:00',
    };

void main() {
  test('parses a product exactly as the API sends it', () {
    final product = Product.fromJson(productJson());

    expect(product.name, 'Polo T-shirt');
    expect(product.hasVariants, isTrue);
    expect(product.category!.name, 'Clothing');
    expect(product.brand, isNull);
    expect(product.unit.label('bn'), 'পিস');
    expect(product.unit.label('en'), 'Piece');
    expect(product.totalStock, '13.000');
    expect(product.variants, hasLength(3));
    expect(product.variants[0].sellingPrice, '350.00', reason: 'Money stays a string, never a double.');
    expect(product.variants[0].barcodes, ['TS-S']);
    expect(product.variants[0].stockStatus, StockStatus.low);
    expect(product.variants[1].stockStatus, StockStatus.out);
    expect(product.variants[2].stockStatus, StockStatus.inStock);
    expect(product.stockStatus, StockStatus.low, reason: 'Some variants need attention, but not all are empty.');
  });

  test('a product is "out" only when every variant is out', () {
    final json = productJson()..['out_of_stock_variants'] = 3;
    expect(Product.fromJson(json).stockStatus, StockStatus.out);

    final fine = productJson()
      ..['out_of_stock_variants'] = 0
      ..['low_stock_variants'] = 0;
    expect(Product.fromJson(fine).stockStatus, StockStatus.inStock);
  });

  test('a paged response exposes whether more pages exist', () {
    final page = Paged.fromJson({
      'data': [productJson()],
      'meta': {'current_page': 2, 'last_page': 3, 'total': 61},
    }, Product.fromJson);

    expect(page.items, hasLength(1));
    expect(page.hasMore, isTrue);
    expect(page.total, 61);
  });

  test('a product draft sends ids only for existing variants and opening stock only for new ones', () {
    const draft = ProductDraft(
      name: 'Shampoo',
      unitId: 1,
      hasVariants: true,
      variants: [
        VariantDraft(id: 7, name: '250ml', purchasePrice: '100', sellingPrice: '150', barcodes: ['A']),
        VariantDraft(name: '500ml', purchasePrice: '180', sellingPrice: '260', openingStock: '6'),
      ],
    );

    final json = draft.toJson();
    final variants = json['variants'] as List;

    expect(json['has_variants'], isTrue);
    expect(variants[0], containsPair('id', 7));
    expect((variants[0] as Map).containsKey('stock_quantity'), isFalse);
    expect((variants[1] as Map).containsKey('id'), isFalse);
    expect(variants[1], containsPair('stock_quantity', '6'));
    expect(variants[1], containsPair('selling_price', '260'));
  });

  test('a product sent to a cashier has no purchase price, and still parses', () {
    final variant = Variant.fromJson({'id': 1, 'name': null, 'selling_price': '60.00', 'stock_quantity': '5.000', 'stock_status': 'in', 'barcodes': <String>[]});

    expect(variant.sellingPrice, '60.00');
    expect(variant.purchasePrice, '0.00');
  });
}
