import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_exceptions.dart';

abstract interface class AuthRepository {
  Future<Map<String, dynamic>> login(
    Map<String, dynamic> fields, {
    bool register = false,
  });
  Future<Map<String, dynamic>> me(String token);
  Future<Map<String, dynamic>> refresh(String token);
  Future<void> logout(String token);
  Future<void> activity(String token);
}

class ApiAuthRepository implements AuthRepository {
  final Dio _dio;
  ApiAuthRepository(this._dio);
  @override
  Future<Map<String, dynamic>> login(
    Map<String, dynamic> fields, {
    bool register = false,
  }) => guard(
    () async => Map<String, dynamic>.from(
      (await _dio.post(
            '/auth/${register ? 'register' : 'login'}',
            data: fields,
          )).data
          as Map,
    ),
  );
  @override
  Future<Map<String, dynamic>> me(String token) => guard(
    () async => Map<String, dynamic>.from(
      (await _dio.get(
            '/auth/me',
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          )).data
          as Map,
    ),
  );
  @override
  Future<Map<String, dynamic>> refresh(String token) => guard(
    () async => Map<String, dynamic>.from(
      (await _dio.post('/auth/refresh', data: {'refreshToken': token})).data
          as Map,
    ),
  );
  @override
  Future<void> logout(String token) => guard(() async {
    await _dio.post('/auth/logout', data: {'refreshToken': token});
  });
  @override
  Future<void> activity(String token) => guard(() async {
    await _dio.post(
      '/auth/activity',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  });
}

abstract interface class SessionStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class PreferencesSessionStorage implements SessionStorage {
  static const key = 'pharmacy.auth.v1';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  @override
  Future<String?> read() => _preferences.getString(key);
  @override
  Future<void> write(String value) => _preferences.setString(key, value);
  @override
  Future<void> clear() => _preferences.remove(key);
}
