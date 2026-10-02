import 'package:dio/dio.dart';

import '../core/api_exceptions.dart';
import '../models/catalog_item.dart';
import '../models/catalog_query.dart';
import '../models/category.dart';
import '../models/drug.dart';
import '../models/manufacturer.dart';
import '../models/page_result.dart';
import '../models/supplier.dart';
import '../models/supplier_license.dart';
import 'catalog_api_controls.dart';
import 'catalog_repository.dart';

class ApiCatalogRepository
    implements
        CatalogRepository,
        CancellableCatalogRepository,
        DispensingCatalogRepository {
  final Dio _dio;
  final List<Duration> retryPauses;
  ApiCatalogRepository(
    this._dio, {
    this.retryPauses = const [
      Duration(milliseconds: 300),
      Duration(milliseconds: 600),
    ],
  });

  final Map<EntityKind, List<CatalogItem>> _references = {};
  final Map<EntityKind, PageResult<CatalogItem>> _pages = {};
  final Map<EntityKind, CatalogItem> _details = {};
  final Map<EntityKind, CancelToken> _listTokens = {};
  Future<void>? _referenceRequest;
  bool _referencesLoaded = false;

  @override
  String? get storageNotice => null;

  @override
  Future<void> initialize() {
    if (_referencesLoaded) return Future.value();
    return _referenceRequest ??= _loadReferences().whenComplete(() {
      _referenceRequest = null;
    });
  }

  Future<void> _loadReferences() async {
    final response = await _read(() => _dio.get('/references'));
    final body = _object(response.data);
    final next = <EntityKind, List<CatalogItem>>{};
    for (final kind in EntityKind.values.where((k) => k != EntityKind.drugs)) {
      next[kind] = _items(kind, body[kind.name]);
    }
    _references.addAll(next);
    _referencesLoaded = true;
  }

  Future<T> _read<T>(Future<T> Function() action, {CancelToken? token}) async {
    for (var attempt = 0; ; attempt++) {
      if (token?.isCancelled == true) throw const RequestCancelledException();
      try {
        return await guard(action);
      } on NetworkException {
        // Три попытки всего. Ошибки HTTP и операции записи не повторяем.
        if (attempt >= 2) rethrow;
        final pause = retryPauses.isEmpty
            ? Duration.zero
            : retryPauses[attempt.clamp(0, retryPauses.length - 1)];
        await Future.any<void>([
          Future<void>.delayed(pause),
          if (token != null)
            token.whenCancel.then<void>(
              (_) => throw const RequestCancelledException(),
            ),
        ]);
      }
    }
  }

  Map<String, dynamic> _object(dynamic value) {
    if (value is! Map) {
      throw const ServerException('Сервер вернул неверный формат данных.');
    }
    return Map<String, dynamic>.from(value);
  }

  List<CatalogItem> _items(EntityKind kind, dynamic value) {
    if (value is! List) {
      throw const ServerException('В ответе сервера отсутствует список.');
    }
    return value.map((item) => _decode(kind, _object(item))).toList();
  }

  CatalogItem _decode(EntityKind kind, Map<String, dynamic> json) =>
      switch (kind) {
        EntityKind.drugs => Drug.fromJson(json),
        EntityKind.suppliers => Supplier.fromJson(json),
        EntityKind.manufacturers => Manufacturer.fromJson(json),
        EntityKind.categories => Category.fromJson(json),
        EntityKind.licenses => SupplierLicense.fromJson(json),
      };

  @override
  List<CatalogItem> all(EntityKind kind, {bool includeDeleted = false}) =>
      List.unmodifiable(
        (_references[kind] ?? _pages[kind]?.items ?? const <CatalogItem>[])
            .where((item) => includeDeleted || !item.isDeleted),
      );

  @override
  CatalogItem? byId(EntityKind kind, int id) {
    final detail = _details[kind];
    if (detail?.id == id) return detail;
    return (_pages[kind]?.items ?? const <CatalogItem>[])
            .where((item) => item.id == id)
            .firstOrNull ??
        (_references[kind] ?? const <CatalogItem>[])
            .where((item) => item.id == id)
            .firstOrNull;
  }

  CatalogItem _remember(EntityKind kind, dynamic body) {
    final json = _object(body);
    final item = _decode(kind, json);
    _details[kind] = item;
    if (_references[kind] case final list?) {
      final index = list.indexWhere((other) => other.id == item.id);
      index < 0 ? list.add(item) : list[index] = item;
    }
    if (kind == EntityKind.suppliers && json['license'] is Map) {
      _remember(EntityKind.licenses, json['license']);
    }
    return item;
  }

  @override
  Future<CatalogItem?> findById(EntityKind kind, int id) async {
    await initialize();
    try {
      final response = await _read(() => _dio.get('/${kind.path}/$id'));
      return _remember(kind, response.data);
    } on NotFoundException {
      _removeCached(kind, id);
      return null;
    }
  }

  @override
  void cancelList(EntityKind kind) =>
      _listTokens.remove(kind)?.cancel('Новые условия поиска');

  @override
  Future<PageResult<CatalogItem>> find(
    EntityKind kind,
    CatalogQuery query,
  ) async {
    cancelList(kind);
    final token = CancelToken();
    _listTokens[kind] = token;
    try {
      await initialize();
      final response = await _read(
        () => _dio.get(
          '/${kind.path}',
          queryParameters: {
            ...query.toParameters(),
            'page': query.page,
            'size': query.size,
            'sort': '${query.sortField},${query.ascending ? 'asc' : 'desc'}',
          },
          cancelToken: token,
        ),
        token: token,
      );
      if (token.isCancelled) throw const RequestCancelledException();
      final body = _object(response.data);
      final page = PageResult<CatalogItem>(
        items: _items(kind, body['items']),
        page: jsonInt(body['page'], 1),
        size: jsonInt(body['size'], query.size),
        total: jsonInt(body['total']),
      );
      // Предыдущая страница заменяется, а не накапливается.
      _pages[kind] = page;
      final detailId = _details[kind]?.id;
      final updated = page.items
          .where((item) => item.id == detailId)
          .firstOrNull;
      if (updated != null) _details[kind] = updated;
      return page;
    } finally {
      if (identical(_listTokens[kind], token)) _listTokens.remove(kind);
    }
  }

  Map<String, dynamic> _input(CatalogItem item) =>
      {...item.toJson()}..remove('deletedAt');

  @override
  Future<CatalogItem> save(EntityKind kind, CatalogItem item) =>
      guard(() async {
        final response = item.id == 0
            ? await _dio.post('/${kind.path}', data: _input(item))
            : await _dio.put('/${kind.path}/${item.id}', data: _input(item));
        return _remember(kind, response.data);
      });

  @override
  Future<Supplier> saveSupplierWithLicense(
    Supplier supplier,
    SupplierLicense license,
  ) => guard(() async {
    final data = {..._input(supplier), 'license': _input(license)};
    final response = supplier.id == 0
        ? await _dio.post('/suppliers', data: data)
        : await _dio.put('/suppliers/${supplier.id}', data: data);
    return _remember(EntityKind.suppliers, response.data) as Supplier;
  });

  void _removeCached(EntityKind kind, int id) {
    _references[kind]?.removeWhere((item) => item.id == id);
    if (_details[kind]?.id == id) _details.remove(kind);
    _pages.remove(kind);
    if (kind == EntityKind.suppliers) {
      _references[EntityKind.licenses]?.removeWhere(
        (item) => (item as SupplierLicense).supplierId == id,
      );
      _details.remove(EntityKind.licenses);
    }
  }

  @override
  Future<void> softDelete(EntityKind kind, int id) => guard(() async {
    final response = await _dio.delete('/${kind.path}/$id');
    _remember(kind, response.data);
  });

  @override
  Future<void> hardDelete(EntityKind kind, int id) => guard(() async {
    await _dio.delete('/${kind.path}/$id', queryParameters: {'hard': true});
    _removeCached(kind, id);
  });

  @override
  Future<void> restore(EntityKind kind, int id) => guard(() async {
    final response = await _dio.post('/${kind.path}/$id/restore');
    _remember(kind, response.data);
  });

  @override
  Future<int> deleteMany(EntityKind kind, List<int> ids) => guard(() async {
    final response = await _dio.post(
      '/${kind.path}/bulk-delete',
      data: {'ids': ids},
    );
    final body = _object(response.data);
    for (final item in _items(kind, body['items'])) {
      _remember(kind, item.toJson());
    }
    // Сопутствующие лицензии возвращаются сервером отдельно.
    if (body['licenses'] case final List licenses) {
      for (final license in licenses) {
        _remember(EntityKind.licenses, license);
      }
    }
    return jsonInt(body['deleted']);
  });

  @override
  Future<Drug> dispenseDrug(int id, int quantity) => guard(() async {
    final response = await _dio.post(
      '/drugs/$id/dispense',
      data: {'quantity': quantity},
    );
    return _remember(EntityKind.drugs, response.data) as Drug;
  });
}
