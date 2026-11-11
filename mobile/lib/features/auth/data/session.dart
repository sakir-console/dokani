/// Models for the `/me` payload: who is signed in, to which shop, and what
/// the shop's plan allows. Plain immutable classes with hand-written JSON —
/// the shapes are small and this avoids a code-generation step.
library;

class AppUser {
  const AppUser({required this.id, required this.name, required this.phone, this.locale = 'bn'});

  final int id;
  final String name;
  final String phone;
  final String locale;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as int,
        name: json['name'] as String,
        phone: json['phone'] as String,
        locale: json['locale'] as String? ?? 'bn',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone, 'locale': locale};
}

enum ShopStatus {
  active,
  inactive,
  suspended;

  static ShopStatus parse(String? value) =>
      ShopStatus.values.firstWhere((s) => s.name == value, orElse: () => ShopStatus.inactive);
}

class Shop {
  const Shop({
    required this.id,
    required this.name,
    required this.shopType,
    required this.phone,
    required this.status,
    this.address,
    this.logoUrl,
    this.currency = 'BDT',
    this.timezone = 'Asia/Dhaka',
  });

  final int id;
  final String name;
  final String shopType;
  final String phone;
  final String? address;
  final String? logoUrl;
  final ShopStatus status;
  final String currency;
  final String timezone;

  factory Shop.fromJson(Map<String, dynamic> json) => Shop(
        id: json['id'] as int,
        name: json['name'] as String,
        shopType: json['shop_type'] as String,
        phone: json['phone'] as String,
        address: json['address'] as String?,
        logoUrl: json['logo_url'] as String?,
        status: ShopStatus.parse(json['status'] as String?),
        currency: json['currency'] as String? ?? 'BDT',
        timezone: json['timezone'] as String? ?? 'Asia/Dhaka',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'shop_type': shopType,
        'phone': phone,
        'address': address,
        'logo_url': logoUrl,
        'status': status.name,
        'currency': currency,
        'timezone': timezone,
      };
}

class SubscriptionInfo {
  const SubscriptionInfo({required this.planCode, required this.planName, this.endsAt, this.isFallback = false});

  final String planCode;
  final String planName;
  final DateTime? endsAt;

  /// True when a paid plan lapsed and the shop is back on the free plan.
  final bool isFallback;

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    final plan = (json['plan'] as Map).cast<String, dynamic>();
    final endsAt = json['ends_at'] as String?;
    return SubscriptionInfo(
      planCode: plan['code'] as String,
      planName: plan['name'] as String,
      endsAt: endsAt == null ? null : DateTime.tryParse(endsAt),
      isFallback: json['is_fallback'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'plan': {'code': planCode, 'name': planName},
        'ends_at': endsAt?.toIso8601String(),
        'is_fallback': isFallback,
      };
}

class Session {
  const Session({
    required this.user,
    required this.shop,
    required this.role,
    required this.permissions,
    required this.subscription,
    required this.modules,
    this.maxProducts,
    this.maxUsers,
    this.settings = const {},
  });

  final AppUser user;
  final Shop shop;
  final String role;
  final List<String> permissions;
  final SubscriptionInfo subscription;
  final List<String> modules;

  /// Null means unlimited.
  final int? maxProducts;
  final int? maxUsers;
  final Map<String, dynamic> settings;

  /// For deciding what to show. The server checks again on every request.
  bool can(String permission) => permissions.contains('*') || permissions.contains(permission);
  bool hasModule(String key) => modules.contains(key);

  Session copyWith({Shop? shop, AppUser? user}) => Session(
        user: user ?? this.user,
        shop: shop ?? this.shop,
        role: role,
        permissions: permissions,
        subscription: subscription,
        modules: modules,
        maxProducts: maxProducts,
        maxUsers: maxUsers,
        settings: settings,
      );

  factory Session.fromJson(Map<String, dynamic> json) {
    final limits = (json['limits'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Session(
      user: AppUser.fromJson((json['user'] as Map).cast<String, dynamic>()),
      shop: Shop.fromJson((json['shop'] as Map).cast<String, dynamic>()),
      role: json['role'] as String? ?? 'cashier',
      permissions: (json['permissions'] as List? ?? const []).map((e) => '$e').toList(),
      subscription: SubscriptionInfo.fromJson((json['subscription'] as Map).cast<String, dynamic>()),
      modules: (json['modules'] as List? ?? const []).map((e) => '$e').toList(),
      maxProducts: limits['max_products'] as int?,
      maxUsers: limits['max_users'] as int?,
      settings: (json['settings'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'shop': shop.toJson(),
        'role': role,
        'permissions': permissions,
        'subscription': subscription.toJson(),
        'modules': modules,
        'limits': {'max_products': maxProducts, 'max_users': maxUsers},
        'settings': settings,
      };
}
