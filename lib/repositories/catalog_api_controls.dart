import '../models/catalog_item.dart';
import '../models/drug.dart';

/// Дополнительные возможности API без изменения контракта CatalogRepository.
abstract interface class CancellableCatalogRepository {
  void cancelList(EntityKind kind);
}

abstract interface class DispensingCatalogRepository {
  Future<Drug> dispenseDrug(int id, int quantity);
}
