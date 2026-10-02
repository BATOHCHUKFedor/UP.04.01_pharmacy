import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/catalog_item.dart';
import '../models/catalog_query.dart';
import '../models/page_result.dart';
import '../models/supplier.dart';
import '../models/supplier_license.dart';
import '../models/drug.dart';
import '../core/api_exceptions.dart';
import '../repositories/catalog_api_controls.dart';
import '../repositories/catalog_repository.dart';
import 'load_status.dart';

class CatalogListState {
  CatalogQuery query = const CatalogQuery();
  PageResult<CatalogItem> result = PageResult.empty();
  LoadStatus status = LoadStatus.idle;
  String? error;
  final Set<int> selected = {};
  int request = 0;
  UnmodifiableSetView<int> get selection => UnmodifiableSetView(selected);
}

class CatalogDetailState {
  LoadStatus status = LoadStatus.idle;
  String? error;
  int request = 0;
}

class CatalogStore extends ChangeNotifier {
  final CatalogRepository _repository;
  CatalogStore(this._repository);
  final Map<EntityKind, CatalogListState> _lists = {
    for (final kind in EntityKind.values) kind: CatalogListState(),
  };
  final Map<(EntityKind, int), CatalogDetailState> _details = {};
  String? get storageNotice => _repository.storageNotice;
  void dismissStorageNotice() {
    _noticeDismissed = true;
    notifyListeners();
  }

  bool _noticeDismissed = false;
  bool get showStorageNotice => !_noticeDismissed && storageNotice != null;

  CatalogListState list(EntityKind kind) => _lists[kind]!;
  List<CatalogItem> options(EntityKind kind, {bool includeDeleted = false}) =>
      _repository.all(kind, includeDeleted: includeDeleted);
  CatalogItem? byId(EntityKind kind, int id) => _repository.byId(kind, id);
  CatalogDetailState detail(EntityKind kind, int id) =>
      _details.putIfAbsent((kind, id), CatalogDetailState.new);

  Future<void> loadDetail(EntityKind kind, int id) async {
    final state = detail(kind, id);
    final request = ++state.request;
    state.status = LoadStatus.loading;
    state.error = null;
    notifyListeners();
    try {
      await _repository.findById(kind, id);
      if (state.request != request) return;
      state.status = LoadStatus.success;
    } catch (error) {
      if (state.request != request) return;
      state.status = LoadStatus.error;
      state.error = 'Не удалось загрузить карточку: $error';
    }
    notifyListeners();
  }

  Future<void> applyQuery(
    EntityKind kind,
    CatalogQuery query, {
    bool force = false,
  }) async {
    final state = list(kind);
    if (!force && state.query == query && state.status != LoadStatus.idle) {
      return;
    }
    state.query = query;
    state.selected.clear();
    await load(kind);
  }

  Future<void> prepareForm(EntityKind kind, int? id) async {
    await _repository.initialize();
    if (id != null) await _repository.findById(kind, id);
  }

  void cancelList(EntityKind kind) {
    if (_repository case final CancellableCatalogRepository remote) {
      remote.cancelList(kind);
      final state = list(kind);
      if (state.status == LoadStatus.loading) {
        state.request++;
        state.status = LoadStatus.idle;
      }
    }
  }

  Future<void> load(EntityKind kind) async {
    final state = list(kind);
    final request = ++state.request;
    state.status = LoadStatus.loading;
    state.error = null;
    notifyListeners();
    try {
      final result = await _repository.find(kind, state.query);
      if (request != state.request) return;
      state.result = result;
      state.status = LoadStatus.success;
    } on RequestCancelledException {
      return;
    } catch (error) {
      if (request != state.request) return;
      state.error = 'Не удалось загрузить список: $error';
      state.status = LoadStatus.error;
    }
    notifyListeners();
  }

  void toggleSelection(EntityKind kind, int id) {
    final selected = list(kind).selected;
    selected.contains(id) ? selected.remove(id) : selected.add(id);
    notifyListeners();
  }

  void togglePageSelection(EntityKind kind, Iterable<int> ids, bool selected) {
    final target = list(kind).selected;
    selected ? target.addAll(ids) : target.removeAll(ids);
    notifyListeners();
  }

  Future<void> _refresh() async {
    notifyListeners();
    await Future.wait(
      EntityKind.values
          .where((kind) => list(kind).status != LoadStatus.idle)
          .map(load),
    );
  }

  Future<CatalogItem> save(EntityKind kind, CatalogItem item) async {
    final saved = await _repository.save(kind, item);
    await _refresh();
    return saved;
  }

  Future<Supplier> saveSupplierWithLicense(
    Supplier supplier,
    SupplierLicense license,
  ) async {
    final saved = await _repository.saveSupplierWithLicense(supplier, license);
    await _refresh();
    return saved;
  }

  Future<void> softDelete(EntityKind kind, int id) async {
    await _repository.softDelete(kind, id);
    list(kind).selected.remove(id);
    await _refresh();
  }

  Future<void> hardDelete(EntityKind kind, int id) async {
    await _repository.hardDelete(kind, id);
    list(kind).selected.remove(id);
    await _refresh();
  }

  Future<void> restore(EntityKind kind, int id) async {
    await _repository.restore(kind, id);
    await _refresh();
  }

  Future<int> deleteSelected(EntityKind kind) async {
    final state = list(kind);
    final count = await _repository.deleteMany(kind, state.selected.toList());
    state.selected.clear();
    await _refresh();
    return count;
  }

  Future<Drug> dispenseDrug(int id, int quantity) async {
    if (_repository case final DispensingCatalogRepository remote) {
      final drug = await remote.dispenseDrug(id, quantity);
      await _refresh();
      return drug;
    }
    throw const ConflictException(
      'Отпуск доступен только при подключении к серверу.',
    );
  }
}
