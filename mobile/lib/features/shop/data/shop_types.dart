import '../../../l10n/app_localizations.dart';

/// The shop types the server accepts (App\Enums\ShopType), in display order.
const shopTypeValues = [
  'grocery',
  'super_shop',
  'clothing',
  'cosmetics',
  'electronics',
  'pharmacy',
  'stationery',
  'hardware',
  'fruit_vegetable',
  'mobile_accessories',
  'general',
];

String shopTypeLabel(String value, AppLocalizations l10n) => switch (value) {
      'grocery' => l10n.shopTypeGrocery,
      'super_shop' => l10n.shopTypeSuperShop,
      'clothing' => l10n.shopTypeClothing,
      'cosmetics' => l10n.shopTypeCosmetics,
      'electronics' => l10n.shopTypeElectronics,
      'pharmacy' => l10n.shopTypePharmacy,
      'stationery' => l10n.shopTypeStationery,
      'hardware' => l10n.shopTypeHardware,
      'fruit_vegetable' => l10n.shopTypeFruitVegetable,
      'mobile_accessories' => l10n.shopTypeMobileAccessories,
      _ => l10n.shopTypeGeneral,
    };

/// Display name for a module key from the session; null for keys this
/// version of the app does not know (they are simply not listed).
String? moduleLabel(String key, AppLocalizations l10n) => switch (key) {
      'products' => l10n.moduleProducts,
      'pos' => l10n.modulePos,
      'customers' => l10n.moduleCustomers,
      'offline' => l10n.moduleOffline,
      'inventory' => l10n.moduleInventory,
      'vendors' => l10n.moduleVendors,
      'reports' => l10n.moduleReports,
      'exports' => l10n.moduleExports,
      'global_catalog' => l10n.moduleGlobalCatalog,
      _ => null,
    };

String roleLabel(String role, AppLocalizations l10n) => switch (role) {
      'owner' => l10n.roleOwner,
      'manager' => l10n.roleManager,
      _ => l10n.roleCashier,
    };
