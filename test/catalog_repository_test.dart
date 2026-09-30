import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_project/models/catalog_item.dart';
import 'package:pharmacy_project/models/catalog_query.dart';
import 'package:pharmacy_project/models/category.dart';
import 'package:pharmacy_project/models/drug.dart';
import 'package:pharmacy_project/models/manufacturer.dart';
import 'package:pharmacy_project/models/supplier.dart';
import 'package:pharmacy_project/models/supplier_license.dart';
import 'package:pharmacy_project/repositories/catalog_repository.dart';
import 'package:pharmacy_project/repositories/local_catalog_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  LocalCatalogRepository repository() =>
      LocalCatalogRepository(SharedPreferencesAsync());

  test('изменения читаются новым экземпляром репозитория', () async {
    final first = repository();
    await first.initialize();
    final created =
        await first.save(
              EntityKind.drugs,
              const Drug(
                id: 0,
                name: 'Тестовый препарат',
                registrationNumber: 'ТЕСТ-0001',
                categoryIds: [1],
                manufacturerId: 1,
                supplierId: 1,
                productionYear: 2025,
                price: 120,
                stock: 10,
              ),
            )
            as Drug;
    final second = repository();
    await second.initialize();
    expect(
      (second.byId(EntityKind.drugs, created.id) as Drug).name,
      'Тестовый препарат',
    );

    await second.softDelete(EntityKind.drugs, created.id);
    final third = repository();
    await third.initialize();
    expect(third.byId(EntityKind.drugs, created.id)!.isDeleted, isTrue);
    expect(
      (await third.find(EntityKind.drugs, const CatalogQuery())).total,
      24,
    );

    await third.restore(EntityKind.drugs, created.id);
    final fourth = repository();
    await fourth.initialize();
    expect(fourth.byId(EntityKind.drugs, created.id)!.isDeleted, isFalse);
    await fourth.hardDelete(EntityKind.drugs, created.id);
    final fifth = repository();
    await fifth.initialize();
    expect(fifth.byId(EntityKind.drugs, created.id), isNull);
  });

  test('дубликаты показывают ключ конкретного поля', () async {
    final repo = repository();
    await repo.initialize();
    await expectLater(
      repo.save(
        EntityKind.drugs,
        const Drug(
          id: 0,
          name: 'Дубликат',
          registrationNumber: 'ЛП-001201',
          categoryIds: [1],
          manufacturerId: 1,
          supplierId: 1,
          productionYear: 2025,
          price: 100,
          stock: 5,
        ),
      ),
      throwsA(
        isA<FieldIssue>().having(
          (error) => error.field,
          'field',
          'registrationNumber',
        ),
      ),
    );
    await expectLater(
      repo.save(
        EntityKind.suppliers,
        const Supplier(
          id: 0,
          name: 'Дубликат',
          contactPerson: 'Контакт',
          country: 'Россия',
          phone: '123',
          email: 'order@pharmstandard.ru',
          partnershipYear: 2025,
          manufacturerIds: [1],
        ),
      ),
      throwsA(
        isA<FieldIssue>().having((error) => error.field, 'field', 'email'),
      ),
    );
  });

  test(
    'производитель с препаратами не удаляется и сообщает количество',
    () async {
      final repo = repository();
      await repo.initialize();
      await expectLater(
        repo.hardDelete(EntityKind.manufacturers, 1),
        throwsA(
          isA<RelationIssue>().having(
            (error) => error.message,
            'message',
            contains('4'),
          ),
        ),
      );
      expect(repo.byId(EntityKind.manufacturers, 1), isNotNull);
    },
  );

  test(
    'лицензия сохраняется вместе с поставщиком и следует за удалением',
    () async {
      final repo = repository();
      await repo.initialize();
      final supplier = await repo.saveSupplierWithLicense(
        const Supplier(
          id: 0,
          name: 'Новый поставщик',
          contactPerson: 'Контакт',
          country: 'Россия',
          phone: '123',
          email: 'new@example.com',
          partnershipYear: 2025,
          manufacturerIds: [1],
        ),
        const SupplierLicense(
          id: 0,
          supplierId: 0,
          number: 'ЛИЦ-NEW',
          issuedYear: 2025,
          expiresYear: 2035,
        ),
      );
      final license = repo
          .all(EntityKind.licenses)
          .cast<SupplierLicense>()
          .singleWhere((item) => item.supplierId == supplier.id);
      await repo.softDelete(EntityKind.suppliers, supplier.id);
      expect(repo.byId(EntityKind.licenses, license.id)!.isDeleted, isTrue);
      await repo.restore(EntityKind.suppliers, supplier.id);
      expect(repo.byId(EntityKind.licenses, license.id)!.isDeleted, isFalse);
      await repo.hardDelete(EntityKind.suppliers, supplier.id);
      expect(repo.byId(EntityKind.licenses, license.id), isNull);
    },
  );

  test('сочетание поиска, категории, поставщика и года', () async {
    final repo = repository();
    await repo.initialize();
    final result = await repo.find(
      EntityKind.drugs,
      const CatalogQuery(
        search: 'Парацетамол',
        categoryId: 1,
        manufacturerId: 1,
        supplierId: 1,
        yearFrom: 2020,
        yearTo: 2020,
      ),
    );
    expect(result.total, 1);
    expect(result.items.single.title, 'Парацетамол');
  });

  test('fromJson принимает отсутствующие и null-поля', () {
    final data = <String, dynamic>{'id': null, 'deletedAt': null};
    expect(Drug.fromJson(data).categoryIds, isEmpty);
    expect(Supplier.fromJson(data).manufacturerIds, isEmpty);
    expect(Manufacturer.fromJson(data).name, '');
    expect(Category.fromJson(data).description, '');
    expect(SupplierLicense.fromJson(data).expiresYear, 0);
  });

  test('повреждённая версия хранилища не приводит к падению', () async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString('pharmacy.catalog.v2', '{broken');
    final repo = repository();
    await repo.initialize();
    expect(repo.storageNotice, isNotNull);
    expect(repo.all(EntityKind.drugs), hasLength(24));
  });
}
