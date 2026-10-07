import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pharmacy_project/core/access_policy.dart';
import 'package:pharmacy_project/core/api_client.dart';
import 'package:pharmacy_project/core/api_exceptions.dart';
import 'package:pharmacy_project/core/auth_validators.dart';
import 'package:pharmacy_project/core/router.dart';
import 'package:pharmacy_project/models/auth_user.dart';
import 'package:pharmacy_project/repositories/auth_repository.dart';
import 'package:pharmacy_project/screens/auth_screen.dart';
import 'package:pharmacy_project/state/auth_notifier.dart';
import 'package:pharmacy_project/widgets/app_scaffold.dart';
import 'support/fake_api_adapter.dart';

class MemorySessionStorage implements SessionStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class FakeAuthRepository implements AuthRepository {
  int refreshes = 0;
  int logouts = 0;
  int logins = 0;
  Object? loginError;
  Object? meError;
  Object? refreshError;
  Completer<Map<String, dynamic>>? refreshCompleter;
  late Map<String, dynamic> data;
  FakeAuthRepository(DateTime time) {
    data = {
      'user': {
        'id': 1,
        'username': 'user',
        'name': 'Пользователь',
        'role': 'customer',
        'active': true,
      },
      'accessToken': 'access-old',
      'refreshToken': 'refresh-old',
      'session': {
        'id': 'session',
        'startedAt': time.millisecondsSinceEpoch,
        'lastActivity': time.millisecondsSinceEpoch,
        'expiresAt': time.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        'idleSeconds': 180,
        'warningSeconds': 30,
      },
    };
  }
  @override
  Future<Map<String, dynamic>> login(
    Map<String, dynamic> fields, {
    bool register = false,
  }) async {
    logins++;
    if (loginError != null) throw loginError!;
    return data;
  }

  @override
  Future<Map<String, dynamic>> me(String token) async {
    if (meError != null) throw meError!;
    return data;
  }

  @override
  Future<Map<String, dynamic>> refresh(String token) async {
    refreshes++;
    if (refreshError != null) throw refreshError!;
    if (refreshCompleter != null) return refreshCompleter!.future;
    return {
      ...data,
      'accessToken': 'access-new',
      'refreshToken': 'refresh-new',
    };
  }

  @override
  Future<void> logout(String token) async {
    logouts++;
  }

  @override
  Future<void> activity(String token) async {}
}

void main() {
  final initialTime = DateTime.utc(2026, 10, 7);
  late DateTime time;
  late FakeAuthRepository repository;
  late MemorySessionStorage storage;
  late AuthNotifier auth;
  setUp(() {
    time = initialTime;
    repository = FakeAuthRepository(time);
    storage = MemorySessionStorage();
    auth = AuthNotifier(repository, storage, clock: () => time, timers: false);
  });
  tearDown(() => auth.dispose());

  test('пользователь читает, но не меняет каталог', () {
    expect(roleAllows(AppRole.customer, Permission.read), true);
    for (final action in [
      Permission.write,
      Permission.delete,
      Permission.hardDelete,
      Permission.restore,
    ]) {
      expect(roleAllows(AppRole.customer, action), false);
    }
  });
  test('фармaцевт изменяет и отпускает; не управляет ролями', () {
    expect(roleAllows(AppRole.pharmacist, Permission.write), true);
    expect(roleAllows(AppRole.pharmacist, Permission.dispense), true);
    expect(roleAllows(AppRole.pharmacist, Permission.users), false);
  });
  test('только admin восстанавливает и физически удаляет', () {
    for (final role in AppRole.values) {
      expect(roleAllows(role, Permission.restore), role == AppRole.admin);
      expect(roleAllows(role, Permission.hardDelete), role == AppRole.admin);
    }
  });
  test('у каждой роли собственный экран, недоступный обеим другим', () {
    for (final entry in {
      AppRole.customer: '/my-reservations',
      AppRole.pharmacist: '/work/reservations',
      AppRole.admin: '/admin/users',
    }.entries) {
      for (final role in AppRole.values) {
        expect(canOpenRoute(role, entry.value), role == entry.key);
      }
    }
  });
  test('администратор не выдаёт бронирования и не продлевает чужие', () {
    expect(roleAllows(AppRole.admin, Permission.reservations), false);
    expect(roleAllows(AppRole.admin, Permission.extend), false);
    expect(roleAllows(AppRole.customer, Permission.extend), true);
  });
  test('ручные адреса создания и справочников запрещены пользователю', () {
    for (final route in [
      '/drugs/new',
      '/drugs/2/edit',
      '/suppliers',
      '/licenses/1',
      '/admin/users/',
      '/work/reservations/',
    ]) {
      expect(canOpenRoute(AppRole.customer, route), false);
    }
    expect(canOpenRoute(AppRole.customer, '/drugs/2'), true);
  });
  test('from безопасен и сохраняет параметры списка', () {
    expect(
      safeReturnPath('/drugs?search=abc&page=2'),
      '/drugs?search=abc&page=2',
    );
    for (final value in [
      'https://bad.example',
      '//bad.example',
      '/login',
      '/session',
      r'/\bad',
    ]) {
      expect(safeReturnPath(value), '/');
    }
  });
  test('пароль проверяет длину, цифру и спецсимвол', () {
    expect(AuthValidators.password('Strong123!'), null);
    for (final value in ['short1!', 'NoDigits!', 'NoSpecial123']) {
      expect(AuthValidators.password(value), isNotNull);
    }
  });
  test(
    'вход сохраняет токены; новый экземпляр восстанавливает; выход очищает',
    () async {
      await auth.login({});
      expect(auth.authenticated, true);
      expect(storage.value, isNotNull);
      final restored = AuthNotifier(
        repository,
        storage,
        clock: () => time,
        timers: false,
      );
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.user!.username, 'user');
      await restored.logout();
      expect(storage.value, null);
      expect(restored.authenticated, false);
    },
  );
  test(
    'изменённая локальная роль влияет только на UI-профиль (п.17)',
    () async {
      await auth.login({});
      final saved = jsonDecode(storage.value!) as Map<String, dynamic>;
      (saved['user'] as Map)['role'] = 'admin';
      storage.value = jsonEncode(saved);
      final restored = AuthNotifier(
        repository,
        storage,
        clock: () => time,
        timers: false,
      );
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.user!.role, AppRole.admin);
      expect(restored.accessToken, 'access-old');
    },
  );
  test('одновременные обновления токена выполняются одним запросом', () async {
    await auth.login({});
    repository.refreshCompleter = Completer();
    final first = auth.refreshTokens();
    final second = auth.refreshTokens();
    expect(repository.refreshes, 1);
    repository.refreshCompleter!.complete({
      ...repository.data,
      'accessToken': 'new',
      'refreshToken': 'new-refresh',
    });
    expect(await first, true);
    expect(await second, true);
    expect(auth.accessToken, 'new');
  });
  test('неудачный refresh завершает сессию и очищает хранилище', () async {
    await auth.login({});
    repository.refreshError = const UnauthorizedException();
    expect(await auth.refreshTokens(), false);
    expect(auth.authenticated, false);
    expect(storage.value, null);
    expect(repository.refreshes, 1);
  });
  test('поздний ответ refresh после выхода не возрождает сессию', () async {
    await auth.login({});
    repository.refreshCompleter = Completer();
    final pending = auth.refreshTokens();
    await auth.logout();
    repository.refreshCompleter!.complete(repository.data);
    expect(await pending, false);
    expect(auth.authenticated, false);
    expect(storage.value, null);
  });
  test('предупреждение за 30 секунд и выход через 3 минуты', () async {
    await auth.login({});
    time = time.add(const Duration(seconds: 150));
    auth.checkTimeout();
    expect(auth.warningRemaining, 30);
    expect(auth.authenticated, true);
    time = time.add(const Duration(seconds: 30));
    auth.checkTimeout();
    expect(auth.authenticated, false);
    await Future<void>.delayed(Duration.zero);
    expect(storage.value, null);
  });
  test(
    'активность отменяет предупреждение, но не продлевает общий срок',
    () async {
      await auth.login({});
      time = time.add(const Duration(seconds: 150));
      auth.touch();
      expect(auth.warningRemaining, null);
      for (var i = 0; i < 35; i++) {
        time = time.add(const Duration(seconds: 95));
        auth.touch();
      }
      time = initialTime.add(const Duration(hours: 1));
      auth.checkTimeout();
      expect(auth.authenticated, false);
      expect(auth.notice, contains('Максимальная'));
    },
  );
  test('offline при восстановлении не уничтожает сохранённые токены', () async {
    await auth.login({});
    repository.meError = const NetworkException();
    final restored = AuthNotifier(
      repository,
      storage,
      clock: () => time,
      timers: false,
    );
    addTearDown(restored.dispose);
    await restored.restore();
    expect(restored.bootstrapError, isNotNull);
    expect(storage.value, isNotNull);
    repository.meError = null;
    await restored.restore();
    expect(restored.bootstrapError, null);
  });
  test(
    'Dio: 401, refresh и один прозрачный повтор исходного запроса',
    () async {
      var token = 'old';
      var refreshes = 0;
      var calls = 0;
      final dio = buildDio(
        baseUrl: 'http://test/api',
        tokenProvider: () => token,
        refreshToken: () async {
          refreshes++;
          token = 'new';
          return true;
        },
      );
      addTearDown(() => dio.close(force: true));
      dio.httpClientAdapter = FakeApiAdapter((options, _) {
        calls++;
        return options.headers['Authorization'] == 'Bearer new'
            ? jsonResponse({'ok': true})
            : jsonResponse({'message': 'expired'}, 401);
      });
      expect((await dio.get('/drugs')).data['ok'], true);
      expect(calls, 2);
      expect(refreshes, 1);
    },
  );
  test('Dio: повторный 401 не запускает бесконечный refresh', () async {
    var refreshes = 0;
    var calls = 0;
    var logouts = 0;
    final dio = buildDio(
      baseUrl: 'http://test/api',
      refreshToken: () async {
        refreshes++;
        return true;
      },
      onSessionExpired: () async {
        logouts++;
      },
    );
    addTearDown(() => dio.close(force: true));
    dio.httpClientAdapter = FakeApiAdapter((_, _) {
      calls++;
      return jsonResponse({}, 401);
    });
    await expectLater(
      guard(() => dio.get('/drugs')),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(calls, 2);
    expect(refreshes, 1);
    expect(logouts, 1);
  });
  test('Dio: ошибка входа 401 не вызывает refresh', () async {
    var refreshes = 0;
    final dio = buildDio(
      baseUrl: 'http://test/api',
      refreshToken: () async {
        refreshes++;
        return true;
      },
    );
    addTearDown(() => dio.close(force: true));
    dio.httpClientAdapter = FakeApiAdapter((_, _) => jsonResponse({}, 401));
    await expectLater(
      guard(() => dio.post('/auth/login')),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(refreshes, 0);
  });

  test('Dio: поздний 401 прежней сессии не выходит из новой', () async {
    var currentSession = 'old-session';
    var refreshes = 0;
    var logouts = 0;
    final response = Completer<ResponseBody>();
    final started = Completer<void>();
    final dio = buildDio(
      baseUrl: 'http://test/api',
      sessionProvider: () => currentSession,
      refreshToken: () async {
        refreshes++;
        return false;
      },
      onSessionExpired: () async {
        logouts++;
      },
    );
    addTearDown(() => dio.close(force: true));
    dio.httpClientAdapter = FakeApiAdapter((options, _) {
      expect(options.extra['authSession'], 'old-session');
      started.complete();
      return response.future;
    });
    final pending = guard(() => dio.get('/drugs'));
    await started.future;
    currentSession = 'new-session';
    response.complete(jsonResponse({}, 401));
    await expectLater(pending, throwsA(isA<UnauthorizedException>()));
    expect(refreshes, 0);
    expect(logouts, 0);
  });
  testWidgets('GoRouter закрывает ручной чужой адрес экраном отказа', (
    tester,
  ) async {
    await tester.runAsync(() => auth.login({}));
    final router = buildRouter(auth: auth);
    addTearDown(router.dispose);
    router.go('/admin/users');
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: auth,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Доступ запрещён'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/forbidden');
  });
  testWidgets('форма входа показывает понятную ошибку неверного пароля', (
    tester,
  ) async {
    repository.loginError = const UnauthorizedException(
      'Неверный логин или пароль.',
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: auth,
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, 'user');
    await tester.enterText(find.byType(TextFormField).last, 'bad');
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();
    expect(find.text('Неверный логин или пароль.'), findsOneWidget);
    expect(auth.authenticated, false);
  });

  testWidgets('предупреждение о бездействии находится внутри экрана', (
    tester,
  ) async {
    await tester.runAsync(() => auth.login({}));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: auth,
        child: const MaterialApp(
          home: AppScaffold(title: 'Главный экран', body: Text('Каталог')),
        ),
      ),
    );
    time = time.add(const Duration(seconds: 150));
    auth.checkTimeout();
    await tester.pump();
    expect(find.text('Выход через 30 с из-за бездействия.'), findsOneWidget);
    await tester.tap(find.text('Продолжить работу'));
    await tester.pump();
    expect(find.textContaining('Выход через'), findsNothing);
  });
}
