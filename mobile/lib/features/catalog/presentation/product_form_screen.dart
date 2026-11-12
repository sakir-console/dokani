import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/message_banner.dart';
import '../../../core/widgets/picker_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../scanner/barcode_scan.dart';
import '../../vendors/data/vendor_repository.dart';
import '../application/catalog_providers.dart';
import '../data/catalog_repository.dart';
import '../data/models.dart';
import 'product_widgets.dart';

/// The text fields of one variant (or of the single hidden variant).
class _VariantFields {
  _VariantFields({this.id, this.existingStock, String name = '', String cost = '', String price = '', String sku = '', List<String> barcodes = const []})
      : name = TextEditingController(text: name),
        cost = TextEditingController(text: cost),
        price = TextEditingController(text: price),
        stock = TextEditingController(),
        sku = TextEditingController(text: sku),
        barcodes = [for (final code in barcodes.isEmpty ? [''] : barcodes) TextEditingController(text: code)];

  factory _VariantFields.from(Variant variant) => _VariantFields(
        id: variant.id,
        existingStock: variant.stockQuantity,
        name: variant.name ?? '',
        cost: Formatters.editable(variant.purchasePrice),
        price: Formatters.editable(variant.sellingPrice),
        sku: variant.sku ?? '',
        barcodes: variant.barcodes,
      );

  /// Set for a variant that already exists on the server.
  final int? id;
  final String? existingStock;
  final TextEditingController name;
  final TextEditingController cost;
  final TextEditingController price;
  final TextEditingController stock;
  final TextEditingController sku;
  final List<TextEditingController> barcodes;

  void dispose() {
    for (final controller in [name, cost, price, stock, sku, ...barcodes]) {
      controller.dispose();
    }
  }
}

/// Add or edit a product. With [productId] it edits; [initialBarcode]
/// pre-fills the barcode when coming from a scan of an unknown code.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.productId, this.initialBarcode});

  final int? productId;
  final String? initialBarcode;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  final _threshold = TextEditingController();
  final List<_VariantFields> _variants = [];

  NamedRef? _category;
  NamedRef? _brand;
  NamedRef? _vendor;
  Unit? _unit;
  bool _hasVariants = false;
  String? _imagePath;
  String? _existingImageUrl;

  bool _loading = false;
  Object? _loadError;
  bool _busy = false;
  String? _error;
  bool _unitMissing = false;

  bool get _editing => widget.productId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      _loading = true;
      Future.microtask(_load);
    } else {
      _variants.add(_VariantFields(barcodes: [?widget.initialBarcode]));
    }
  }

  @override
  void dispose() {
    for (final controller in [_name, _location, _description, _threshold]) {
      controller.dispose();
    }
    for (final variant in _variants) {
      variant.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final product = await ref.read(catalogRepositoryProvider).product(widget.productId!);
      if (!mounted) return;
      setState(() {
        _name.text = product.name;
        _location.text = product.storageLocation ?? '';
        _description.text = product.description ?? '';
        _threshold.text = Formatters.editable(product.lowStockThreshold);
        _category = product.category;
        _brand = product.brand;
        _vendor = product.vendor;
        _unit = product.unit;
        _hasVariants = product.hasVariants;
        _existingImageUrl = product.imageUrl;
        _variants.addAll(product.variants.map(_VariantFields.from));
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error;
          _loading = false;
        });
      }
    }
  }

  // --- Pickers -------------------------------------------------------------

  Future<void> _pickUnit() async {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final units = await _loadList(() => ref.read(unitsProvider.future));
    if (units == null || !mounted) return;

    final picked = await showPickerSheet<Unit>(
      context,
      title: l10n.unit,
      items: units,
      labelOf: (unit) => unit.label(locale),
      isSelected: (unit) => unit.id == _unit?.id,
    );
    if (picked?.value != null) {
      setState(() {
        _unit = picked!.value;
        _unitMissing = false;
      });
    }
  }

  Future<void> _pickCategory() async {
    final l10n = AppLocalizations.of(context);
    final categories = await _loadList(() => ref.read(categoriesProvider.future));
    if (categories == null || !mounted) return;

    final picked = await showPickerSheet<NamedRef>(
      context,
      title: l10n.category,
      items: [for (final category in categories) NamedRef(id: category.id, name: category.name)],
      labelOf: (item) => item.name,
      isSelected: (item) => item.id == _category?.id,
      allowNone: true,
      createLabel: l10n.addCategory,
      onCreate: () => _createNamed(
        title: l10n.addCategory,
        label: l10n.categoryName,
        create: (name) async {
          final created = await ref.read(catalogRepositoryProvider).createCategory(name);
          ref.invalidate(categoriesProvider);
          return NamedRef(id: created.id, name: created.name);
        },
      ),
    );
    if (picked != null) setState(() => _category = picked.value);
  }

  Future<void> _pickBrand() async {
    final l10n = AppLocalizations.of(context);
    final brands = await _loadList(() => ref.read(brandsProvider.future));
    if (brands == null || !mounted) return;

    final picked = await showPickerSheet<NamedRef>(
      context,
      title: l10n.brand,
      items: brands,
      labelOf: (item) => item.name,
      isSelected: (item) => item.id == _brand?.id,
      allowNone: true,
      createLabel: l10n.addBrand,
      onCreate: () => _createNamed(
        title: l10n.addBrand,
        label: l10n.brandName,
        create: (name) async {
          final created = await ref.read(catalogRepositoryProvider).createBrand(name);
          ref.invalidate(brandsProvider);
          return created;
        },
      ),
    );
    if (picked != null) setState(() => _brand = picked.value);
  }

  Future<void> _pickVendor() async {
    final l10n = AppLocalizations.of(context);
    final vendors = await _loadList(() => ref.read(vendorRepositoryProvider).vendors());
    if (vendors == null || !mounted) return;

    final picked = await showPickerSheet<NamedRef>(
      context,
      title: l10n.vendor,
      items: [for (final vendor in vendors) NamedRef(id: vendor.id, name: vendor.name)],
      labelOf: (item) => item.name,
      isSelected: (item) => item.id == _vendor?.id,
      allowNone: true,
      createLabel: l10n.addVendor,
      onCreate: () => _createNamed(
        title: l10n.addVendor,
        label: l10n.vendorName,
        create: (name) async {
          final created = await ref.read(vendorRepositoryProvider).create(VendorDraft(name: name));
          ref.invalidate(vendorsProvider);
          return NamedRef(id: created.id, name: created.name);
        },
      ),
    );
    if (picked != null) setState(() => _vendor = picked.value);
  }

  /// Loads a list for a picker; on failure explains why and returns null.
  Future<List<T>?> _loadList<T>(Future<List<T>> Function() load) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      return await load();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error, l10n))));
      return null;
    }
  }

  /// Asks for a name, creates the item, and reports a failure in place.
  Future<NamedRef?> _createNamed({
    required String title,
    required String label,
    required Future<NamedRef> Function(String name) create,
  }) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final name = await showTextInputDialog(context, title: title, label: label, confirmLabel: l10n.add);
    if (name == null) return null;

    try {
      return await create(name);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error, l10n))));
      return null;
    }
  }

  // --- Image and barcode ---------------------------------------------------

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 85);
      if (picked != null && mounted) setState(() => _imagePath = picked.path);
    } catch (_) {
      // Picker unavailable or permission denied; the photo is optional.
    }
  }

  Future<void> _scanInto(TextEditingController controller) async {
    final code = await ref.read(barcodeScanProvider)(context);
    if (code != null && mounted) setState(() => controller.text = code);
  }

  // --- Variants ------------------------------------------------------------

  void _setHasVariants(bool value) {
    setState(() {
      _hasVariants = value;
      if (!value && _variants.length > 1) {
        // Back to a single price and stock: keep the first variant only.
        for (final extra in _variants.sublist(1)) {
          extra.dispose();
        }
        _variants.removeRange(1, _variants.length);
      }
    });
  }

  void _addVariant() => setState(() => _variants.add(_VariantFields()));

  void _removeVariant(int index) => setState(() => _variants.removeAt(index).dispose());

  // --- Save ----------------------------------------------------------------

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    setState(() {
      _error = null;
      _unitMissing = _unit == null;
    });
    final fieldsValid = _formKey.currentState!.validate();
    if (!fieldsValid || _unit == null) return;

    final stockDecimals = _unit!.allowsDecimal ? 3 : 0;
    String? clean(TextEditingController controller) {
      final value = controller.text.trim();
      return value.isEmpty ? null : value;
    }

    final draft = ProductDraft(
      name: _name.text.trim(),
      unitId: _unit!.id,
      categoryId: _category?.id,
      brandId: _brand?.id,
      vendorId: _vendor?.id,
      description: clean(_description),
      storageLocation: clean(_location),
      lowStockThreshold: Formatters.parseDecimal(_threshold.text, maxDecimals: 3),
      hasVariants: _hasVariants,
      variants: [
        for (final variant in _variants)
          VariantDraft(
            id: variant.id,
            name: _hasVariants ? variant.name.text.trim() : null,
            sku: clean(variant.sku),
            // An empty purchase price means "not recorded", stored as zero.
            purchasePrice: Formatters.parseDecimal(variant.cost.text, maxDecimals: 2) ?? '0',
            sellingPrice: Formatters.parseDecimal(variant.price.text, maxDecimals: 2)!,
            openingStock: variant.id == null ? Formatters.parseDecimal(variant.stock.text, maxDecimals: stockDecimals) : null,
            barcodes: [
              for (final barcode in variant.barcodes)
                if (barcode.text.trim().isNotEmpty) barcode.text.trim(),
            ],
          ),
      ],
    );

    setState(() => _busy = true);
    try {
      final repository = ref.read(catalogRepositoryProvider);
      final saved = _editing ? await repository.updateProduct(widget.productId!, draft) : await repository.createProduct(draft);

      var photoFailed = false;
      if (_imagePath != null) {
        try {
          await repository.uploadProductImage(saved.id, _imagePath!);
        } catch (_) {
          photoFailed = true; // The product itself is saved; say so rather than failing the whole form.
        }
      }

      ref
        ..invalidate(productProvider(saved.id))
        ..invalidate(stockSummaryProvider);
      await ref.read(productListProvider.notifier).refresh();

      messenger.showSnackBar(SnackBar(content: Text(photoFailed ? l10n.photoUploadFailed : l10n.productSaved)));
      // After creating, land on the new product; after editing, go back to it.
      _editing ? router.pop() : router.pushReplacement('/products/${saved.id}');
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error, l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final hasVendors = ref.watch(sessionProvider)?.hasModule('vendors') ?? false;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_loadError != null) {
      body = Center(
        child: Padding(padding: const EdgeInsets.all(24), child: MessageBanner(message: describeError(_loadError!, l10n))),
      );
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[MessageBanner(message: _error!), const SizedBox(height: 16)],
              AppTextField(
                label: l10n.productName,
                controller: _name,
                maxLength: 190,
                textCapitalization: TextCapitalization.words,
                validator: (value) => (value == null || value.trim().isEmpty) ? l10n.errRequired : null,
              ),
              const SizedBox(height: 16),
              PickerField(
                label: l10n.unit,
                value: _unit?.label(locale),
                onTap: _pickUnit,
                errorText: _unitMissing ? l10n.errChooseUnit : null,
              ),
              const SizedBox(height: 16),
              PickerField(label: l10n.category, value: _category?.name, onTap: _pickCategory),
              const SizedBox(height: 16),
              PickerField(label: l10n.brand, value: _brand?.name, onTap: _pickBrand),
              if (hasVendors) ...[
                const SizedBox(height: 16),
                PickerField(label: l10n.vendor, value: _vendor?.name, onTap: _pickVendor),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.hasVariants, style: text.titleSmall),
                subtitle: Text(l10n.hasVariantsHint),
                value: _hasVariants,
                onChanged: _busy ? null : _setHasVariants,
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _variants.length; i++) ...[
                _variantSection(i, l10n, locale),
                const SizedBox(height: 12),
              ],
              if (_hasVariants)
                OutlinedButton.icon(onPressed: _addVariant, icon: const Icon(Icons.add), label: Text(l10n.addVariant)),
              const SizedBox(height: 20),
              AppTextField(
                label: '${l10n.storageLocation} (${l10n.optional})',
                hint: l10n.storageLocationHint,
                controller: _location,
                maxLength: 100,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: '${l10n.lowStockAlertAt} (${l10n.optional})',
                hint: l10n.lowStockAlertHint,
                controller: _threshold,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? null
                    : (Formatters.parseDecimal(value, maxDecimals: 3) == null ? l10n.errNumber : null),
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: '${l10n.description} (${l10n.optional})',
                controller: _description,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 16),
              _photoPicker(l10n, text),
              const SizedBox(height: 24),
              PrimaryButton(label: l10n.save, busy: _busy, onPressed: _save),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? l10n.editProduct : l10n.addProduct)),
      body: SafeArea(child: body),
    );
  }

  Widget _variantSection(int index, AppLocalizations l10n, String locale) {
    final variant = _variants[index];
    final text = Theme.of(context).textTheme;
    final stockDecimals = (_unit?.allowsDecimal ?? false) ? 3 : 0;

    String? money(String? value, {required bool required}) {
      if (value == null || value.trim().isEmpty) return required ? l10n.errRequired : null;
      return Formatters.parseDecimal(value, maxDecimals: 2) == null ? l10n.errNumber : null;
    }

    final cost = Formatters.parseDecimal(variant.cost.text, maxDecimals: 2);
    final price = Formatters.parseDecimal(variant.price.text, maxDecimals: 2);
    final sellingAtLoss = cost != null && price != null && Formatters.isLess(price, cost);

    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hasVariants) ...[
          Row(
            children: [
              Expanded(child: Text(l10n.variantN(index + 1), style: text.titleMedium)),
              if (_variants.length > 1)
                IconButton(
                  tooltip: l10n.removeVariant,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeVariant(index),
                ),
            ],
          ),
          AppTextField(
            label: l10n.variantName,
            hint: l10n.variantNameHint,
            controller: variant.name,
            maxLength: 120,
            validator: (value) => (value == null || value.trim().isEmpty) ? l10n.errRequired : null,
          ),
          const SizedBox(height: 16),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                label: l10n.purchasePrice,
                controller: variant.cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) => money(value, required: false),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppTextField(
                label: l10n.sellingPrice,
                controller: variant.price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) => money(value, required: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        if (sellingAtLoss) ...[
          const SizedBox(height: 8),
          MessageBanner(message: l10n.priceBelowCost, tone: BannerTone.warning),
        ],
        const SizedBox(height: 16),
        if (variant.id == null)
          AppTextField(
            label: '${l10n.openingStock} (${l10n.optional})',
            controller: variant.stock,
            keyboardType: TextInputType.numberWithOptions(decimal: stockDecimals > 0),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? null
                : (Formatters.parseDecimal(value, maxDecimals: stockDecimals) == null
                    ? (stockDecimals == 0 ? l10n.errWholeNumber : l10n.errNumber)
                    : null),
          )
        else
          // Existing stock changes through Stock in / Stock out / Correct stock, which keep a history.
          Text(
            l10n.currentStock(_unit == null ? Formatters.quantity(variant.existingStock!, locale) : stockLabel(variant.existingStock!, _unit!, locale)),
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
        const SizedBox(height: 16),
        for (var b = 0; b < variant.barcodes.length; b++) ...[
          AppTextField(
            label: b == 0 ? '${l10n.barcode} (${l10n.optional})' : '${l10n.barcode} ${b + 1}',
            controller: variant.barcodes[b],
            maxLength: 64,
            keyboardType: TextInputType.visiblePassword,
            suffixIcon: IconButton(
              tooltip: l10n.scanBarcode,
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () => _scanInto(variant.barcodes[b]),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: variant.barcodes.length >= 10
                ? null
                : () => setState(() => variant.barcodes.add(TextEditingController())),
            icon: const Icon(Icons.add, size: 20),
            label: Text(l10n.addBarcode),
          ),
        ),
        AppTextField(label: '${l10n.sku} (${l10n.optional})', controller: variant.sku, maxLength: 64),
      ],
    );

    // A product without variants shows its fields inline; variants are boxed so each one reads as a unit.
    if (!_hasVariants) return fields;

    return Card(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), child: fields));
  }

  Widget _photoPicker(AppLocalizations l10n, TextTheme text) {
    final hasPhoto = _imagePath != null || _existingImageUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('${l10n.productPhoto} (${l10n.optional})', style: text.titleSmall),
        ),
        Row(
          children: [
            if (_imagePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(_imagePath!), width: 72, height: 72, fit: BoxFit.cover, cacheWidth: 216),
              )
            else if (_existingImageUrl != null)
              ProductThumb(name: _name.text, imageUrl: _existingImageUrl, size: 72),
            if (hasPhoto) const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _pickImage,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(hasPhoto ? l10n.changeLogo : l10n.choosePhoto),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
