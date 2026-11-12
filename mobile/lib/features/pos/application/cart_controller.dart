import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/exact.dart';
import '../../catalog/data/models.dart';

/// One product (variant) in the cart, with the price it was added at.
class CartLine {
  const CartLine({
    required this.variantId,
    required this.title,
    required this.unit,
    required this.unitPricePaisa,
    required this.quantityMilli,
    required this.stockMilli,
    required this.allowsDecimal,
  });

  final int variantId;
  final String title;
  final Unit unit;
  final int unitPricePaisa;
  final int quantityMilli;

  /// Stock when the product was loaded. The server checks again at checkout.
  final int stockMilli;
  final bool allowsDecimal;

  int get totalPaisa => Exact.lineTotal(unitPricePaisa, quantityMilli);

  /// "কেজি" / "Kilogram" for built-in units; a shop's own unit by its short name.
  String unitLabel(String languageCode) => unit.isBuiltIn ? unit.label(languageCode) : unit.shortName;

  CartLine withQuantity(int quantityMilli) => CartLine(
        variantId: variantId,
        title: title,
        unit: unit,
        unitPricePaisa: unitPricePaisa,
        quantityMilli: quantityMilli,
        stockMilli: stockMilli,
        allowsDecimal: allowsDecimal,
      );
}

class CartState {
  const CartState({this.lines = const [], this.discountPaisa = 0, this.chargePaisa = 0});

  final List<CartLine> lines;
  final int discountPaisa;
  final int chargePaisa;

  bool get isEmpty => lines.isEmpty;
  int get lineCount => lines.length;
  int get subtotalPaisa => lines.fold(0, (sum, line) => sum + line.totalPaisa);

  /// Subtotal − discount + additional charge. Never below zero: the discount is capped when set.
  int get grandTotalPaisa => subtotalPaisa - discountPaisa + chargePaisa;

  CartState copyWith({List<CartLine>? lines, int? discountPaisa, int? chargePaisa}) => CartState(
        lines: lines ?? this.lines,
        discountPaisa: discountPaisa ?? this.discountPaisa,
        chargePaisa: chargePaisa ?? this.chargePaisa,
      );
}

/// What happened when something was added, so the screen can say so.
enum CartAddResult { added, outOfStock }

/// The cart of the sale in progress. All arithmetic is in whole paisa and
/// thousandths of a unit; nothing here uses floating point.
class CartController extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  /// Adds one unit of the variant; adding it again increases the quantity.
  /// Refuses to go past the known stock unless [allowNegativeStock].
  CartAddResult add(Product product, Variant variant, {bool allowNegativeStock = false}) {
    final index = state.lines.indexWhere((line) => line.variantId == variant.id);
    final current = index == -1 ? 0 : state.lines[index].quantityMilli;
    final stock = Exact.milli(variant.stockQuantity);
    final next = current + 1000;

    if (!allowNegativeStock && next > stock) return CartAddResult.outOfStock;

    final line = CartLine(
      variantId: variant.id,
      title: variant.name == null ? product.name : '${product.name} — ${variant.name}',
      unit: product.unit,
      unitPricePaisa: Exact.paisa(variant.sellingPrice),
      quantityMilli: next,
      stockMilli: stock,
      allowsDecimal: product.unit.allowsDecimal,
    );

    final lines = [...state.lines];
    index == -1 ? lines.add(line) : lines[index] = line;
    _set(lines);
    return CartAddResult.added;
  }

  /// Sets an exact quantity (thousandths). Zero or less removes the line.
  /// Returns false when it would exceed the known stock.
  bool setQuantity(int variantId, int quantityMilli, {bool allowNegativeStock = false}) {
    final index = state.lines.indexWhere((line) => line.variantId == variantId);
    if (index == -1) return false;
    if (quantityMilli <= 0) {
      remove(variantId);
      return true;
    }

    final line = state.lines[index];
    if (!allowNegativeStock && quantityMilli > line.stockMilli) return false;

    final lines = [...state.lines]..[index] = line.withQuantity(quantityMilli);
    _set(lines);
    return true;
  }

  void remove(int variantId) => _set(state.lines.where((line) => line.variantId != variantId).toList());

  /// Returns false when the discount is larger than the subtotal.
  bool setDiscount(int paisa) {
    if (paisa < 0 || paisa > state.subtotalPaisa) return false;
    state = state.copyWith(discountPaisa: paisa);
    return true;
  }

  void setCharge(int paisa) => state = state.copyWith(chargePaisa: paisa < 0 ? 0 : paisa);

  void clear() => state = const CartState();

  void _set(List<CartLine> lines) {
    final subtotal = lines.fold(0, (sum, line) => sum + line.totalPaisa);
    // Removing items must not leave a discount bigger than what is left.
    state = state.copyWith(lines: lines, discountPaisa: state.discountPaisa > subtotal ? subtotal : state.discountPaisa);
  }
}

final cartProvider = NotifierProvider<CartController, CartState>(CartController.new);
