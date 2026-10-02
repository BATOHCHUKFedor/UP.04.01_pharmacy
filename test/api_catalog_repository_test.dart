import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_project/core/api_client.dart';
import 'package:pharmacy_project/core/api_exceptions.dart';
import 'package:pharmacy_project/models/catalog_item.dart';
import 'package:pharmacy_project/models/catalog_query.dart';
import 'package:pharmacy_project/models/drug.dart';
import 'package:pharmacy_project/repositories/api_catalog_repository.dart';

import 'support/fake_api_adapter.dart';

void main() {
  late Dio dio;
  late ApiCatalogRepository repo;
  FakeApiAdapter connect(ApiHandler handler) {
    final adapter = FakeApiAdapter((options, cancellation) {
      if (options.path == '/references') return jsonResponse(referencesJson);
      return handler(options, cancellation);
    });
    dio.httpClientAdapter = adapter;
    return adapter;
  }

  setUp(() {
    dio = buildDio(baseUrl: 'http://test/api');
    repo = ApiCatalogRepository(dio, retryPauses: const []);
  });
  tearDown(() => dio.close(force: true));

  test('условия и диагностические параметры уходят серверу', () async {
    final adapter = connect(
      (options, _) => jsonResponse(pageJson(11, page: 2)),
    );
    final result = await repo.find(
      EntityKind.drugs,
      const CatalogQuery(
        search: 'аспирин',
        categoryId: 1,
        manufacturerId: 1,
        supplierId: 1,
        yearFrom: 2020,
        yearTo: 2025,
        sortField: 'year',
        ascending: false,
        page: 2,
        size: 25,
        includeDeleted: true,
        debugDelay: 1500,
        debugFail: 500,
      ),
    );
    final q = adapter.requests.last.queryParameters;
    expect(q['search'], 'аспирин');
    expect(q['sort'], 'year,desc');
    expect(q['page'], 2);
    expect(q['size'], 25);
    expect(q['__delay'], '1500');
    expect(q['__fail'], '500');
    expect(result.page, 2);
    final drug = result.items.single as Drug;
    expect(drug.manufacturerId, 1);
    expect(drug.supplierId, 1);
    expect(drug.categoryIds, [1]);
  });

  test('новая страница запрашивается и заменяет предыдущую', () async {
    final adapter = connect(
      (options, _) => jsonResponse(
        pageJson(
          options.queryParameters['page'] == 2 ? 11 : 1,
          page: options.queryParameters['page'] as int,
        ),
      ),
    );
    await repo.find(EntityKind.drugs, const CatalogQuery());
    await repo.find(EntityKind.drugs, const CatalogQuery(page: 2));
    expect(adapter.requests.where((r) => r.path == '/drugs'), hasLength(2));
    expect(repo.byId(EntityKind.drugs, 1), isNull);
    expect(repo.all(EntityKind.drugs).single.id, 11);
  });

  test(
    '422 сохраняет все ошибки полей и не превращается в DioException',
    () async {
      connect(
        (_, _) => jsonResponse({
          'message': 'Проверьте поля',
          'errors': {
            'registrationNumber': 'Номер уже существует',
            'name': 'Слишком длинное название',
          },
        }, 422),
      );
      await expectLater(
        repo.save(EntityKind.drugs, Drug.fromJson(drugJson(0))),
        throwsA(
          isA<ValidationException>().having((e) => e.errors, 'errors', {
            'registrationNumber': 'Номер уже существует',
            'name': 'Слишком длинное название',
          }),
        ),
      );
    },
  );

  test('недоступный сервер: три попытки чтения и NetworkException', () async {
    final adapter = connect(
      (options, _) => throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      ),
    );
    await expectLater(
      repo.find(EntityKind.drugs, const CatalogQuery()),
      throwsA(isA<NetworkException>()),
    );
    expect(adapter.requests.where((r) => r.path == '/drugs'), hasLength(3));
  });

  test('чтение восстанавливается после двух сетевых сбоев', () async {
    var attempts = 0;
    connect((options, _) {
      if (++attempts < 3) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'offline',
        );
      }
      return jsonResponse(pageJson(1));
    });
    expect(
      (await repo.find(EntityKind.drugs, const CatalogQuery())).items,
      hasLength(1),
    );
    expect(attempts, 3);
  });

  test('создание при сетевом сбое не повторяется', () async {
    final adapter = connect(
      (options, _) => throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      ),
    );
    await expectLater(
      repo.save(EntityKind.drugs, Drug.fromJson(drugJson(0))),
      throwsA(isA<NetworkException>()),
    );
    expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
  });

  test('409 при отпуске становится понятным ConflictException', () async {
    connect(
      (_, _) =>
          jsonResponse({'message': 'Недостаточно упаковок. Доступно: 0'}, 409),
    );
    await expectLater(
      repo.dispenseDrug(1, 1),
      throwsA(
        isA<ConflictException>().having(
          (e) => e.message,
          'message',
          contains('Доступно: 0'),
        ),
      ),
    );
  });

  test('500 становится ServerException и не повторяется', () async {
    final adapter = connect(
      (_, _) => jsonResponse({'message': 'Тестовая ошибка'}, 500),
    );
    await expectLater(
      repo.find(EntityKind.drugs, const CatalogQuery()),
      throwsA(isA<ServerException>()),
    );
    expect(adapter.requests.where((r) => r.path == '/drugs'), hasLength(1));
  });

  test(
    'CancelToken отменяет старый поиск и его результат не попадает в кэш',
    () async {
      final started = Completer<void>();
      final oldResponse = Completer<ResponseBody>();
      final cancelled = Completer<void>();
      connect((options, cancellation) {
        if (options.queryParameters['search'] == 'старый') {
          cancellation?.then((_) {
            if (!cancelled.isCompleted) cancelled.complete();
          });
          started.complete();
          return oldResponse.future;
        }
        return jsonResponse(pageJson(2));
      });
      final old = repo.find(
        EntityKind.drugs,
        const CatalogQuery(search: 'старый'),
      );
      final oldCheck = expectLater(
        old,
        throwsA(isA<RequestCancelledException>()),
      );
      await started.future;
      final newest = await repo.find(
        EntityKind.drugs,
        const CatalogQuery(search: 'новый'),
      );
      await cancelled.future;
      await oldCheck;
      oldResponse.complete(jsonResponse(pageJson(1)));
      expect(newest.items.single.id, 2);
      expect(repo.byId(EntityKind.drugs, 1), isNull);
      expect(repo.all(EntityKind.drugs).single.id, 2);
    },
  );

  test(
    'справочники загружаются один раз при повторных и параллельных открытиях',
    () async {
      final adapter = connect((_, _) => jsonResponse(drugJson(1)));
      await Future.wait([repo.initialize(), repo.initialize()]);
      await repo.findById(EntityKind.drugs, 1);
      await repo.initialize();
      expect(
        adapter.requests.where((r) => r.path == '/references'),
        hasLength(1),
      );
      expect(repo.all(EntityKind.manufacturers).single.title, 'Завод');
    },
  );

  test(
    'физическое удаление и восстановление используют разные API операции',
    () async {
      final adapter = connect((options, _) => jsonResponse(drugJson(1)));
      await repo.softDelete(EntityKind.drugs, 1);
      await repo.restore(EntityKind.drugs, 1);
      await repo.hardDelete(EntityKind.drugs, 1);
      expect(adapter.requests.map((r) => '${r.method} ${r.path}'), [
        'DELETE /drugs/1',
        'POST /drugs/1/restore',
        'DELETE /drugs/1',
      ]);
      expect(adapter.requests.last.queryParameters['hard'], true);
    },
  );

  test(
    '404 карточки даёт пустой результат и удаляет старую запись из кэша',
    () async {
      connect(
        (options, _) => options.path == '/drugs'
            ? jsonResponse(pageJson(1))
            : jsonResponse({'message': 'Не найдено'}, 404),
      );
      await repo.find(EntityKind.drugs, const CatalogQuery());
      expect(await repo.findById(EntityKind.drugs, 1), isNull);
      expect(repo.byId(EntityKind.drugs, 1), isNull);
    },
  );
}
