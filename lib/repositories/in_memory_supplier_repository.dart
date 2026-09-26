import '../models/page_result.dart';
import '../models/supplier.dart';
import '../models/supplier_query.dart';
import 'seed_data.dart';
import 'supplier_repository.dart';

class InMemorySupplierRepository implements SupplierRepository {
  final List<Supplier> _suppliers = [...seedSuppliers];
  int _nextId = seedSuppliers.length + 1;

  @override
  Future<PageResult<Supplier>> find(SupplierQuery q) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    var rows = _suppliers
        .where((s) => q.includeDeleted || !s.isDeleted)
        .toList();
    final needle = q.search.trim().toLowerCase();
    if (needle.isNotEmpty) {
      rows = rows
          .where(
            (s) =>
                s.name.toLowerCase().contains(needle) ||
                s.contactPerson.toLowerCase().contains(needle) ||
                s.country.toLowerCase().contains(needle),
          )
          .toList();
    }
    rows.sort((a, b) {
      final comparison = switch (q.sortField) {
        'country' => a.country.toLowerCase().compareTo(b.country.toLowerCase()),
        'partnershipYear' => a.partnershipYear.compareTo(b.partnershipYear),
        _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      };
      return q.sortAscending ? comparison : -comparison;
    });
    final total = rows.length;
    final totalPages = total == 0 ? 1 : (total / q.size).ceil();
    final safePage = q.page > totalPages ? totalPages : q.page;
    final from = (safePage - 1) * q.size;
    final to = from + q.size > total ? total : from + q.size;
    final items = from >= total ? <Supplier>[] : rows.sublist(from, to);
    return PageResult(items: items, page: safePage, size: q.size, total: total);
  }

  @override
  Future<Supplier?> findById(int id) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _suppliers.where((supplier) => supplier.id == id).firstOrNull;
  }

  @override
  Future<Supplier> create(Supplier supplier) async {
    final created = Supplier(
      id: _nextId++,
      name: supplier.name,
      contactPerson: supplier.contactPerson,
      country: supplier.country,
      phone: supplier.phone,
      email: supplier.email,
      partnershipYear: supplier.partnershipYear,
      deletedAt: supplier.deletedAt,
    );
    _suppliers.add(created);
    return created;
  }

  @override
  Future<Supplier> update(Supplier supplier) async {
    final index = _indexOf(supplier.id);
    _suppliers[index] = supplier;
    return supplier;
  }

  @override
  Future<void> softDelete(int id) async {
    final index = _indexOf(id);
    _suppliers[index] = _suppliers[index].copyWith(deletedAt: DateTime.now());
  }

  @override
  Future<void> hardDelete(int id) async =>
      _suppliers.removeWhere((supplier) => supplier.id == id);

  @override
  Future<void> restore(int id) async {
    final index = _indexOf(id);
    _suppliers[index] = _suppliers[index].copyWith(clearDeletedAt: true);
  }

  @override
  Future<int> deleteMany(List<int> ids) async {
    var count = 0;
    for (final id in ids) {
      final index = _suppliers.indexWhere(
        (supplier) => supplier.id == id && !supplier.isDeleted,
      );
      if (index != -1) {
        _suppliers[index] = _suppliers[index].copyWith(
          deletedAt: DateTime.now(),
        );
        count++;
      }
    }
    return count;
  }

  int _indexOf(int id) {
    final index = _suppliers.indexWhere((supplier) => supplier.id == id);
    if (index == -1) throw StateError('Поставщик $id не найден');
    return index;
  }
}
