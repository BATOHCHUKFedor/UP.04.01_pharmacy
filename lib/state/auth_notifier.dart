import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/api_exceptions.dart';
import '../models/auth_user.dart';
import '../repositories/auth_repository.dart';

class AuthNotifier extends ChangeNotifier {
  final AuthRepository repository;
  final SessionStorage storage;
  final DateTime Function() now;
  AuthNotifier(
    this.repository,
    this.storage, {
    DateTime Function()? clock,
    bool timers = true,
  }) : now = clock ?? DateTime.now {
    if (timers) {
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => checkTimeout(),
      );
    }
  }
  AuthUser? user;
  AuthSession? session;
  String? accessToken;
  String? _refreshToken;
  bool initializing = true;
  bool busy = false;
  String? bootstrapError;
  String? notice;
  DateTime? _lastActivity;
  DateTime? _lastHeartbeat;
  Timer? _timer;
  Future<bool>? _refreshing;
  Future<void> _storageQueue = Future.value();
  bool _disposed = false;
  int _generation = 0;
  bool get authenticated => user != null && accessToken != null;
  bool allows(Permission permission) =>
      user != null && roleAllows(user!.role, permission);
  int? get warningRemaining {
    if (!authenticated || session == null || _lastActivity == null) return null;
    final left =
        session!.idleSeconds - now().difference(_lastActivity!).inSeconds;
    return left > 0 && left <= session!.warningSeconds ? left : null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _persist() {
    final value = jsonEncode({
      'user': user?.toJson(),
      'session': session?.toJson(),
      'accessToken': accessToken,
      'refreshToken': _refreshToken,
      'lastActivity': _lastActivity?.millisecondsSinceEpoch,
    });
    final generation = _generation;
    return _storageQueue = _storageQueue.catchError((Object _) {}).then((
      _,
    ) async {
      if (generation == _generation && authenticated) {
        await storage.write(value);
      }
    });
  }

  Future<void> restore() async {
    initializing = true;
    bootstrapError = null;
    _notify();
    final generation = _generation;
    try {
      final raw = await storage.read();
      if (generation != _generation || _disposed) return;
      if (raw == null) return;
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      user = AuthUser.fromJson(Map<String, dynamic>.from(saved['user'] as Map));
      session = AuthSession.fromJson(
        Map<String, dynamic>.from(saved['session'] as Map),
      );
      accessToken = saved['accessToken'] as String?;
      _refreshToken = saved['refreshToken'] as String?;
      _lastActivity = DateTime.fromMillisecondsSinceEpoch(
        (saved['lastActivity'] as num?)?.toInt() ??
            session!.lastActivity.millisecondsSinceEpoch,
      );
      if (!authenticated || _refreshToken == null || _expired()) {
        await logout('Сессия завершена. Войдите снова.');
        return;
      }
      final cachedUser = user!;
      var refreshed = false;
      Map<String, dynamic> result;
      try {
        result = await repository.me(accessToken!);
      } on UnauthorizedException {
        if (!await refreshTokens()) return;
        refreshed = true;
        result = await repository.me(accessToken!);
      }
      if (generation != _generation || _disposed) return;
      final verified = AuthUser.fromJson(
        Map<String, dynamic>.from(result['user'] as Map),
      );
      // Профиль — только подсказка интерфейсу (демонстрация ПР5, п.17).
      // Сервер проверяет сессию и права самостоятельно; localStorage не доверен.
      user = !refreshed && cachedUser.id == verified.id ? cachedUser : verified;
      session = AuthSession.fromJson(
        Map<String, dynamic>.from(result['session'] as Map),
      );
      await _persist();
    } on NetworkException catch (error) {
      bootstrapError = error.message;
    } on ServerException catch (error) {
      bootstrapError = error.message;
    } catch (_) {
      await logout('Не удалось восстановить сессию. Войдите снова.');
    } finally {
      initializing = false;
      _notify();
    }
  }

  void _accept(Map<String, dynamic> data, {bool login = false}) {
    user = AuthUser.fromJson(Map<String, dynamic>.from(data['user'] as Map));
    session = AuthSession.fromJson(
      Map<String, dynamic>.from(data['session'] as Map),
    );
    accessToken = data['accessToken'] as String;
    _refreshToken = data['refreshToken'] as String;
    if (login) _lastActivity = session!.lastActivity;
  }

  Future<void> login(
    Map<String, dynamic> fields, {
    bool register = false,
  }) async {
    if (busy) return;
    busy = true;
    notice = null;
    _notify();
    final generation = ++_generation;
    _refreshing = null;
    try {
      final result = await repository.login(fields, register: register);
      if (generation != _generation || _disposed) return;
      _accept(result, login: true);
      bootstrapError = null;
      await _persist();
    } finally {
      busy = false;
      initializing = false;
      _notify();
    }
  }

  Future<bool> refreshTokens() {
    if (_refreshing != null) return _refreshing!;
    late final Future<bool> pending;
    pending = _refresh().whenComplete(() {
      if (identical(_refreshing, pending)) _refreshing = null;
    });
    _refreshing = pending;
    return pending;
  }

  Future<bool> _refresh() async {
    if (_refreshToken == null || _expired()) {
      await logout('Сессия завершена. Войдите снова.');
      return false;
    }
    final generation = _generation;
    try {
      final result = await repository.refresh(_refreshToken!);
      if (generation != _generation || _disposed) return false;
      _accept(result);
      await _persist();
      _notify();
      return true;
    } catch (_) {
      if (generation == _generation) {
        await logout('Не удалось обновить токен. Войдите снова.');
      }
      return false;
    }
  }

  Future<void> logout([String? message]) async {
    final token = _refreshToken;
    ++_generation;
    _refreshing = null;
    user = null;
    session = null;
    accessToken = null;
    _refreshToken = null;
    _lastActivity = null;
    _lastHeartbeat = null;
    bootstrapError = null;
    notice = message;
    initializing = false;
    _notify();
    _storageQueue = _storageQueue
        .catchError((Object _) {})
        .then((_) => storage.clear());
    await _storageQueue;
    if (token != null) {
      try {
        await repository.logout(token);
      } catch (_) {
        /* Локальный выход работает и без сети. */
      }
    }
  }

  bool _expired() =>
      session == null ||
      _lastActivity == null ||
      !now().isBefore(session!.expiresAt) ||
      now().difference(_lastActivity!).inSeconds >= session!.idleSeconds;
  void checkTimeout() {
    if (!authenticated || initializing || bootstrapError != null) return;
    if (_expired()) {
      unawaited(
        logout(
          now().isBefore(session!.expiresAt)
              ? 'Вы вышли из системы после периода бездействия.'
              : 'Максимальная длительность сессии истекла.',
        ),
      );
    } else if (warningRemaining != null) {
      _notify();
    }
  }

  void touch() {
    if (!authenticated || initializing || bootstrapError != null) return;
    if (_expired()) {
      checkTimeout();
      return;
    }
    final time = now();
    if (_lastActivity != null &&
        time.difference(_lastActivity!).inMilliseconds < 1000) {
      return;
    }
    final warned = warningRemaining != null;
    _lastActivity = time;
    unawaited(_persist().catchError((Object _) {}));
    if (warned) _notify();
    if (_lastHeartbeat == null ||
        time.difference(_lastHeartbeat!).inSeconds >= 10) {
      _lastHeartbeat = time;
      unawaited(_heartbeat());
    }
  }

  Future<void> _heartbeat() async {
    final generation = _generation;
    try {
      await repository.activity(accessToken!);
    } on UnauthorizedException {
      if (generation != _generation) return;
      if (await refreshTokens() && generation == _generation) {
        try {
          await repository.activity(accessToken!);
        } on UnauthorizedException {
          await logout('Сессия завершена. Войдите снова.');
        } catch (_) {}
      }
    } catch (_) {
      /* Сетевой сбой не считается активностью сервера. */
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    super.dispose();
  }
}
