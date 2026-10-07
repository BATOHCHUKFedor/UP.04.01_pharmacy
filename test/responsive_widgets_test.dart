import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pharmacy_project/core/api_client.dart';
import 'package:pharmacy_project/core/form_leave_guard.dart';
import 'package:pharmacy_project/models/auth_user.dart';
import 'package:pharmacy_project/models/catalog_item.dart';
import 'package:pharmacy_project/models/catalog_query.dart';
import 'package:pharmacy_project/repositories/api_catalog_repository.dart';
import 'package:pharmacy_project/screens/catalog_form_screen.dart';
import 'package:pharmacy_project/screens/catalog_list_screen.dart';
import 'package:pharmacy_project/screens/auth_screen.dart';
import 'package:pharmacy_project/state/auth_notifier.dart';
import 'package:pharmacy_project/state/catalog_store.dart';
import 'package:pharmacy_project/state/load_status.dart';
import 'package:pharmacy_project/widgets/screen_state_view.dart';
import 'package:pharmacy_project/widgets/entity_card_list.dart';
import 'package:pharmacy_project/widgets/responsive_cards.dart';
import 'auth_test.dart' show FakeAuthRepository, MemorySessionStorage;
import 'support/fake_api_adapter.dart';

void main() {
  void viewport(WidgetTester tester, double width, {double height = 900}) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> stateView(
    WidgetTester tester,
    LoadStatus status, {
    bool empty = false,
    VoidCallback? retry,
  }) async {
    viewport(tester, 360, height: 320);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScreenStateView(
            status: status,
            isEmpty: empty,
            emptyMessage: 'Ничего не найдено',
            error: 'Сервер недоступен. Проверьте соединение.',
            onRetry: retry ?? () {},
            child: const Text('Данные'),
          ),
        ),
      ),
    );
  }

  testWidgets('загрузка: видимый индикатор и семантическая подпись', (
    tester,
  ) async {
    await stateView(tester, LoadStatus.loading);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('Загрузка данных'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('пустой результат отличается от ошибки', (tester) async {
    await stateView(tester, LoadStatus.success, empty: true);
    expect(find.text('Ничего не найдено'), findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
    expect(find.byIcon(Icons.search_off), findsOneWidget);
  });
  testWidgets('ошибка и кнопка повтора, работающая с клавиатуры', (
    tester,
  ) async {
    var retries = 0;
    await stateView(tester, LoadStatus.error, retry: () => retries++);
    expect(find.textContaining('Сервер недоступен'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  Future<(GoRouter, FakeApiAdapter)> catalog(
    WidgetTester tester, {
    AppRole role = AppRole.admin,
    String route = '/drugs',
    ApiHandler? handler,
  }) async {
    final now = DateTime.now();
    final repository = FakeAuthRepository(now);
    (repository.data['user'] as Map<String, dynamic>)['role'] = role.name;
    final auth = AuthNotifier(
      repository,
      MemorySessionStorage(),
      timers: false,
    );
    await auth.login({});
    final dio = buildDio(baseUrl: 'http://test/api');
    final adapter = FakeApiAdapter(
      (options, cancel) => options.path == '/references'
          ? jsonResponse(referencesJson)
          : handler?.call(options, cancel) ?? jsonResponse(pageJson(1)),
    );
    dio.httpClientAdapter = adapter;
    final store = CatalogStore(
      ApiCatalogRepository(dio, retryPauses: const []),
    );
    final router = GoRouter(
      initialLocation: route,
      routes: [
        GoRoute(
          path: '/drugs',
          builder: (_, state) => CatalogListScreen(
            kind: EntityKind.drugs,
            query: CatalogQuery.fromParameters(state.uri.queryParameters),
          ),
        ),
        GoRoute(
          path: '/categories/new',
          builder: (_, _) =>
              const CatalogFormScreen(kind: EntityKind.categories),
        ),
      ],
    );
    addTearDown(() {
      router.dispose();
      store.dispose();
      auth.dispose();
      dio.close(force: true);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: store),
          Provider(create: (_) => FormLeaveGuard()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    return (router, adapter);
  }

  testWidgets('валидация нескольких полей только после Сохранить', (
    tester,
  ) async {
    viewport(tester, 360);
    await catalog(tester, route: '/categories/new');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '');
    expect(find.text('Заполните поле'), findsNothing);
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Заполните поле'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('недоступная пользователю кнопка создания скрыта', (
    tester,
  ) async {
    viewport(tester, 360);
    await catalog(tester, role: AppRole.customer);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Создать'), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
  testWidgets(
    'живое изменение 360/768/1280/1920: карточки, таблица, навигация без переполнений',
    (tester) async {
      viewport(tester, 360);
      await catalog(tester);
      await tester.pumpAndSettle();
      for (final width in [360.0, 768.0, 1280.0, 1920.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        expect(
          find.byType(DataTable),
          width >= 1280 ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(EntityCardList<CatalogItem>),
          width < 1280 ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(NavigationBar),
          width < 600 ? findsOneWidget : findsNothing,
        );
        await tester.tap(find.text('Поиск и фильтры'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Ширина $width');
      }
    },
  );
  testWidgets('связь восстанавливается по Повторить без пересоздания экрана', (
    tester,
  ) async {
    viewport(tester, 360);
    var offline = true;
    await catalog(
      tester,
      handler: (options, _) {
        if (offline) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }
        return jsonResponse(pageJson(1));
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Повторить'), findsOneWidget);
    offline = false;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Препарат 1'), findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
  });
  testWidgets('две карточки в строке при 768, одна при 360; длинные данные', (
    tester,
  ) async {
    viewport(tester, 768);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResponsiveCards(
            children: [
              for (var i = 0; i < 4; i++)
                Card(child: Text('Длинное название ' * 30)),
            ],
          ),
        ),
      ),
    );
    final rows = find.descendant(
      of: find.byType(ResponsiveCards),
      matching: find.byType(Row),
    );
    expect(
      tester.widget<Row>(rows.first).children.whereType<Expanded>().length,
      2,
    );
    tester.view.physicalSize = const Size(360, 900);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Row>(rows.first).children.whereType<Expanded>().length,
      1,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'в форме входа Enter на логине переходит к паролю, а не отправляет форму',
    (tester) async {
      viewport(tester, 360);
      final repository = FakeAuthRepository(DateTime.now());
      final auth = AuthNotifier(
        repository,
        MemorySessionStorage(),
        timers: false,
      );
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(home: AuthScreen()),
        ),
      );
      await tester.tap(find.byType(TextFormField).first);
      await tester.enterText(find.byType(TextFormField).first, 'customer');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(find.text('Заполните поле'), findsNothing);
      expect(repository.logins, 0);
      expect(FocusManager.instance.primaryFocus?.hasFocus, true);
    },
  );
  testWidgets('короткое окно и масштаб текста не ломают сообщения', (
    tester,
  ) async {
    viewport(tester, 360, height: 250);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: ScreenStateView(
              status: LoadStatus.error,
              isEmpty: false,
              emptyMessage: '',
              error: 'Очень длинное сообщение об ошибке ' * 20,
              onRetry: () {},
              child: const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Повторить'));
    expect(tester.takeException(), isNull);
  });
}
