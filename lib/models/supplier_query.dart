class SupplierQuery {
  final String search;
  final String sortField;
  final bool sortAscending;
  final int page;
  final int size;
  final bool includeDeleted;

  const SupplierQuery({
    this.search = '',
    this.sortField = 'name',
    this.sortAscending = true,
    this.page = 1,
    this.size = 10,
    this.includeDeleted = false,
  });

  factory SupplierQuery.fromParameters(Map<String, String> p) {
    final sort = (p['sort'] ?? 'name,asc').split(',');
    final requestedSize = int.tryParse(p['size'] ?? '');
    final requestedPage = int.tryParse(p['page'] ?? '');
    return SupplierQuery(
      search: p['search'] ?? '',
      sortField: _supplierSortFields.contains(sort.first) ? sort.first : 'name',
      sortAscending: sort.length < 2 || sort[1] != 'desc',
      page: requestedPage != null && requestedPage > 0 ? requestedPage : 1,
      size: const {10, 25, 50}.contains(requestedSize) ? requestedSize! : 10,
      includeDeleted: p['includeDeleted'] == 'true',
    );
  }

  SupplierQuery copyWith({
    String? search,
    String? sortField,
    bool? sortAscending,
    int? page,
    int? size,
    bool? includeDeleted,
  }) {
    return SupplierQuery(
      search: search ?? this.search,
      sortField: sortField ?? this.sortField,
      sortAscending: sortAscending ?? this.sortAscending,
      page: page ?? 1,
      size: size ?? this.size,
      includeDeleted: includeDeleted ?? this.includeDeleted,
    );
  }

  Map<String, String> toParameters() => {
    if (search.trim().isNotEmpty) 'search': search.trim(),
    if (sortField != 'name' || !sortAscending)
      'sort': '$sortField,${sortAscending ? 'asc' : 'desc'}',
    if (page != 1) 'page': '$page',
    if (size != 10) 'size': '$size',
    if (includeDeleted) 'includeDeleted': 'true',
  };

  @override
  bool operator ==(Object other) =>
      other is SupplierQuery &&
      search == other.search &&
      sortField == other.sortField &&
      sortAscending == other.sortAscending &&
      page == other.page &&
      size == other.size &&
      includeDeleted == other.includeDeleted;

  @override
  int get hashCode =>
      Object.hash(search, sortField, sortAscending, page, size, includeDeleted);
}

const _supplierSortFields = {'name', 'country', 'partnershipYear'};
