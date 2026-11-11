import 'dart:convert';

import 'package:dokani/features/auth/data/session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  test('parses the /me payload', () {
    final session = Session.fromJson(sessionJson());

    expect(session.user.phone, '01712345678');
    expect(session.shop.name, 'Rahim Store');
    expect(session.shop.status, ShopStatus.active);
    expect(session.role, 'owner');
    expect(session.subscription.planCode, 'free');
    expect(session.subscription.endsAt, isNull);
    expect(session.maxProducts, 50);
    expect(session.hasModule('pos'), isTrue);
    expect(session.hasModule('reports'), isFalse);
  });

  test('survives the cache round trip', () {
    final original = Session.fromJson(sessionJson(planCode: 'basic', planName: 'Basic'));
    final restored = Session.fromJson((jsonDecode(jsonEncode(original.toJson())) as Map).cast<String, dynamic>());

    expect(restored.toJson(), original.toJson());
    expect(restored.subscription.planName, 'Basic');
  });

  test('an unknown shop status is treated as not usable', () {
    expect(ShopStatus.parse('something-new'), ShopStatus.inactive);
    expect(ShopStatus.parse(null), ShopStatus.inactive);
  });

  test('permissions: owner wildcard and explicit lists', () {
    final owner = Session.fromJson(sessionJson());
    final cashier = Session.fromJson(sessionJson(role: 'cashier', permissions: ['shop.view', 'pos.sell']));

    expect(owner.can('settings.manage'), isTrue);
    expect(cashier.can('pos.sell'), isTrue);
    expect(cashier.can('settings.manage'), isFalse);
  });

  test('null limits mean unlimited', () {
    final json = sessionJson()..['limits'] = {'max_products': null, 'max_users': null};
    final session = Session.fromJson(json);

    expect(session.maxProducts, isNull);
    expect(session.maxUsers, isNull);
  });
}
