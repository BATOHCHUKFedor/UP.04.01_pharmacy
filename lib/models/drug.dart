import 'catalog_item.dart';

class Drug implements CatalogItem {
  @override
  final int id;
  final String name;
  final String registrationNumber;
  final List<int> categoryIds;
  final int manufacturerId;
  final int productionYear;
  final double price;
  final int stock;
  final int supplierId;
  @override
  final DateTime? deletedAt;

  const Drug({
    required this.id,
    required this.name,
    required this.registrationNumber,
    required this.categoryIds,
    required this.manufacturerId,
    required this.productionYear,
    required this.price,
    required this.stock,
    required this.supplierId,
    this.deletedAt,
  });

  @override
  String get title => name;
  @override
  bool get isDeleted => deletedAt != null;

  Drug copyWith({
    String? name,
    String? registrationNumber,
    List<int>? categoryIds,
    int? manufacturerId,
    int? productionYear,
    double? price,
    int? stock,
    int? supplierId,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => Drug(
    id: id,
    name: name ?? this.name,
    registrationNumber: registrationNumber ?? this.registrationNumber,
    categoryIds: categoryIds ?? this.categoryIds,
    manufacturerId: manufacturerId ?? this.manufacturerId,
    productionYear: productionYear ?? this.productionYear,
    price: price ?? this.price,
    stock: stock ?? this.stock,
    supplierId: supplierId ?? this.supplierId,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );

  @override
  Drug withId(int id) => Drug(
    id: id,
    name: name,
    registrationNumber: registrationNumber,
    categoryIds: categoryIds,
    manufacturerId: manufacturerId,
    productionYear: productionYear,
    price: price,
    stock: stock,
    supplierId: supplierId,
    deletedAt: deletedAt,
  );
  @override
  Drug withDeletedAt(DateTime? value) => Drug(
    id: id,
    name: name,
    registrationNumber: registrationNumber,
    categoryIds: categoryIds,
    manufacturerId: manufacturerId,
    productionYear: productionYear,
    price: price,
    stock: stock,
    supplierId: supplierId,
    deletedAt: value,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'registrationNumber': registrationNumber,
    'categoryIds': categoryIds,
    'manufacturerId': manufacturerId,
    'productionYear': productionYear,
    'price': price,
    'stock': stock,
    'supplierId': supplierId,
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory Drug.fromJson(Map<String, dynamic> json) => Drug(
    id: jsonInt(json['id']),
    name: jsonString(json['name']),
    registrationNumber: jsonString(json['registrationNumber']),
    categoryIds: jsonRelatedIds(json['categoryIds'], json['categories']),
    manufacturerId: jsonRelatedId(json['manufacturerId'], json['manufacturer']),
    productionYear: jsonInt(json['productionYear']),
    price: jsonDouble(json['price']),
    stock: jsonInt(json['stock']),
    supplierId: jsonRelatedId(json['supplierId'], json['supplier']),
    deletedAt: jsonDate(json['deletedAt']),
  );
}
