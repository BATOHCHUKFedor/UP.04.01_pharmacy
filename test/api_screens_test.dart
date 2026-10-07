import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pharmacy_project/core/api_client.dart';
import 'package:pharmacy_project/core/form_leave_guard.dart';
import 'package:pharmacy_project/models/catalog_item.dart';
import 'package:pharmacy_project/models/catalog_query.dart';
import 'package:pharmacy_project/repositories/api_catalog_repository.dart';
import 'package:pharmacy_project/screens/catalog_form_screen.dart';
import 'package:pharmacy_project/screens/catalog_list_screen.dart';
import 'package:pharmacy_project/state/catalog_store.dart';

import 'support/fake_api_adapter.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    GoRouter router,
    ApiHandler handler,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dio = buildDio(baseUrl: 'http://test/api');
    dio.httpClientAdapter = FakeApiAdapter(
      (options, cancel) => options.path == '/references'
          ? jsonResponse(referencesJson)
          : handler(options, cancel),
    );
    final store = CatalogStore(
      ApiCatalogRepository(dio, retryPauses: const []),
    );
    addTearDown(() {
      router.dispose();
      store.dispose();
      dio.close(force: true);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<FormLeaveGuard>(create: (_) => FormLeaveGuard()),
          ChangeNotifierProvider.value(value: store),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  testWidgets(
    'список показывает загрузку, данные, пустой результат, ошибку и повтор',
    (tester) async {
      final delayed = Completer<ResponseBody>();
      var fail = true;
      final router = GoRouter(
        initialLocation: '/drugs',
        routes: [
          GoRoute(
            path: '/drugs',
            builder: (_, state) => CatalogListScreen(
              kind: EntityKind.drugs,
              query: CatalogQuery.fromParameters(state.uri.queryParameters),
            ),
          ),
        ],
      );
      await mount(tester, router, (options, _) {
        if (options.queryParameters['search'] == 'пусто') {
          return jsonResponse({'items': [], 'page': 1, 'size': 10, 'total': 0});
        }
        if (options.queryParameters['__fail'] != null && fail) {
          return jsonResponse({'message': 'Принудительная ошибка'}, 500);
        }
        if (!delayed.isCompleted) return delayed.future;
        return jsonResponse(pageJson(1));
      });
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      delayed.complete(jsonResponse(pageJson(1)));
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsOneWidget);
      router.go('/drugs?search=пусто');
      await tester.pumpAndSettle();
      expect(find.text('По заданным условиям записей нет'), findsOneWidget);
      router.go('/drugs?__fail=500');
      await tester.pumpAndSettle();
      expect(find.textContaining('Принудительная ошибка'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsOneWidget);
    },
  );

  testWidgets(
    'серверный 422 показывает несколько ошибок непосредственно под полями',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/drugs/1/edit',
        routes: [
          GoRoute(
            path: '/drugs/1/edit',
            builder: (_, _) =>
                const CatalogFormScreen(kind: EntityKind.drugs, id: 1),
          ),
        ],
      );
      await mount(
        tester,
        router,
        (options, _) => options.method == 'GET'
            ? jsonResponse(drugJson(1))
            : jsonResponse({
                'errors': {
                  'registrationNumber': 'Номер уже существует',
                  'name': 'Название отклонено сервером',
                },
              }, 422),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Номер уже существует'), findsOneWidget);
      expect(find.text('Название отклонено сервером'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('двойное нажатие при сохранении отправляет только один POST', (
    tester,
  ) async {
    final response = Completer<ResponseBody>();
    var posts = 0;
    final router = GoRouter(
      initialLocation: '/categories/new',
      routes: [
        GoRoute(
          path: '/categories/new',
          builder: (_, _) =>
              const CatalogFormScreen(kind: EntityKind.categories),
        ),
        GoRoute(
          path: '/categories/:id',
          builder: (_, _) => const Scaffold(body: Text('Сохранено')),
        ),
      ],
    );
    await mount(tester, router, (_, _) {
      posts++;
      return response.future;
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Категория');
    await tester.enterText(find.byType(TextFormField).last, 'Описание');
    await tester.tap(find.text('Сохранить'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Сохранить'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(posts, 1);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField).first).enabled,
      false,
    );
    response.complete(
      jsonResponse({
        'id': 7,
        'name': 'Категория',
        'description': 'Описание',
      }, 201),
    );
    await tester.pumpAndSettle();
    expect(find.text('Сохранено'), findsOneWidget);
  });
}
