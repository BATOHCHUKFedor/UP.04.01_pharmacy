import '../models/drug.dart';
import '../models/drug_query.dart';
import '../models/page_result.dart';

abstract interface class DrugRepository {
  Future<PageResult<Drug>> find(DrugQuery query);
  Future<Drug?> findById(int id);
  Future<Drug> create(Drug drug);
  Future<Drug> update(Drug drug);
  Future<void> softDelete(int id);
  Future<void> hardDelete(int id);
  Future<void> restore(int id);
  Future<int> deleteMany(List<int> ids);
}
