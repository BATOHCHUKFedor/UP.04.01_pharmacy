import 'catalog_item.dart';

class Manufacturer implements CatalogItem {
  @override
  final int id;
  final String name;
  final String country;
  final String contactEmail;
  @override
  final DateTime? deletedAt;

  const Manufacturer({
    required this.id,
    required this.name,
    required this.country,
    required this.contactEmail,
    this.deletedAt,
  });
  @override
  String get title => name;
  @override
  bool get isDeleted => deletedAt != null;

  Manufacturer copyWith({
    String? name,
    String? country,
    String? contactEmail,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => Manufacturer(
    id: id,
    name: name ?? this.name,
    country: country ?? this.country,
    contactEmail: contactEmail ?? this.contactEmail,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );
  @override
  Manufacturer withId(int id) => Manufacturer(
    id: id,
    name: name,
    country: country,
    contactEmail: contactEmail,
    deletedAt: deletedAt,
  );
  @override
  Manufacturer withDeletedAt(DateTime? value) => Manufacturer(
    id: id,
    name: name,
    country: country,
    contactEmail: contactEmail,
    deletedAt: value,
  );
  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'country': country,
    'contactEmail': contactEmail,
    'deletedAt': deletedAt?.toIso8601String(),
  };
  factory Manufacturer.fromJson(Map<String, dynamic> json) => Manufacturer(
    id: jsonInt(json['id']),
    name: jsonString(json['name']),
    country: jsonString(json['country']),
    contactEmail: jsonString(json['contactEmail']),
    deletedAt: jsonDate(json['deletedAt']),
  );
}
