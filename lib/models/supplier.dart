import 'catalog_item.dart';

class Supplier implements CatalogItem {
  @override
  final int id;
  final String name;
  final String contactPerson;
  final String country;
  final String phone;
  final String email;
  final int partnershipYear;
  final List<int> manufacturerIds;
  @override
  final DateTime? deletedAt;

  const Supplier({
    required this.id,
    required this.name,
    required this.contactPerson,
    required this.country,
    required this.phone,
    required this.email,
    required this.partnershipYear,
    required this.manufacturerIds,
    this.deletedAt,
  });

  @override
  String get title => name;
  @override
  bool get isDeleted => deletedAt != null;

  Supplier copyWith({
    String? name,
    String? contactPerson,
    String? country,
    String? phone,
    String? email,
    int? partnershipYear,
    List<int>? manufacturerIds,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => Supplier(
    id: id,
    name: name ?? this.name,
    contactPerson: contactPerson ?? this.contactPerson,
    country: country ?? this.country,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    partnershipYear: partnershipYear ?? this.partnershipYear,
    manufacturerIds: manufacturerIds ?? this.manufacturerIds,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );

  @override
  Supplier withId(int id) => Supplier(
    id: id,
    name: name,
    contactPerson: contactPerson,
    country: country,
    phone: phone,
    email: email,
    partnershipYear: partnershipYear,
    manufacturerIds: manufacturerIds,
    deletedAt: deletedAt,
  );
  @override
  Supplier withDeletedAt(DateTime? value) => Supplier(
    id: id,
    name: name,
    contactPerson: contactPerson,
    country: country,
    phone: phone,
    email: email,
    partnershipYear: partnershipYear,
    manufacturerIds: manufacturerIds,
    deletedAt: value,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'contactPerson': contactPerson,
    'country': country,
    'phone': phone,
    'email': email,
    'partnershipYear': partnershipYear,
    'manufacturerIds': manufacturerIds,
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
    id: jsonInt(json['id']),
    name: jsonString(json['name']),
    contactPerson: jsonString(json['contactPerson']),
    country: jsonString(json['country']),
    phone: jsonString(json['phone']),
    email: jsonString(json['email']),
    partnershipYear: jsonInt(json['partnershipYear']),
    manufacturerIds: jsonIds(json['manufacturerIds']),
    deletedAt: jsonDate(json['deletedAt']),
  );
}
