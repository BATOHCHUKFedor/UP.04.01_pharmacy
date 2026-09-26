class Supplier {
  final int id;
  final String name;
  final String contactPerson;
  final String country;
  final String phone;
  final String email;
  final int partnershipYear;
  final DateTime? deletedAt;

  const Supplier({
    required this.id,
    required this.name,
    required this.contactPerson,
    required this.country,
    required this.phone,
    required this.email,
    required this.partnershipYear,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  Supplier copyWith({
    String? name,
    String? contactPerson,
    String? country,
    String? phone,
    String? email,
    int? partnershipYear,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return Supplier(
      id: id,
      name: name ?? this.name,
      contactPerson: contactPerson ?? this.contactPerson,
      country: country ?? this.country,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      partnershipYear: partnershipYear ?? this.partnershipYear,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}
