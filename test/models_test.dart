import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_project/models/catalog_item.dart';
import 'package:pharmacy_project/models/category.dart';
import 'package:pharmacy_project/models/drug.dart';
import 'package:pharmacy_project/models/manufacturer.dart';
import 'package:pharmacy_project/models/supplier.dart';
import 'package:pharmacy_project/models/supplier_license.dart';
import 'package:pharmacy_project/models/reservation.dart';
import 'package:pharmacy_project/models/auth_user.dart';
import 'support/fake_api_adapter.dart';

void main() {
  final factories = <String, CatalogItem Function(Map<String, dynamic>)>{
    'препарат': Drug.fromJson,
    'поставщик': Supplier.fromJson,
    'производитель': Manufacturer.fromJson,
    'категория': Category.fromJson,
    'лицензия': SupplierLicense.fromJson,
  };
  for (final entry in factories.entries) {
    test('${entry.key}: отсутствующие и null-поля, JSON round-trip', () {
      final empty = entry.value({});
      final nullable = entry.value({
        for (final key in empty.toJson().keys) key: null,
      });
      expect(nullable.toJson(), empty.toJson());
      final dated = empty.withId(7).withDeletedAt(DateTime.utc(2026, 10, 7));
      expect(entry.value(dated.toJson()).toJson(), dated.toJson());
      expect(dated.isDeleted, true);
      expect(dated.withDeletedAt(null).isDeleted, false);
    });
  }
  test('препарат разбирает вложенные связи API и строковые числа', () {
    final drug = Drug.fromJson({...drugJson(1), 'price': '12.5', 'stock': '7'});
    expect(drug.manufacturerId, 1);
    expect(drug.supplierId, 1);
    expect(drug.categoryIds, [1]);
    expect(drug.price, 12.5);
    expect(drug.stock, 7);
    expect(drug.copyWith(stock: 0).name, drug.name);
    expect(drug.stock, 7);
  });
  test('неизвестная роль не повышает права', () {
    expect(AuthUser.fromJson({'role': 'superadmin'}).role, AppRole.customer);
  });
  test('бронирование: пустой JSON, невалидная дата и round-trip', () {
    final item = Reservation.fromJson({'expiresAt': 'не дата'});
    expect(item.expiresAt, DateTime.fromMillisecondsSinceEpoch(0));
    expect(item.quantity, 0);
    expect(Reservation.fromJson(item.toJson()).toJson(), item.toJson());
  });
}
