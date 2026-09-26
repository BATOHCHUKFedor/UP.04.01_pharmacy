import '../models/drug.dart';
import '../models/drug_query.dart';
import '../models/page_result.dart';
import 'drug_repository.dart';
import 'seed_data.dart';

class InMemoryDrugRepository implements DrugRepository {
  final List<Drug> _drugs = [...seedDrugs];
  int _nextId = seedDrugs.length + 1;

  @override
  Future<PageResult<Drug>> find(DrugQuery q) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    var rows = _drugs
        .where((drug) => q.includeDeleted || !drug.isDeleted)
        .toList();

    final needle = q.search.trim().toLowerCase();
    if (needle.isNotEmpty) {
      rows = rows
          .where(
            (drug) =>
                drug.name.toLowerCase().contains(needle) ||
                drug.registrationNumber.toLowerCase().contains(needle),
          )
          .toList();
    }
    if (q.category != null) {
      rows = rows.where((drug) => drug.category == q.category).toList();
    }
    if (q.supplierId != null) {
      rows = rows.where((drug) => drug.supplierId == q.supplierId).toList();
    }
    if (q.yearFrom != null) {
      rows = rows.where((drug) => drug.productionYear >= q.yearFrom!).toList();
    }
    if (q.yearTo != null) {
      rows = rows.where((drug) => drug.productionYear <= q.yearTo!).toList();
    }

    rows.sort((a, b) {
      final comparison = switch (q.sortField) {
        'productionYear' => a.productionYear.compareTo(b.productionYear),
        'price' => a.price.compareTo(b.price),
        'stock' => a.stock.compareTo(b.stock),
        _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      };
      return q.sortAscending ? comparison : -comparison;
    });

    final total = rows.length;
    final totalPages = total == 0 ? 1 : (total / q.size).ceil();
    final safePage = q.page > totalPages ? totalPages : q.page;
    final from = (safePage - 1) * q.size;
    final to = from + q.size > total ? total : from + q.size;
    final items = from >= total ? <Drug>[] : rows.sublist(from, to);
    return PageResult(items: items, page: safePage, size: q.size, total: total);
  }

  @override
  Future<Drug?> findById(int id) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _drugs.where((drug) => drug.id == id).firstOrNull;
  }

  @override
  Future<Drug> create(Drug drug) async {
    final created = Drug(
      id: _nextId++,
      name: drug.name,
      registrationNumber: drug.registrationNumber,
      category: drug.category,
      manufacturer: drug.manufacturer,
      productionYear: drug.productionYear,
      price: drug.price,
      stock: drug.stock,
      supplierId: drug.supplierId,
      deletedAt: drug.deletedAt,
    );
    _drugs.add(created);
    return created;
  }

  @override
  Future<Drug> update(Drug drug) async {
    final index = _indexOf(drug.id);
    _drugs[index] = drug;
    return drug;
  }

  @override
  Future<void> softDelete(int id) async {
    final index = _indexOf(id);
    _drugs[index] = _drugs[index].copyWith(deletedAt: DateTime.now());
  }

  @override
  Future<void> hardDelete(int id) async {
    _drugs.removeWhere((drug) => drug.id == id);
  }

  @override
  Future<void> restore(int id) async {
    final index = _indexOf(id);
    _drugs[index] = _drugs[index].copyWith(clearDeletedAt: true);
  }

  @override
  Future<int> deleteMany(List<int> ids) async {
    var count = 0;
    for (final id in ids) {
      final index = _drugs.indexWhere(
        (drug) => drug.id == id && !drug.isDeleted,
      );
      if (index != -1) {
        _drugs[index] = _drugs[index].copyWith(deletedAt: DateTime.now());
        count++;
      }
    }
    return count;
  }

  int _indexOf(int id) {
    final index = _drugs.indexWhere((drug) => drug.id == id);
    if (index == -1) throw StateError('Препарат $id не найден');
    return index;
  }
}
