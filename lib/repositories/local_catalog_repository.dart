import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/catalog_item.dart';
import '../models/catalog_query.dart';
import '../models/category.dart';
import '../models/drug.dart';
import '../models/manufacturer.dart';
import '../models/page_result.dart';
import '../models/supplier.dart';
import '../models/supplier_license.dart';
import 'catalog_repository.dart';
import 'seed_data.dart';

class LocalCatalogRepository implements CatalogRepository {
  static const _storageKey = 'pharmacy.catalog.v2';
  final SharedPreferencesAsync _preferences;
  LocalCatalogRepository(this._preferences);

  Map<EntityKind, List<CatalogItem>> _rows = {};
  Future<void>? _initialization;
  Future<void> _pendingWrite = Future<void>.value();
  @override
  String? storageNotice;

  @override
  Future<void> initialize() => _initialization ??= _read();

  Future<void> _read() async {
    String? raw;
    try {
      raw = await _preferences.getString(_storageKey);
    } catch (_) {
      _rows = _seeds();
      storageNotice =
          'Не удалось прочитать локальное хранилище. Загружен начальный каталог.';
      return;
    }
    if (raw == null) {
      _rows = _seeds();
      try {
        if (await _preferences.getString('pharmacy.catalog.v1') != null) {
          storageNotice =
              'Обнаружен старый формат данных. Загружен начальный каталог новой версии.';
        }
      } catch (_) {
        storageNotice =
            'Не удалось проверить прежнюю версию хранилища. Загружен начальный каталог.';
      }
      try {
        await _preferences.setString(_storageKey, _encode(_rows));
      } catch (_) {
        storageNotice =
            'Не удалось сохранить начальный каталог в браузере. Изменения могут не сохраниться.';
      }
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['version'] != 2) {
        throw const FormatException('Неподдерживаемая версия данных');
      }
      _rows = {
        for (final kind in EntityKind.values)
          kind: _decodeItems(kind, decoded[kind.name]),
      };
    } catch (_) {
      _rows = _seeds();
      storageNotice =
          'Сохранённые данные имеют старый или повреждённый формат. Загружен начальный каталог.';
    }
  }

  Map<EntityKind, List<CatalogItem>> _seeds() => {
    EntityKind.drugs: [...seedDrugs],
    EntityKind.suppliers: [...seedSuppliers],
    EntityKind.manufacturers: [...seedManufacturers],
    EntityKind.categories: [...seedCategories],
    EntityKind.licenses: [...seedLicenses],
  };

  List<CatalogItem> _decodeItems(EntityKind kind, Object? value) {
    if (value is! List) return <CatalogItem>[];
    return value.whereType<Map>().map((entry) {
      final json = Map<String, dynamic>.from(entry);
      return switch (kind) {
        EntityKind.drugs => Drug.fromJson(json),
        EntityKind.suppliers => Supplier.fromJson(json),
        EntityKind.manufacturers => Manufacturer.fromJson(json),
        EntityKind.categories => Category.fromJson(json),
        EntityKind.licenses => SupplierLicense.fromJson(json),
      };
    }).toList();
  }

  String _encode(Map<EntityKind, List<CatalogItem>> rows) => jsonEncode({
    'version': 2,
    for (final kind in EntityKind.values)
      kind.name: rows[kind]!.map((item) => item.toJson()).toList(),
  });

  @override
  List<CatalogItem> all(EntityKind kind, {bool includeDeleted = false}) =>
      List.unmodifiable(
        (_rows[kind] ?? const <CatalogItem>[]).where(
          (item) => includeDeleted || !item.isDeleted,
        ),
      );

  @override
  CatalogItem? byId(EntityKind kind, int id) =>
      (_rows[kind] ?? const <CatalogItem>[])
          .where((item) => item.id == id)
          .firstOrNull;

  @override
  Future<CatalogItem?> findById(EntityKind kind, int id) async {
    await initialize();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return byId(kind, id);
  }

  @override
  Future<PageResult<CatalogItem>> find(EntityKind kind, CatalogQuery q) async {
    await initialize();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    var rows = all(kind, includeDeleted: q.includeDeleted).toList();
    final search = q.search.trim().toLowerCase();
    if (search.isNotEmpty) {
      rows = rows.where((item) => _searchText(item).contains(search)).toList();
    }
    if (kind == EntityKind.drugs) {
      rows = rows
          .cast<Drug>()
          .where(
            (drug) =>
                (q.categoryId == null ||
                    drug.categoryIds.contains(q.categoryId)) &&
                (q.manufacturerId == null ||
                    drug.manufacturerId == q.manufacturerId) &&
                (q.supplierId == null || drug.supplierId == q.supplierId) &&
                (q.yearFrom == null || drug.productionYear >= q.yearFrom!) &&
                (q.yearTo == null || drug.productionYear <= q.yearTo!),
          )
          .toList();
    }
    if (kind == EntityKind.suppliers) {
      rows = rows
          .cast<Supplier>()
          .where(
            (supplier) =>
                (q.country == null || supplier.country == q.country) &&
                (q.manufacturerId == null ||
                    supplier.manufacturerIds.contains(q.manufacturerId)),
          )
          .toList();
    }
    if (kind == EntityKind.manufacturers && q.country != null) {
      rows = rows
          .cast<Manufacturer>()
          .where((m) => m.country == q.country)
          .toList();
    }
    if (kind == EntityKind.categories && q.usedOnly == true) {
      final usedIds = _rows[EntityKind.drugs]!
          .cast<Drug>()
          .expand((drug) => drug.categoryIds)
          .toSet();
      rows = rows
          .cast<Category>()
          .where((c) => usedIds.contains(c.id))
          .toList();
    }
    if (kind == EntityKind.licenses) {
      rows = rows
          .cast<SupplierLicense>()
          .where(
            (license) =>
                (q.supplierId == null || license.supplierId == q.supplierId) &&
                (q.yearFrom == null || license.expiresYear >= q.yearFrom!) &&
                (q.yearTo == null || license.expiresYear <= q.yearTo!),
          )
          .toList();
    }
    rows.sort((a, b) {
      final result = _sortValue(
        a,
        q.sortField,
      ).compareTo(_sortValue(b, q.sortField));
      return q.ascending ? result : -result;
    });
    final total = rows.length;
    final totalPages = total == 0 ? 1 : (total / q.size).ceil();
    final page = q.page.clamp(1, totalPages);
    final from = (page - 1) * q.size;
    final to = (from + q.size).clamp(0, total);
    return PageResult(
      items: rows.sublist(from, to),
      page: page,
      size: q.size,
      total: total,
    );
  }

  String _searchText(CatalogItem item) => switch (item) {
    Drug d => '${d.name} ${d.registrationNumber}'.toLowerCase(),
    Supplier s =>
      '${s.name} ${s.contactPerson} ${s.country} ${s.email}'.toLowerCase(),
    Manufacturer m => '${m.name} ${m.country}'.toLowerCase(),
    Category c => '${c.name} ${c.description}'.toLowerCase(),
    SupplierLicense l =>
      '${l.number} ${byId(EntityKind.suppliers, l.supplierId)?.title ?? ''}'
          .toLowerCase(),
    _ => item.title.toLowerCase(),
  };

  Comparable<dynamic> _sortValue(CatalogItem item, String field) =>
      switch ((item, field)) {
        (_, 'id') => item.id,
        (Drug d, 'year') => d.productionYear,
        (Drug d, 'price') => d.price,
        (Drug d, 'stock') => d.stock,
        (Supplier s, 'country') => s.country.toLowerCase(),
        (Supplier s, 'year') => s.partnershipYear,
        (Supplier s, 'email') => s.email.toLowerCase(),
        (Manufacturer m, 'country') => m.country.toLowerCase(),
        (Manufacturer m, 'email') => m.contactEmail.toLowerCase(),
        (Category c, 'description') => c.description.toLowerCase(),
        (SupplierLicense l, 'expiresYear') => l.expiresYear,
        (SupplierLicense l, 'issuedYear') => l.issuedYear,
        _ => item.title.toLowerCase(),
      };

  Future<R> _transaction<R>(
    R Function(Map<EntityKind, List<CatalogItem>>) change,
  ) async {
    await initialize();
    final previous = _pendingWrite;
    final completion = Completer<void>();
    _pendingWrite = completion.future;
    await previous;
    try {
      final next = {
        for (final kind in EntityKind.values) kind: [..._rows[kind]!],
      };
      final result = change(next);
      await _preferences.setString(_storageKey, _encode(next));
      _rows = next;
      return result;
    } finally {
      completion.complete();
    }
  }

  CatalogItem _upsert(
    Map<EntityKind, List<CatalogItem>> rows,
    EntityKind kind,
    CatalogItem item,
  ) {
    final list = rows[kind]!;
    _validateReferences(rows, kind, item);
    if (kind == EntityKind.drugs) {
      final drug = item as Drug;
      if (rows[EntityKind.drugs]!.cast<Drug>().any(
        (existing) =>
            existing.id != drug.id &&
            existing.registrationNumber.toLowerCase() ==
                drug.registrationNumber.trim().toLowerCase(),
      )) {
        throw const FieldIssue(
          'registrationNumber',
          'Такой регистрационный номер уже существует',
        );
      }
    }
    if (kind == EntityKind.suppliers) {
      final supplier = item as Supplier;
      if (rows[EntityKind.suppliers]!.cast<Supplier>().any(
        (existing) =>
            existing.id != supplier.id &&
            existing.email.toLowerCase() == supplier.email.trim().toLowerCase(),
      )) {
        throw const FieldIssue('email', 'Такой адрес почты уже существует');
      }
      final associated = rows[EntityKind.drugs]!.cast<Drug>().where(
        (drug) => drug.supplierId == supplier.id,
      );
      if (associated.any(
        (drug) => !supplier.manufacturerIds.contains(drug.manufacturerId),
      )) {
        throw const FieldIssue(
          'manufacturerIds',
          'Нельзя убрать производителя: с ним связаны препараты этого поставщика',
        );
      }
    }
    if (kind == EntityKind.licenses) {
      final license = item as SupplierLicense;
      if (rows[EntityKind.licenses]!.cast<SupplierLicense>().any(
        (existing) =>
            existing.id != license.id &&
            existing.supplierId == license.supplierId,
      )) {
        throw const FieldIssue(
          'supplierId',
          'У этого поставщика уже есть лицензия',
        );
      }
    }
    if (item.id == 0) {
      final nextId =
          list.fold<int>(
            0,
            (max, current) => current.id > max ? current.id : max,
          ) +
          1;
      final created = item.withId(nextId);
      list.add(created);
      return created;
    }
    final index = list.indexWhere((existing) => existing.id == item.id);
    if (index < 0) throw StateError('Запись не найдена');
    list[index] = item;
    return item;
  }

  void _validateReferences(
    Map<EntityKind, List<CatalogItem>> rows,
    EntityKind kind,
    CatalogItem item,
  ) {
    bool active(EntityKind target, int id) =>
        rows[target]!.any((other) => other.id == id && !other.isDeleted);
    if (item is Drug) {
      if (!active(EntityKind.manufacturers, item.manufacturerId)) {
        throw const FieldIssue(
          'manufacturerId',
          'Выберите действующего производителя',
        );
      }
      if (!active(EntityKind.suppliers, item.supplierId)) {
        throw const FieldIssue(
          'supplierId',
          'Выберите действующего поставщика',
        );
      }
      final supplier = rows[EntityKind.suppliers]!.cast<Supplier>().firstWhere(
        (s) => s.id == item.supplierId,
      );
      if (!supplier.manufacturerIds.contains(item.manufacturerId)) {
        throw const FieldIssue(
          'supplierId',
          'Поставщик не работает с выбранным производителем',
        );
      }
      if (item.categoryIds.isEmpty ||
          item.categoryIds.any((id) => !active(EntityKind.categories, id))) {
        throw const FieldIssue('categoryIds', 'Выберите действующие категории');
      }
    }
    if (item is Supplier &&
        item.manufacturerIds.any(
          (id) => !active(EntityKind.manufacturers, id),
        )) {
      throw const FieldIssue(
        'manufacturerIds',
        'Выберите действующих производителей',
      );
    }
    if (item is SupplierLicense &&
        !active(EntityKind.suppliers, item.supplierId)) {
      throw const FieldIssue('supplierId', 'Выберите действующего поставщика');
    }
  }

  @override
  Future<CatalogItem> save(EntityKind kind, CatalogItem item) =>
      _transaction((rows) => _upsert(rows, kind, item));

  @override
  Future<Supplier> saveSupplierWithLicense(
    Supplier supplier,
    SupplierLicense license,
  ) => _transaction((rows) {
    final saved = _upsert(rows, EntityKind.suppliers, supplier) as Supplier;
    final corrected = license.copyWith(supplierId: saved.id);
    _upsert(rows, EntityKind.licenses, corrected);
    return saved;
  });

  void _checkDeletion(
    Map<EntityKind, List<CatalogItem>> rows,
    EntityKind kind,
    int id,
  ) {
    final drugs = rows[EntityKind.drugs]!.cast<Drug>();
    final suppliers = rows[EntityKind.suppliers]!.cast<Supplier>();
    if (kind == EntityKind.manufacturers) {
      final drugCount = drugs.where((d) => d.manufacturerId == id).length;
      if (drugCount > 0) {
        throw RelationIssue(
          'Удаление невозможно: связанных препаратов — $drugCount',
        );
      }
      final supplierCount = suppliers
          .where((s) => s.manufacturerIds.contains(id))
          .length;
      if (supplierCount > 0) {
        throw RelationIssue(
          'Удаление невозможно: связанных поставщиков — $supplierCount',
        );
      }
    }
    if (kind == EntityKind.categories) {
      final count = drugs.where((d) => d.categoryIds.contains(id)).length;
      if (count > 0) {
        throw RelationIssue(
          'Удаление невозможно: связанных препаратов — $count',
        );
      }
    }
    if (kind == EntityKind.suppliers) {
      final count = drugs.where((d) => d.supplierId == id).length;
      if (count > 0) {
        throw RelationIssue(
          'Удаление невозможно: связанных препаратов — $count',
        );
      }
    }
  }

  @override
  Future<void> softDelete(EntityKind kind, int id) => _transaction((rows) {
    _checkDeletion(rows, kind, id);
    final list = rows[kind]!;
    final index = list.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Запись не найдена');
    list[index] = list[index].withDeletedAt(DateTime.now());
    if (kind == EntityKind.suppliers) {
      final licenses = rows[EntityKind.licenses]!;
      for (var i = 0; i < licenses.length; i++) {
        if ((licenses[i] as SupplierLicense).supplierId == id) {
          licenses[i] = licenses[i].withDeletedAt(DateTime.now());
        }
      }
    }
  });

  @override
  Future<void> hardDelete(EntityKind kind, int id) => _transaction((rows) {
    _checkDeletion(rows, kind, id);
    rows[kind]!.removeWhere((item) => item.id == id);
    if (kind == EntityKind.suppliers) {
      rows[EntityKind.licenses]!.removeWhere(
        (item) => (item as SupplierLicense).supplierId == id,
      );
    }
  });

  @override
  Future<void> restore(EntityKind kind, int id) => _transaction((rows) {
    final list = rows[kind]!;
    final index = list.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Запись не найдена');
    list[index] = list[index].withDeletedAt(null);
    if (kind == EntityKind.suppliers) {
      final licenses = rows[EntityKind.licenses]!;
      for (var i = 0; i < licenses.length; i++) {
        if ((licenses[i] as SupplierLicense).supplierId == id) {
          licenses[i] = licenses[i].withDeletedAt(null);
        }
      }
    }
  });

  @override
  Future<int> deleteMany(EntityKind kind, List<int> ids) => _transaction((
    rows,
  ) {
    var count = 0;
    final list = rows[kind]!;
    for (final id in ids.toSet()) {
      final index = list.indexWhere((item) => item.id == id && !item.isDeleted);
      if (index < 0) continue;
      _checkDeletion(rows, kind, id);
      list[index] = list[index].withDeletedAt(DateTime.now());
      if (kind == EntityKind.suppliers) {
        final licenses = rows[EntityKind.licenses]!;
        for (var i = 0; i < licenses.length; i++) {
          if ((licenses[i] as SupplierLicense).supplierId == id) {
            licenses[i] = licenses[i].withDeletedAt(DateTime.now());
          }
        }
      }
      count++;
    }
    return count;
  });
}
