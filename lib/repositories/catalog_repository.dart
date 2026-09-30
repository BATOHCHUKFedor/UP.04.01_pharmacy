import '../models/catalog_item.dart';
import '../models/catalog_query.dart';
import '../models/page_result.dart';
import '../models/supplier.dart';
import '../models/supplier_license.dart';

class FieldIssue implements Exception {
  final String field;
  final String message;
  const FieldIssue(this.field, this.message);
  @override
  String toString() => message;
}

class RelationIssue implements Exception {
  final String message;
  const RelationIssue(this.message);
  @override
  String toString() => message;
}

abstract interface class CatalogRepository {
  String? get storageNotice;
  Future<void> initialize();
  List<CatalogItem> all(EntityKind kind, {bool includeDeleted = false});
  CatalogItem? byId(EntityKind kind, int id);
  Future<CatalogItem?> findById(EntityKind kind, int id);
  Future<PageResult<CatalogItem>> find(EntityKind kind, CatalogQuery query);
  Future<CatalogItem> save(EntityKind kind, CatalogItem item);
  Future<Supplier> saveSupplierWithLicense(
    Supplier supplier,
    SupplierLicense license,
  );
  Future<void> softDelete(EntityKind kind, int id);
  Future<void> hardDelete(EntityKind kind, int id);
  Future<void> restore(EntityKind kind, int id);
  Future<int> deleteMany(EntityKind kind, List<int> ids);
}
