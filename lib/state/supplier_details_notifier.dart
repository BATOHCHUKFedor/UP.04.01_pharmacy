import 'package:flutter/foundation.dart';

import '../models/supplier.dart';
import '../repositories/supplier_repository.dart';
import 'load_status.dart';

class SupplierDetailsNotifier extends ChangeNotifier {
  final SupplierRepository _repository;
  SupplierDetailsNotifier(this._repository);

  Supplier? _supplier;
  LoadStatus _status = LoadStatus.idle;
  String? _error;

  Supplier? get supplier => _supplier;
  LoadStatus get status => _status;
  String? get error => _error;

  Future<void> load(int id) async {
    _status = LoadStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _supplier = await _repository.findById(id);
      _status = LoadStatus.success;
    } catch (error) {
      _error = 'Не удалось загрузить поставщика: $error';
      _status = LoadStatus.error;
    }
    notifyListeners();
  }
}
