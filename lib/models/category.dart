import 'catalog_item.dart';

class Category implements CatalogItem {
  @override
  final int id;
  final String name;
  final String description;
  @override
  final DateTime? deletedAt;

  const Category({
    required this.id,
    required this.name,
    required this.description,
    this.deletedAt,
  });
  @override
  String get title => name;
  @override
  bool get isDeleted => deletedAt != null;
  Category copyWith({
    String? name,
    String? description,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => Category(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );
  @override
  Category withId(int id) => Category(
    id: id,
    name: name,
    description: description,
    deletedAt: deletedAt,
  );
  @override
  Category withDeletedAt(DateTime? value) =>
      Category(id: id, name: name, description: description, deletedAt: value);
  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'deletedAt': deletedAt?.toIso8601String(),
  };
  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: jsonInt(json['id']),
    name: jsonString(json['name']),
    description: jsonString(json['description']),
    deletedAt: jsonDate(json['deletedAt']),
  );
}
