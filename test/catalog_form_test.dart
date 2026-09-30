import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmacy_project/core/form_leave_guard.dart';
import 'package:pharmacy_project/models/catalog_item.dart';
import 'package:pharmacy_project/repositories/local_catalog_repository.dart';
import 'package:pharmacy_project/screens/catalog_form_screen.dart';
import 'package:pharmacy_project/state/catalog_store.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('общая форма показывает ошибки у полей и сохраняет категорию', (
    tester,
  ) async {
    final repository = LocalCatalogRepository(SharedPreferencesAsync());
    await repository.initialize();
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
          builder: (_, _) => const Scaffold(body: Text('Карточка')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<FormLeaveGuard>(create: (_) => FormLeaveGuard()),
          ChangeNotifierProvider(create: (_) => CatalogStore(repository)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pump();
    expect(find.text('Заполните поле'), findsNWidgets(2));

    final inputs = find.byType(TextFormField);
    await tester.enterText(inputs.at(0), 'Новая категория');
    await tester.pump();
    expect(find.text('Заполните поле'), findsOneWidget);
    await tester.enterText(inputs.at(1), 'Описание категории');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(
      repository
          .all(EntityKind.categories)
          .where((item) => item.title == 'Новая категория'),
      hasLength(1),
    );
    expect(find.text('Карточка'), findsOneWidget);
  });

  testWidgets('нетронутые поля проверяются только после сохранения', (
    tester,
  ) async {
    final repository = LocalCatalogRepository(SharedPreferencesAsync());
    await repository.initialize();
    final router = GoRouter(
      initialLocation: '/drugs/new',
      routes: [
        GoRoute(
          path: '/drugs/new',
          builder: (_, _) => const CatalogFormScreen(kind: EntityKind.drugs),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<FormLeaveGuard>(create: (_) => FormLeaveGuard()),
          ChangeNotifierProvider(create: (_) => CatalogStore(repository)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Тест');
    await tester.pump();
    expect(find.text('Заполните поле'), findsNothing);
    expect(find.text('Выберите значение'), findsNothing);
    expect(find.text('Выберите хотя бы одно значение'), findsNothing);

    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pump();
    expect(find.text('Заполните поле'), findsWidgets);
    expect(find.text('Выберите значение'), findsWidgets);
    expect(find.text('Выберите хотя бы одно значение'), findsOneWidget);
  });

  testWidgets('уход из изменённой формы требует подтверждения', (tester) async {
    final repository = LocalCatalogRepository(SharedPreferencesAsync());
    await repository.initialize();
    final router = GoRouter(
      initialLocation: '/categories',
      routes: [
        GoRoute(
          path: '/categories',
          builder: (_, _) => const Scaffold(body: Text('Список')),
          routes: [
            GoRoute(
              path: 'new',
              builder: (_, _) =>
                  const CatalogFormScreen(kind: EntityKind.categories),
              onExit: (context, state) =>
                  context.read<FormLeaveGuard>().confirm(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<FormLeaveGuard>(create: (_) => FormLeaveGuard()),
          ChangeNotifierProvider(create: (_) => CatalogStore(repository)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push('/categories/new');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Черновик');
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('Несохранённые изменения'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.text('Черновик'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Уйти'));
    await tester.pumpAndSettle();
    expect(find.text('Список'), findsOneWidget);
  });

  testWidgets('выбор производителя сужает список поставщиков', (tester) async {
    final repository = LocalCatalogRepository(SharedPreferencesAsync());
    await repository.initialize();
    final router = GoRouter(
      initialLocation: '/drugs/new',
      routes: [
        GoRoute(
          path: '/drugs/new',
          builder: (_, _) => const CatalogFormScreen(kind: EntityKind.drugs),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<FormLeaveGuard>(create: (_) => FormLeaveGuard()),
          ChangeNotifierProvider(create: (_) => CatalogStore(repository)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final selectors = find.byType(DropdownButtonFormField<int>);
    await tester.tap(selectors.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bayer').last);
    await tester.pumpAndSettle();

    final supplierSelector = tester.widget<DropdownButton<int>>(
      find.descendant(
        of: find.byType(DropdownButtonFormField<int>).at(1),
        matching: find.byType(DropdownButton<int>),
      ),
    );
    final availableIds = supplierSelector.items!
        .map((option) => option.value)
        .toSet();
    expect(availableIds, contains(2));
    expect(availableIds, isNot(contains(1)));
  });
}
