class Drug {
  final int id;
  final String name;
  final String registrationNumber;
  final String category;
  final String manufacturer;
  final int productionYear;
  final double price;
  final int stock;
  final int supplierId;
  final DateTime? deletedAt;

  const Drug({
    required this.id,
    required this.name,
    required this.registrationNumber,
    required this.category,
    required this.manufacturer,
    required this.productionYear,
    required this.price,
    required this.stock,
    required this.supplierId,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  Drug copyWith({
    String? name,
    String? registrationNumber,
    String? category,
    String? manufacturer,
    int? productionYear,
    double? price,
    int? stock,
    int? supplierId,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return Drug(
      id: id,
      name: name ?? this.name,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      category: category ?? this.category,
      manufacturer: manufacturer ?? this.manufacturer,
      productionYear: productionYear ?? this.productionYear,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      supplierId: supplierId ?? this.supplierId,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}
