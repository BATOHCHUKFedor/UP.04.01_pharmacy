import '../models/page_result.dart';
import '../models/supplier.dart';
import '../models/supplier_query.dart';

abstract interface class SupplierRepository {
  Future<PageResult<Supplier>> find(SupplierQuery query);
  Future<Supplier?> findById(int id);
  Future<Supplier> create(Supplier supplier);
  Future<Supplier> update(Supplier supplier);
  Future<void> softDelete(int id);
  Future<void> hardDelete(int id);
  Future<void> restore(int id);
  Future<int> deleteMany(List<int> ids);
}
