class CatalogQuery {
  final String search;
  final int? categoryId;
  final int? manufacturerId;
  final int? supplierId;
  final int? yearFrom;
  final int? yearTo;
  final String? country;
  final bool? usedOnly;
  final String sortField;
  final bool ascending;
  final int page;
  final int size;
  final bool includeDeleted;

  const CatalogQuery({
    this.search = '',
    this.categoryId,
    this.manufacturerId,
    this.supplierId,
    this.yearFrom,
    this.yearTo,
    this.country,
    this.usedOnly,
    this.sortField = 'name',
    this.ascending = true,
    this.page = 1,
    this.size = 10,
    this.includeDeleted = false,
  });

  factory CatalogQuery.fromParameters(Map<String, String> p) {
    final sort = (p['sort'] ?? 'name,asc').split(',');
    final size = int.tryParse(p['size'] ?? '');
    final page = int.tryParse(p['page'] ?? '');
    return CatalogQuery(
      search: p['search'] ?? '',
      categoryId: int.tryParse(p['categoryId'] ?? ''),
      manufacturerId: int.tryParse(p['manufacturerId'] ?? ''),
      supplierId: int.tryParse(p['supplierId'] ?? ''),
      yearFrom: int.tryParse(p['yearFrom'] ?? ''),
      yearTo: int.tryParse(p['yearTo'] ?? ''),
      country: p['country']?.isNotEmpty == true ? p['country'] : null,
      usedOnly: p['usedOnly'] == 'true' ? true : null,
      sortField:
          const {
            'name',
            'year',
            'price',
            'stock',
            'country',
            'expiresYear',
            'issuedYear',
            'description',
            'email',
            'id',
          }.contains(sort.first)
          ? sort.first
          : 'name',
      ascending: sort.length < 2 || sort[1] != 'desc',
      page: page != null && page > 0 ? page : 1,
      size: const {10, 25, 50}.contains(size) ? size! : 10,
      includeDeleted: p['includeDeleted'] == 'true',
    );
  }

  CatalogQuery copyWith({
    String? search,
    Object? categoryId = _unset,
    Object? manufacturerId = _unset,
    Object? supplierId = _unset,
    Object? yearFrom = _unset,
    Object? yearTo = _unset,
    Object? country = _unset,
    Object? usedOnly = _unset,
    String? sortField,
    bool? ascending,
    int? page,
    int? size,
    bool? includeDeleted,
  }) => CatalogQuery(
    search: search ?? this.search,
    categoryId: categoryId == _unset ? this.categoryId : categoryId as int?,
    manufacturerId: manufacturerId == _unset
        ? this.manufacturerId
        : manufacturerId as int?,
    supplierId: supplierId == _unset ? this.supplierId : supplierId as int?,
    yearFrom: yearFrom == _unset ? this.yearFrom : yearFrom as int?,
    yearTo: yearTo == _unset ? this.yearTo : yearTo as int?,
    country: country == _unset ? this.country : country as String?,
    usedOnly: usedOnly == _unset ? this.usedOnly : usedOnly as bool?,
    sortField: sortField ?? this.sortField,
    ascending: ascending ?? this.ascending,
    page: page ?? 1,
    size: size ?? this.size,
    includeDeleted: includeDeleted ?? this.includeDeleted,
  );

  Map<String, String> toParameters() => {
    if (search.trim().isNotEmpty) 'search': search.trim(),
    if (categoryId != null) 'categoryId': '$categoryId',
    if (manufacturerId != null) 'manufacturerId': '$manufacturerId',
    if (supplierId != null) 'supplierId': '$supplierId',
    if (yearFrom != null) 'yearFrom': '$yearFrom',
    if (yearTo != null) 'yearTo': '$yearTo',
    'country': ?country,
    if (usedOnly == true) 'usedOnly': 'true',
    if (sortField != 'name' || !ascending)
      'sort': '$sortField,${ascending ? 'asc' : 'desc'}',
    if (page != 1) 'page': '$page',
    if (size != 10) 'size': '$size',
    if (includeDeleted) 'includeDeleted': 'true',
  };

  @override
  bool operator ==(Object other) =>
      other is CatalogQuery &&
      search == other.search &&
      categoryId == other.categoryId &&
      manufacturerId == other.manufacturerId &&
      supplierId == other.supplierId &&
      yearFrom == other.yearFrom &&
      yearTo == other.yearTo &&
      country == other.country &&
      usedOnly == other.usedOnly &&
      sortField == other.sortField &&
      ascending == other.ascending &&
      page == other.page &&
      size == other.size &&
      includeDeleted == other.includeDeleted;
  @override
  int get hashCode => Object.hashAll([
    search,
    categoryId,
    manufacturerId,
    supplierId,
    yearFrom,
    yearTo,
    country,
    usedOnly,
    sortField,
    ascending,
    page,
    size,
    includeDeleted,
  ]);
  static const _unset = Object();
}
