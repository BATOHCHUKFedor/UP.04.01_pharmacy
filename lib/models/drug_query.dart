class DrugQuery {
  final String search;
  final String? category;
  final int? supplierId;
  final int? yearFrom;
  final int? yearTo;
  final String sortField;
  final bool sortAscending;
  final int page;
  final int size;
  final bool includeDeleted;

  const DrugQuery({
    this.search = '',
    this.category,
    this.supplierId,
    this.yearFrom,
    this.yearTo,
    this.sortField = 'name',
    this.sortAscending = true,
    this.page = 1,
    this.size = 10,
    this.includeDeleted = false,
  });

  factory DrugQuery.fromParameters(Map<String, String> p) {
    final sort = (p['sort'] ?? 'name,asc').split(',');
    return DrugQuery(
      search: p['search'] ?? '',
      category: _drugCategories.contains(p['category']) ? p['category'] : null,
      supplierId: _supplierIds.contains(int.tryParse(p['supplierId'] ?? ''))
          ? int.parse(p['supplierId']!)
          : null,
      yearFrom: int.tryParse(p['yearFrom'] ?? ''),
      yearTo: int.tryParse(p['yearTo'] ?? ''),
      sortField: _drugSortFields.contains(sort.first) ? sort.first : 'name',
      sortAscending: sort.length < 2 || sort[1] != 'desc',
      page: _positiveInt(p['page'], 1),
      size: _pageSizes.contains(int.tryParse(p['size'] ?? ''))
          ? int.parse(p['size']!)
          : 10,
      includeDeleted: p['includeDeleted'] == 'true',
    );
  }

  DrugQuery copyWith({
    String? search,
    Object? category = _unset,
    Object? supplierId = _unset,
    Object? yearFrom = _unset,
    Object? yearTo = _unset,
    String? sortField,
    bool? sortAscending,
    int? page,
    int? size,
    bool? includeDeleted,
  }) {
    return DrugQuery(
      search: search ?? this.search,
      category: category == _unset ? this.category : category as String?,
      supplierId: supplierId == _unset ? this.supplierId : supplierId as int?,
      yearFrom: yearFrom == _unset ? this.yearFrom : yearFrom as int?,
      yearTo: yearTo == _unset ? this.yearTo : yearTo as int?,
      sortField: sortField ?? this.sortField,
      sortAscending: sortAscending ?? this.sortAscending,
      page: page ?? 1,
      size: size ?? this.size,
      includeDeleted: includeDeleted ?? this.includeDeleted,
    );
  }

  Map<String, String> toParameters() => {
    if (search.trim().isNotEmpty) 'search': search.trim(),
    'category': ?category,
    if (supplierId != null) 'supplierId': '$supplierId',
    if (yearFrom != null) 'yearFrom': '$yearFrom',
    if (yearTo != null) 'yearTo': '$yearTo',
    if (sortField != 'name' || !sortAscending)
      'sort': '$sortField,${sortAscending ? 'asc' : 'desc'}',
    if (page != 1) 'page': '$page',
    if (size != 10) 'size': '$size',
    if (includeDeleted) 'includeDeleted': 'true',
  };

  @override
  bool operator ==(Object other) =>
      other is DrugQuery &&
      search == other.search &&
      category == other.category &&
      supplierId == other.supplierId &&
      yearFrom == other.yearFrom &&
      yearTo == other.yearTo &&
      sortField == other.sortField &&
      sortAscending == other.sortAscending &&
      page == other.page &&
      size == other.size &&
      includeDeleted == other.includeDeleted;

  @override
  int get hashCode => Object.hash(
    search,
    category,
    supplierId,
    yearFrom,
    yearTo,
    sortField,
    sortAscending,
    page,
    size,
    includeDeleted,
  );

  static const _unset = Object();
}

const _drugSortFields = {'name', 'productionYear', 'price', 'stock'};
const _pageSizes = {10, 25, 50};
const _drugCategories = {
  'Анальгетики',
  'Противовоспалительные',
  'Антибиотики',
  'Антигистаминные',
  'ЖКТ',
  'Сердечно-сосудистые',
};
const _supplierIds = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
int _positiveInt(String? value, int fallback) {
  final parsed = int.tryParse(value ?? '');
  return parsed != null && parsed > 0 ? parsed : fallback;
}
