import 'catalog_item.dart';

class SupplierLicense implements CatalogItem {
  @override
  final int id;
  final int supplierId;
  final String number;
  final int issuedYear;
  final int expiresYear;
  @override
  final DateTime? deletedAt;

  const SupplierLicense({
    required this.id,
    required this.supplierId,
    required this.number,
    required this.issuedYear,
    required this.expiresYear,
    this.deletedAt,
  });
  @override
  String get title => number;
  @override
  bool get isDeleted => deletedAt != null;
  SupplierLicense copyWith({
    int? supplierId,
    String? number,
    int? issuedYear,
    int? expiresYear,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => SupplierLicense(
    id: id,
    supplierId: supplierId ?? this.supplierId,
    number: number ?? this.number,
    issuedYear: issuedYear ?? this.issuedYear,
    expiresYear: expiresYear ?? this.expiresYear,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );
  @override
  SupplierLicense withId(int id) => SupplierLicense(
    id: id,
    supplierId: supplierId,
    number: number,
    issuedYear: issuedYear,
    expiresYear: expiresYear,
    deletedAt: deletedAt,
  );
  @override
  SupplierLicense withDeletedAt(DateTime? value) => SupplierLicense(
    id: id,
    supplierId: supplierId,
    number: number,
    issuedYear: issuedYear,
    expiresYear: expiresYear,
    deletedAt: value,
  );
  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'supplierId': supplierId,
    'number': number,
    'issuedYear': issuedYear,
    'expiresYear': expiresYear,
    'deletedAt': deletedAt?.toIso8601String(),
  };
  factory SupplierLicense.fromJson(Map<String, dynamic> json) =>
      SupplierLicense(
        id: jsonInt(json['id']),
        supplierId: jsonRelatedId(json['supplierId'], json['supplier']),
        number: jsonString(json['number']),
        issuedYear: jsonInt(json['issuedYear']),
        expiresYear: jsonInt(json['expiresYear']),
        deletedAt: jsonDate(json['deletedAt']),
      );
}
