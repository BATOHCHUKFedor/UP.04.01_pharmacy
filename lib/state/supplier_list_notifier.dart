import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/page_result.dart';
import '../models/supplier.dart';
import '../models/supplier_query.dart';
import '../repositories/supplier_repository.dart';
import 'load_status.dart';

class SupplierListNotifier extends ChangeNotifier {
  final SupplierRepository _repository;
  SupplierListNotifier(this._repository);

  SupplierQuery _query = const SupplierQuery();
  PageResult<Supplier> _result = PageResult.empty();
  LoadStatus _status = LoadStatus.idle;
  String? _error;
  final Set<int> _selected = {};
  int _requestNumber = 0;

  SupplierQuery get query => _query;
  PageResult<Supplier> get result => _result;
  LoadStatus get status => _status;
  String? get error => _error;
  UnmodifiableSetView<int> get selected => UnmodifiableSetView(_selected);
  bool get hasSelection => _selected.isNotEmpty;

  Future<void> applyQuery(SupplierQuery next, {bool force = false}) async {
    if (!force && next == _query && _status != LoadStatus.idle) return;
    _query = next;
    _selected.clear();
    await load();
  }

  Future<void> load() async {
    final request = ++_requestNumber;
    _status = LoadStatus.loading;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.find(_query);
      if (request != _requestNumber) return;
      _result = result;
      _status = LoadStatus.success;
    } catch (error) {
      if (request != _requestNumber) return;
      _error = 'Не удалось загрузить поставщиков: $error';
      _status = LoadStatus.error;
    }
    notifyListeners();
  }

  void toggleSelection(int id) {
    _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
    notifyListeners();
  }

  void togglePageSelection(Iterable<int> ids, bool selected) {
    selected ? _selected.addAll(ids) : _selected.removeAll(ids);
    notifyListeners();
  }

  Future<int> deleteSelected() async {
    final count = await _repository.deleteMany(_selected.toList());
    _selected.clear();
    await load();
    return count;
  }

  Future<void> softDelete(int id) async {
    await _repository.softDelete(id);
    _selected.remove(id);
    await load();
  }

  Future<void> hardDelete(int id) async {
    await _repository.hardDelete(id);
    _selected.remove(id);
    await load();
  }

  Future<void> restore(int id) async {
    await _repository.restore(id);
    await load();
  }
}
