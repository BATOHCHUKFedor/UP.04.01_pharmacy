import 'package:flutter/foundation.dart';

import '../models/drug.dart';
import '../repositories/drug_repository.dart';
import 'load_status.dart';

class DrugDetailsNotifier extends ChangeNotifier {
  final DrugRepository _repository;
  DrugDetailsNotifier(this._repository);

  Drug? _drug;
  LoadStatus _status = LoadStatus.idle;
  String? _error;

  Drug? get drug => _drug;
  LoadStatus get status => _status;
  String? get error => _error;

  Future<void> load(int id) async {
    _status = LoadStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _drug = await _repository.findById(id);
      _status = LoadStatus.success;
    } catch (error) {
      _error = 'Не удалось загрузить препарат: $error';
      _status = LoadStatus.error;
    }
    notifyListeners();
  }
}
