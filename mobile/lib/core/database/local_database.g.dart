// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class $CachedProductsTable extends CachedProducts
    with TableInfo<$CachedProductsTable, CachedProduct> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _searchNameMeta = const VerificationMeta(
    'searchName',
  );
  @override
  late final GeneratedColumn<String> searchName = GeneratedColumn<String>(
    'search_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, searchName, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_products';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedProduct> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('search_name')) {
      context.handle(
        _searchNameMeta,
        searchName.isAcceptableOrUnknown(data['search_name']!, _searchNameMeta),
      );
    } else if (isInserting) {
      context.missing(_searchNameMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedProduct map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedProduct(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      searchName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}search_name'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
    );
  }

  @override
  $CachedProductsTable createAlias(String alias) {
    return $CachedProductsTable(attachedDatabase, alias);
  }
}

class CachedProduct extends DataClass implements Insertable<CachedProduct> {
  final int id;
  final String searchName;
  final String json;
  const CachedProduct({
    required this.id,
    required this.searchName,
    required this.json,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['search_name'] = Variable<String>(searchName);
    map['json'] = Variable<String>(json);
    return map;
  }

  CachedProductsCompanion toCompanion(bool nullToAbsent) {
    return CachedProductsCompanion(
      id: Value(id),
      searchName: Value(searchName),
      json: Value(json),
    );
  }

  factory CachedProduct.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedProduct(
      id: serializer.fromJson<int>(json['id']),
      searchName: serializer.fromJson<String>(json['searchName']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'searchName': serializer.toJson<String>(searchName),
      'json': serializer.toJson<String>(json),
    };
  }

  CachedProduct copyWith({int? id, String? searchName, String? json}) =>
      CachedProduct(
        id: id ?? this.id,
        searchName: searchName ?? this.searchName,
        json: json ?? this.json,
      );
  CachedProduct copyWithCompanion(CachedProductsCompanion data) {
    return CachedProduct(
      id: data.id.present ? data.id.value : this.id,
      searchName: data.searchName.present
          ? data.searchName.value
          : this.searchName,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedProduct(')
          ..write('id: $id, ')
          ..write('searchName: $searchName, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, searchName, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedProduct &&
          other.id == this.id &&
          other.searchName == this.searchName &&
          other.json == this.json);
}

class CachedProductsCompanion extends UpdateCompanion<CachedProduct> {
  final Value<int> id;
  final Value<String> searchName;
  final Value<String> json;
  const CachedProductsCompanion({
    this.id = const Value.absent(),
    this.searchName = const Value.absent(),
    this.json = const Value.absent(),
  });
  CachedProductsCompanion.insert({
    this.id = const Value.absent(),
    required String searchName,
    required String json,
  }) : searchName = Value(searchName),
       json = Value(json);
  static Insertable<CachedProduct> custom({
    Expression<int>? id,
    Expression<String>? searchName,
    Expression<String>? json,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (searchName != null) 'search_name': searchName,
      if (json != null) 'json': json,
    });
  }

  CachedProductsCompanion copyWith({
    Value<int>? id,
    Value<String>? searchName,
    Value<String>? json,
  }) {
    return CachedProductsCompanion(
      id: id ?? this.id,
      searchName: searchName ?? this.searchName,
      json: json ?? this.json,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (searchName.present) {
      map['search_name'] = Variable<String>(searchName.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedProductsCompanion(')
          ..write('id: $id, ')
          ..write('searchName: $searchName, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }
}

class $CachedBarcodesTable extends CachedBarcodes
    with TableInfo<$CachedBarcodesTable, CachedBarcode> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedBarcodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _variantIdMeta = const VerificationMeta(
    'variantId',
  );
  @override
  late final GeneratedColumn<int> variantId = GeneratedColumn<int>(
    'variant_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<int> productId = GeneratedColumn<int>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [code, variantId, productId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_barcodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedBarcode> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('variant_id')) {
      context.handle(
        _variantIdMeta,
        variantId.isAcceptableOrUnknown(data['variant_id']!, _variantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_variantIdMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {code};
  @override
  CachedBarcode map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedBarcode(
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      variantId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}variant_id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}product_id'],
      )!,
    );
  }

  @override
  $CachedBarcodesTable createAlias(String alias) {
    return $CachedBarcodesTable(attachedDatabase, alias);
  }
}

class CachedBarcode extends DataClass implements Insertable<CachedBarcode> {
  final String code;
  final int variantId;
  final int productId;
  const CachedBarcode({
    required this.code,
    required this.variantId,
    required this.productId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['code'] = Variable<String>(code);
    map['variant_id'] = Variable<int>(variantId);
    map['product_id'] = Variable<int>(productId);
    return map;
  }

  CachedBarcodesCompanion toCompanion(bool nullToAbsent) {
    return CachedBarcodesCompanion(
      code: Value(code),
      variantId: Value(variantId),
      productId: Value(productId),
    );
  }

  factory CachedBarcode.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedBarcode(
      code: serializer.fromJson<String>(json['code']),
      variantId: serializer.fromJson<int>(json['variantId']),
      productId: serializer.fromJson<int>(json['productId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'code': serializer.toJson<String>(code),
      'variantId': serializer.toJson<int>(variantId),
      'productId': serializer.toJson<int>(productId),
    };
  }

  CachedBarcode copyWith({String? code, int? variantId, int? productId}) =>
      CachedBarcode(
        code: code ?? this.code,
        variantId: variantId ?? this.variantId,
        productId: productId ?? this.productId,
      );
  CachedBarcode copyWithCompanion(CachedBarcodesCompanion data) {
    return CachedBarcode(
      code: data.code.present ? data.code.value : this.code,
      variantId: data.variantId.present ? data.variantId.value : this.variantId,
      productId: data.productId.present ? data.productId.value : this.productId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedBarcode(')
          ..write('code: $code, ')
          ..write('variantId: $variantId, ')
          ..write('productId: $productId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(code, variantId, productId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedBarcode &&
          other.code == this.code &&
          other.variantId == this.variantId &&
          other.productId == this.productId);
}

class CachedBarcodesCompanion extends UpdateCompanion<CachedBarcode> {
  final Value<String> code;
  final Value<int> variantId;
  final Value<int> productId;
  final Value<int> rowid;
  const CachedBarcodesCompanion({
    this.code = const Value.absent(),
    this.variantId = const Value.absent(),
    this.productId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedBarcodesCompanion.insert({
    required String code,
    required int variantId,
    required int productId,
    this.rowid = const Value.absent(),
  }) : code = Value(code),
       variantId = Value(variantId),
       productId = Value(productId);
  static Insertable<CachedBarcode> custom({
    Expression<String>? code,
    Expression<int>? variantId,
    Expression<int>? productId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (code != null) 'code': code,
      if (variantId != null) 'variant_id': variantId,
      if (productId != null) 'product_id': productId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedBarcodesCompanion copyWith({
    Value<String>? code,
    Value<int>? variantId,
    Value<int>? productId,
    Value<int>? rowid,
  }) {
    return CachedBarcodesCompanion(
      code: code ?? this.code,
      variantId: variantId ?? this.variantId,
      productId: productId ?? this.productId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (variantId.present) {
      map['variant_id'] = Variable<int>(variantId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<int>(productId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedBarcodesCompanion(')
          ..write('code: $code, ')
          ..write('variantId: $variantId, ')
          ..write('productId: $productId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedCustomersTable extends CachedCustomers
    with TableInfo<$CachedCustomersTable, CachedCustomer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedCustomersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _searchNameMeta = const VerificationMeta(
    'searchName',
  );
  @override
  late final GeneratedColumn<String> searchName = GeneratedColumn<String>(
    'search_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, phone, searchName, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_customers';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedCustomer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    } else if (isInserting) {
      context.missing(_phoneMeta);
    }
    if (data.containsKey('search_name')) {
      context.handle(
        _searchNameMeta,
        searchName.isAcceptableOrUnknown(data['search_name']!, _searchNameMeta),
      );
    } else if (isInserting) {
      context.missing(_searchNameMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedCustomer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedCustomer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      )!,
      searchName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}search_name'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
    );
  }

  @override
  $CachedCustomersTable createAlias(String alias) {
    return $CachedCustomersTable(attachedDatabase, alias);
  }
}

class CachedCustomer extends DataClass implements Insertable<CachedCustomer> {
  final int id;
  final String phone;
  final String searchName;
  final String json;
  const CachedCustomer({
    required this.id,
    required this.phone,
    required this.searchName,
    required this.json,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['phone'] = Variable<String>(phone);
    map['search_name'] = Variable<String>(searchName);
    map['json'] = Variable<String>(json);
    return map;
  }

  CachedCustomersCompanion toCompanion(bool nullToAbsent) {
    return CachedCustomersCompanion(
      id: Value(id),
      phone: Value(phone),
      searchName: Value(searchName),
      json: Value(json),
    );
  }

  factory CachedCustomer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedCustomer(
      id: serializer.fromJson<int>(json['id']),
      phone: serializer.fromJson<String>(json['phone']),
      searchName: serializer.fromJson<String>(json['searchName']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'phone': serializer.toJson<String>(phone),
      'searchName': serializer.toJson<String>(searchName),
      'json': serializer.toJson<String>(json),
    };
  }

  CachedCustomer copyWith({
    int? id,
    String? phone,
    String? searchName,
    String? json,
  }) => CachedCustomer(
    id: id ?? this.id,
    phone: phone ?? this.phone,
    searchName: searchName ?? this.searchName,
    json: json ?? this.json,
  );
  CachedCustomer copyWithCompanion(CachedCustomersCompanion data) {
    return CachedCustomer(
      id: data.id.present ? data.id.value : this.id,
      phone: data.phone.present ? data.phone.value : this.phone,
      searchName: data.searchName.present
          ? data.searchName.value
          : this.searchName,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedCustomer(')
          ..write('id: $id, ')
          ..write('phone: $phone, ')
          ..write('searchName: $searchName, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, phone, searchName, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedCustomer &&
          other.id == this.id &&
          other.phone == this.phone &&
          other.searchName == this.searchName &&
          other.json == this.json);
}

class CachedCustomersCompanion extends UpdateCompanion<CachedCustomer> {
  final Value<int> id;
  final Value<String> phone;
  final Value<String> searchName;
  final Value<String> json;
  const CachedCustomersCompanion({
    this.id = const Value.absent(),
    this.phone = const Value.absent(),
    this.searchName = const Value.absent(),
    this.json = const Value.absent(),
  });
  CachedCustomersCompanion.insert({
    this.id = const Value.absent(),
    required String phone,
    required String searchName,
    required String json,
  }) : phone = Value(phone),
       searchName = Value(searchName),
       json = Value(json);
  static Insertable<CachedCustomer> custom({
    Expression<int>? id,
    Expression<String>? phone,
    Expression<String>? searchName,
    Expression<String>? json,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (phone != null) 'phone': phone,
      if (searchName != null) 'search_name': searchName,
      if (json != null) 'json': json,
    });
  }

  CachedCustomersCompanion copyWith({
    Value<int>? id,
    Value<String>? phone,
    Value<String>? searchName,
    Value<String>? json,
  }) {
    return CachedCustomersCompanion(
      id: id ?? this.id,
      phone: phone ?? this.phone,
      searchName: searchName ?? this.searchName,
      json: json ?? this.json,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (searchName.present) {
      map['search_name'] = Variable<String>(searchName.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedCustomersCompanion(')
          ..write('id: $id, ')
          ..write('phone: $phone, ')
          ..write('searchName: $searchName, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }
}

class $OutboxEntriesTable extends OutboxEntries
    with TableInfo<$OutboxEntriesTable, OutboxEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _clientUuidMeta = const VerificationMeta(
    'clientUuid',
  );
  @override
  late final GeneratedColumn<String> clientUuid = GeneratedColumn<String>(
    'client_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayMeta = const VerificationMeta(
    'display',
  );
  @override
  late final GeneratedColumn<String> display = GeneratedColumn<String>(
    'display',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverMeta = const VerificationMeta('server');
  @override
  late final GeneratedColumn<String> server = GeneratedColumn<String>(
    'server',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clientUuid,
    kind,
    payload,
    display,
    status,
    errorCode,
    errorMessage,
    attempts,
    createdAt,
    server,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('client_uuid')) {
      context.handle(
        _clientUuidMeta,
        clientUuid.isAcceptableOrUnknown(data['client_uuid']!, _clientUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_clientUuidMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('display')) {
      context.handle(
        _displayMeta,
        display.isAcceptableOrUnknown(data['display']!, _displayMeta),
      );
    } else if (isInserting) {
      context.missing(_displayMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('server')) {
      context.handle(
        _serverMeta,
        server.isAcceptableOrUnknown(data['server']!, _serverMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      clientUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_uuid'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      display: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      server: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server'],
      ),
    );
  }

  @override
  $OutboxEntriesTable createAlias(String alias) {
    return $OutboxEntriesTable(attachedDatabase, alias);
  }
}

class OutboxEntry extends DataClass implements Insertable<OutboxEntry> {
  final int id;

  /// The id the server uses to recognise a repeat of the same record.
  final String clientUuid;

  /// 'sale' or 'due_collection'
  final String kind;

  /// The request body, exactly as it will be sent.
  final String payload;

  /// What is needed to show the record on the phone before it is synced
  /// (product names, customer name), which the request body does not carry.
  final String display;

  /// 'pending', 'synced' or 'failed'
  final String status;
  final String? errorCode;
  final String? errorMessage;
  final int attempts;
  final DateTime createdAt;

  /// The server's answer once synced (id, invoice number, invoice link).
  final String? server;
  const OutboxEntry({
    required this.id,
    required this.clientUuid,
    required this.kind,
    required this.payload,
    required this.display,
    required this.status,
    this.errorCode,
    this.errorMessage,
    required this.attempts,
    required this.createdAt,
    this.server,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['client_uuid'] = Variable<String>(clientUuid);
    map['kind'] = Variable<String>(kind);
    map['payload'] = Variable<String>(payload);
    map['display'] = Variable<String>(display);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    map['attempts'] = Variable<int>(attempts);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || server != null) {
      map['server'] = Variable<String>(server);
    }
    return map;
  }

  OutboxEntriesCompanion toCompanion(bool nullToAbsent) {
    return OutboxEntriesCompanion(
      id: Value(id),
      clientUuid: Value(clientUuid),
      kind: Value(kind),
      payload: Value(payload),
      display: Value(display),
      status: Value(status),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      attempts: Value(attempts),
      createdAt: Value(createdAt),
      server: server == null && nullToAbsent
          ? const Value.absent()
          : Value(server),
    );
  }

  factory OutboxEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxEntry(
      id: serializer.fromJson<int>(json['id']),
      clientUuid: serializer.fromJson<String>(json['clientUuid']),
      kind: serializer.fromJson<String>(json['kind']),
      payload: serializer.fromJson<String>(json['payload']),
      display: serializer.fromJson<String>(json['display']),
      status: serializer.fromJson<String>(json['status']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      attempts: serializer.fromJson<int>(json['attempts']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      server: serializer.fromJson<String?>(json['server']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'clientUuid': serializer.toJson<String>(clientUuid),
      'kind': serializer.toJson<String>(kind),
      'payload': serializer.toJson<String>(payload),
      'display': serializer.toJson<String>(display),
      'status': serializer.toJson<String>(status),
      'errorCode': serializer.toJson<String?>(errorCode),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'attempts': serializer.toJson<int>(attempts),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'server': serializer.toJson<String?>(server),
    };
  }

  OutboxEntry copyWith({
    int? id,
    String? clientUuid,
    String? kind,
    String? payload,
    String? display,
    String? status,
    Value<String?> errorCode = const Value.absent(),
    Value<String?> errorMessage = const Value.absent(),
    int? attempts,
    DateTime? createdAt,
    Value<String?> server = const Value.absent(),
  }) => OutboxEntry(
    id: id ?? this.id,
    clientUuid: clientUuid ?? this.clientUuid,
    kind: kind ?? this.kind,
    payload: payload ?? this.payload,
    display: display ?? this.display,
    status: status ?? this.status,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    attempts: attempts ?? this.attempts,
    createdAt: createdAt ?? this.createdAt,
    server: server.present ? server.value : this.server,
  );
  OutboxEntry copyWithCompanion(OutboxEntriesCompanion data) {
    return OutboxEntry(
      id: data.id.present ? data.id.value : this.id,
      clientUuid: data.clientUuid.present
          ? data.clientUuid.value
          : this.clientUuid,
      kind: data.kind.present ? data.kind.value : this.kind,
      payload: data.payload.present ? data.payload.value : this.payload,
      display: data.display.present ? data.display.value : this.display,
      status: data.status.present ? data.status.value : this.status,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      server: data.server.present ? data.server.value : this.server,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEntry(')
          ..write('id: $id, ')
          ..write('clientUuid: $clientUuid, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('display: $display, ')
          ..write('status: $status, ')
          ..write('errorCode: $errorCode, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('attempts: $attempts, ')
          ..write('createdAt: $createdAt, ')
          ..write('server: $server')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    clientUuid,
    kind,
    payload,
    display,
    status,
    errorCode,
    errorMessage,
    attempts,
    createdAt,
    server,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxEntry &&
          other.id == this.id &&
          other.clientUuid == this.clientUuid &&
          other.kind == this.kind &&
          other.payload == this.payload &&
          other.display == this.display &&
          other.status == this.status &&
          other.errorCode == this.errorCode &&
          other.errorMessage == this.errorMessage &&
          other.attempts == this.attempts &&
          other.createdAt == this.createdAt &&
          other.server == this.server);
}

class OutboxEntriesCompanion extends UpdateCompanion<OutboxEntry> {
  final Value<int> id;
  final Value<String> clientUuid;
  final Value<String> kind;
  final Value<String> payload;
  final Value<String> display;
  final Value<String> status;
  final Value<String?> errorCode;
  final Value<String?> errorMessage;
  final Value<int> attempts;
  final Value<DateTime> createdAt;
  final Value<String?> server;
  const OutboxEntriesCompanion({
    this.id = const Value.absent(),
    this.clientUuid = const Value.absent(),
    this.kind = const Value.absent(),
    this.payload = const Value.absent(),
    this.display = const Value.absent(),
    this.status = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.attempts = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.server = const Value.absent(),
  });
  OutboxEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String clientUuid,
    required String kind,
    required String payload,
    required String display,
    this.status = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.attempts = const Value.absent(),
    required DateTime createdAt,
    this.server = const Value.absent(),
  }) : clientUuid = Value(clientUuid),
       kind = Value(kind),
       payload = Value(payload),
       display = Value(display),
       createdAt = Value(createdAt);
  static Insertable<OutboxEntry> custom({
    Expression<int>? id,
    Expression<String>? clientUuid,
    Expression<String>? kind,
    Expression<String>? payload,
    Expression<String>? display,
    Expression<String>? status,
    Expression<String>? errorCode,
    Expression<String>? errorMessage,
    Expression<int>? attempts,
    Expression<DateTime>? createdAt,
    Expression<String>? server,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clientUuid != null) 'client_uuid': clientUuid,
      if (kind != null) 'kind': kind,
      if (payload != null) 'payload': payload,
      if (display != null) 'display': display,
      if (status != null) 'status': status,
      if (errorCode != null) 'error_code': errorCode,
      if (errorMessage != null) 'error_message': errorMessage,
      if (attempts != null) 'attempts': attempts,
      if (createdAt != null) 'created_at': createdAt,
      if (server != null) 'server': server,
    });
  }

  OutboxEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? clientUuid,
    Value<String>? kind,
    Value<String>? payload,
    Value<String>? display,
    Value<String>? status,
    Value<String?>? errorCode,
    Value<String?>? errorMessage,
    Value<int>? attempts,
    Value<DateTime>? createdAt,
    Value<String?>? server,
  }) {
    return OutboxEntriesCompanion(
      id: id ?? this.id,
      clientUuid: clientUuid ?? this.clientUuid,
      kind: kind ?? this.kind,
      payload: payload ?? this.payload,
      display: display ?? this.display,
      status: status ?? this.status,
      errorCode: errorCode ?? this.errorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      attempts: attempts ?? this.attempts,
      createdAt: createdAt ?? this.createdAt,
      server: server ?? this.server,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (clientUuid.present) {
      map['client_uuid'] = Variable<String>(clientUuid.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (display.present) {
      map['display'] = Variable<String>(display.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (server.present) {
      map['server'] = Variable<String>(server.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEntriesCompanion(')
          ..write('id: $id, ')
          ..write('clientUuid: $clientUuid, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('display: $display, ')
          ..write('status: $status, ')
          ..write('errorCode: $errorCode, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('attempts: $attempts, ')
          ..write('createdAt: $createdAt, ')
          ..write('server: $server')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateData extends DataClass implements Insertable<SyncStateData> {
  final String key;
  final String value;
  const SyncStateData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(key: Value(key), value: Value(value));
  }

  factory SyncStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SyncStateData copyWith({String? key, String? value}) =>
      SyncStateData(key: key ?? this.key, value: value ?? this.value);
  SyncStateData copyWithCompanion(SyncStateCompanion data) {
    return SyncStateData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateData &&
          other.key == this.key &&
          other.value == this.value);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SyncStateCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStateCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SyncStateData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStateCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SyncStateCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDatabase extends GeneratedDatabase {
  _$LocalDatabase(QueryExecutor e) : super(e);
  $LocalDatabaseManager get managers => $LocalDatabaseManager(this);
  late final $CachedProductsTable cachedProducts = $CachedProductsTable(this);
  late final $CachedBarcodesTable cachedBarcodes = $CachedBarcodesTable(this);
  late final $CachedCustomersTable cachedCustomers = $CachedCustomersTable(
    this,
  );
  late final $OutboxEntriesTable outboxEntries = $OutboxEntriesTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedProducts,
    cachedBarcodes,
    cachedCustomers,
    outboxEntries,
    syncState,
  ];
}

typedef $$CachedProductsTableCreateCompanionBuilder =
    CachedProductsCompanion Function({
      Value<int> id,
      required String searchName,
      required String json,
    });
typedef $$CachedProductsTableUpdateCompanionBuilder =
    CachedProductsCompanion Function({
      Value<int> id,
      Value<String> searchName,
      Value<String> json,
    });

class $$CachedProductsTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedProductsTable> {
  $$CachedProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get searchName => $composableBuilder(
    column: $table.searchName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedProductsTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedProductsTable> {
  $$CachedProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get searchName => $composableBuilder(
    column: $table.searchName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedProductsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedProductsTable> {
  $$CachedProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get searchName => $composableBuilder(
    column: $table.searchName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$CachedProductsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedProductsTable,
          CachedProduct,
          $$CachedProductsTableFilterComposer,
          $$CachedProductsTableOrderingComposer,
          $$CachedProductsTableAnnotationComposer,
          $$CachedProductsTableCreateCompanionBuilder,
          $$CachedProductsTableUpdateCompanionBuilder,
          (
            CachedProduct,
            BaseReferences<
              _$LocalDatabase,
              $CachedProductsTable,
              CachedProduct
            >,
          ),
          CachedProduct,
          PrefetchHooks Function()
        > {
  $$CachedProductsTableTableManager(
    _$LocalDatabase db,
    $CachedProductsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> searchName = const Value.absent(),
                Value<String> json = const Value.absent(),
              }) => CachedProductsCompanion(
                id: id,
                searchName: searchName,
                json: json,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String searchName,
                required String json,
              }) => CachedProductsCompanion.insert(
                id: id,
                searchName: searchName,
                json: json,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedProductsTable, CachedProduct>(table),
                  BaseReferences<
                    _$LocalDatabase,
                    $CachedProductsTable,
                    CachedProduct
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedProductsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedProductsTable,
      CachedProduct,
      $$CachedProductsTableFilterComposer,
      $$CachedProductsTableOrderingComposer,
      $$CachedProductsTableAnnotationComposer,
      $$CachedProductsTableCreateCompanionBuilder,
      $$CachedProductsTableUpdateCompanionBuilder,
      (
        CachedProduct,
        BaseReferences<_$LocalDatabase, $CachedProductsTable, CachedProduct>,
      ),
      CachedProduct,
      PrefetchHooks Function()
    >;
typedef $$CachedBarcodesTableCreateCompanionBuilder =
    CachedBarcodesCompanion Function({
      required String code,
      required int variantId,
      required int productId,
      Value<int> rowid,
    });
typedef $$CachedBarcodesTableUpdateCompanionBuilder =
    CachedBarcodesCompanion Function({
      Value<String> code,
      Value<int> variantId,
      Value<int> productId,
      Value<int> rowid,
    });

class $$CachedBarcodesTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedBarcodesTable> {
  $$CachedBarcodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get variantId => $composableBuilder(
    column: $table.variantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedBarcodesTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedBarcodesTable> {
  $$CachedBarcodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get variantId => $composableBuilder(
    column: $table.variantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedBarcodesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedBarcodesTable> {
  $$CachedBarcodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<int> get variantId =>
      $composableBuilder(column: $table.variantId, builder: (column) => column);

  GeneratedColumn<int> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);
}

class $$CachedBarcodesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedBarcodesTable,
          CachedBarcode,
          $$CachedBarcodesTableFilterComposer,
          $$CachedBarcodesTableOrderingComposer,
          $$CachedBarcodesTableAnnotationComposer,
          $$CachedBarcodesTableCreateCompanionBuilder,
          $$CachedBarcodesTableUpdateCompanionBuilder,
          (
            CachedBarcode,
            BaseReferences<
              _$LocalDatabase,
              $CachedBarcodesTable,
              CachedBarcode
            >,
          ),
          CachedBarcode,
          PrefetchHooks Function()
        > {
  $$CachedBarcodesTableTableManager(
    _$LocalDatabase db,
    $CachedBarcodesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedBarcodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedBarcodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedBarcodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> code = const Value.absent(),
                Value<int> variantId = const Value.absent(),
                Value<int> productId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedBarcodesCompanion(
                code: code,
                variantId: variantId,
                productId: productId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String code,
                required int variantId,
                required int productId,
                Value<int> rowid = const Value.absent(),
              }) => CachedBarcodesCompanion.insert(
                code: code,
                variantId: variantId,
                productId: productId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedBarcodesTable, CachedBarcode>(table),
                  BaseReferences<
                    _$LocalDatabase,
                    $CachedBarcodesTable,
                    CachedBarcode
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedBarcodesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedBarcodesTable,
      CachedBarcode,
      $$CachedBarcodesTableFilterComposer,
      $$CachedBarcodesTableOrderingComposer,
      $$CachedBarcodesTableAnnotationComposer,
      $$CachedBarcodesTableCreateCompanionBuilder,
      $$CachedBarcodesTableUpdateCompanionBuilder,
      (
        CachedBarcode,
        BaseReferences<_$LocalDatabase, $CachedBarcodesTable, CachedBarcode>,
      ),
      CachedBarcode,
      PrefetchHooks Function()
    >;
typedef $$CachedCustomersTableCreateCompanionBuilder =
    CachedCustomersCompanion Function({
      Value<int> id,
      required String phone,
      required String searchName,
      required String json,
    });
typedef $$CachedCustomersTableUpdateCompanionBuilder =
    CachedCustomersCompanion Function({
      Value<int> id,
      Value<String> phone,
      Value<String> searchName,
      Value<String> json,
    });

class $$CachedCustomersTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedCustomersTable> {
  $$CachedCustomersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get searchName => $composableBuilder(
    column: $table.searchName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedCustomersTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedCustomersTable> {
  $$CachedCustomersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get searchName => $composableBuilder(
    column: $table.searchName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedCustomersTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedCustomersTable> {
  $$CachedCustomersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get searchName => $composableBuilder(
    column: $table.searchName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$CachedCustomersTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedCustomersTable,
          CachedCustomer,
          $$CachedCustomersTableFilterComposer,
          $$CachedCustomersTableOrderingComposer,
          $$CachedCustomersTableAnnotationComposer,
          $$CachedCustomersTableCreateCompanionBuilder,
          $$CachedCustomersTableUpdateCompanionBuilder,
          (
            CachedCustomer,
            BaseReferences<
              _$LocalDatabase,
              $CachedCustomersTable,
              CachedCustomer
            >,
          ),
          CachedCustomer,
          PrefetchHooks Function()
        > {
  $$CachedCustomersTableTableManager(
    _$LocalDatabase db,
    $CachedCustomersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedCustomersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedCustomersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedCustomersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> phone = const Value.absent(),
                Value<String> searchName = const Value.absent(),
                Value<String> json = const Value.absent(),
              }) => CachedCustomersCompanion(
                id: id,
                phone: phone,
                searchName: searchName,
                json: json,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String phone,
                required String searchName,
                required String json,
              }) => CachedCustomersCompanion.insert(
                id: id,
                phone: phone,
                searchName: searchName,
                json: json,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedCustomersTable, CachedCustomer>(table),
                  BaseReferences<
                    _$LocalDatabase,
                    $CachedCustomersTable,
                    CachedCustomer
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedCustomersTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedCustomersTable,
      CachedCustomer,
      $$CachedCustomersTableFilterComposer,
      $$CachedCustomersTableOrderingComposer,
      $$CachedCustomersTableAnnotationComposer,
      $$CachedCustomersTableCreateCompanionBuilder,
      $$CachedCustomersTableUpdateCompanionBuilder,
      (
        CachedCustomer,
        BaseReferences<_$LocalDatabase, $CachedCustomersTable, CachedCustomer>,
      ),
      CachedCustomer,
      PrefetchHooks Function()
    >;
typedef $$OutboxEntriesTableCreateCompanionBuilder =
    OutboxEntriesCompanion Function({
      Value<int> id,
      required String clientUuid,
      required String kind,
      required String payload,
      required String display,
      Value<String> status,
      Value<String?> errorCode,
      Value<String?> errorMessage,
      Value<int> attempts,
      required DateTime createdAt,
      Value<String?> server,
    });
typedef $$OutboxEntriesTableUpdateCompanionBuilder =
    OutboxEntriesCompanion Function({
      Value<int> id,
      Value<String> clientUuid,
      Value<String> kind,
      Value<String> payload,
      Value<String> display,
      Value<String> status,
      Value<String?> errorCode,
      Value<String?> errorMessage,
      Value<int> attempts,
      Value<DateTime> createdAt,
      Value<String?> server,
    });

class $$OutboxEntriesTableFilterComposer
    extends Composer<_$LocalDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientUuid => $composableBuilder(
    column: $table.clientUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get display => $composableBuilder(
    column: $table.display,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get server => $composableBuilder(
    column: $table.server,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxEntriesTableOrderingComposer
    extends Composer<_$LocalDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientUuid => $composableBuilder(
    column: $table.clientUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get display => $composableBuilder(
    column: $table.display,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get server => $composableBuilder(
    column: $table.server,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxEntriesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clientUuid => $composableBuilder(
    column: $table.clientUuid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get display =>
      $composableBuilder(column: $table.display, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get server =>
      $composableBuilder(column: $table.server, builder: (column) => column);
}

class $$OutboxEntriesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $OutboxEntriesTable,
          OutboxEntry,
          $$OutboxEntriesTableFilterComposer,
          $$OutboxEntriesTableOrderingComposer,
          $$OutboxEntriesTableAnnotationComposer,
          $$OutboxEntriesTableCreateCompanionBuilder,
          $$OutboxEntriesTableUpdateCompanionBuilder,
          (
            OutboxEntry,
            BaseReferences<_$LocalDatabase, $OutboxEntriesTable, OutboxEntry>,
          ),
          OutboxEntry,
          PrefetchHooks Function()
        > {
  $$OutboxEntriesTableTableManager(
    _$LocalDatabase db,
    $OutboxEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> clientUuid = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> display = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> server = const Value.absent(),
              }) => OutboxEntriesCompanion(
                id: id,
                clientUuid: clientUuid,
                kind: kind,
                payload: payload,
                display: display,
                status: status,
                errorCode: errorCode,
                errorMessage: errorMessage,
                attempts: attempts,
                createdAt: createdAt,
                server: server,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String clientUuid,
                required String kind,
                required String payload,
                required String display,
                Value<String> status = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                required DateTime createdAt,
                Value<String?> server = const Value.absent(),
              }) => OutboxEntriesCompanion.insert(
                id: id,
                clientUuid: clientUuid,
                kind: kind,
                payload: payload,
                display: display,
                status: status,
                errorCode: errorCode,
                errorMessage: errorMessage,
                attempts: attempts,
                createdAt: createdAt,
                server: server,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxEntriesTable, OutboxEntry>(table),
                  BaseReferences<
                    _$LocalDatabase,
                    $OutboxEntriesTable,
                    OutboxEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $OutboxEntriesTable,
      OutboxEntry,
      $$OutboxEntriesTableFilterComposer,
      $$OutboxEntriesTableOrderingComposer,
      $$OutboxEntriesTableAnnotationComposer,
      $$OutboxEntriesTableCreateCompanionBuilder,
      $$OutboxEntriesTableUpdateCompanionBuilder,
      (
        OutboxEntry,
        BaseReferences<_$LocalDatabase, $OutboxEntriesTable, OutboxEntry>,
      ),
      OutboxEntry,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder = SyncStateCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SyncStateTableUpdateCompanionBuilder = SyncStateCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SyncStateTableFilterComposer
    extends Composer<_$LocalDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$LocalDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$LocalDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $SyncStateTable,
          SyncStateData,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (
            SyncStateData,
            BaseReferences<_$LocalDatabase, $SyncStateTable, SyncStateData>,
          ),
          SyncStateData,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$LocalDatabase db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SyncStateCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SyncStateCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncStateTable, SyncStateData>(table),
                  BaseReferences<
                    _$LocalDatabase,
                    $SyncStateTable,
                    SyncStateData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $SyncStateTable,
      SyncStateData,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (
        SyncStateData,
        BaseReferences<_$LocalDatabase, $SyncStateTable, SyncStateData>,
      ),
      SyncStateData,
      PrefetchHooks Function()
    >;

class $LocalDatabaseManager {
  final _$LocalDatabase _db;
  $LocalDatabaseManager(this._db);
  $$CachedProductsTableTableManager get cachedProducts =>
      $$CachedProductsTableTableManager(_db, _db.cachedProducts);
  $$CachedBarcodesTableTableManager get cachedBarcodes =>
      $$CachedBarcodesTableTableManager(_db, _db.cachedBarcodes);
  $$CachedCustomersTableTableManager get cachedCustomers =>
      $$CachedCustomersTableTableManager(_db, _db.cachedCustomers);
  $$OutboxEntriesTableTableManager get outboxEntries =>
      $$OutboxEntriesTableTableManager(_db, _db.outboxEntries);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
}
