import 'package:dio/dio.dart';

sealed class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}

class NetworkException extends ApiException {
  const NetworkException([
    super.message = 'Сервер недоступен. Проверьте соединение и настройки CORS.',
  ]);
}

class UnauthorizedException extends ApiException {
  const UnauthorizedException([super.message = 'Требуется вход в систему.']);
}

class ForbiddenException extends ApiException {
  const ForbiddenException([super.message = 'Недостаточно прав для действия.']);
}

class NotFoundException extends ApiException {
  const NotFoundException([super.message = 'Запись не найдена.']);
}

class ConflictException extends ApiException {
  const ConflictException(super.message);
}

class ValidationException extends ApiException {
  final Map<String, String> errors;
  const ValidationException(super.message, this.errors);
}

class ServerException extends ApiException {
  const ServerException([super.message = 'Ошибка сервера. Попробуйте позже.']);
}

class RequestCancelledException extends ApiException {
  const RequestCancelledException() : super('Устаревший запрос отменён.');
}

ApiException mapHttpError(int status, dynamic body) {
  final message = body is Map && body['message'] is String
      ? body['message'] as String
      : null;
  return switch (status) {
    401 => UnauthorizedException(message ?? 'Требуется вход в систему.'),
    403 => ForbiddenException(message ?? 'Недостаточно прав для действия.'),
    404 => NotFoundException(message ?? 'Запись не найдена.'),
    409 => ConflictException(message ?? 'Операция невозможна.'),
    422 => ValidationException(
      message ?? 'Проверьте поля формы.',
      body is Map && body['errors'] is Map
          ? (body['errors'] as Map).map(
              (key, value) => MapEntry('$key', '$value'),
            )
          : const {},
    ),
    _ => ServerException(message ?? 'Ошибка сервера (код $status).'),
  };
}

ApiException mapDioError(DioException error) {
  if (error.error case final ApiException existing) return existing;
  if (error.response case final response?) {
    return mapHttpError(response.statusCode ?? 500, response.data);
  }
  return switch (error.type) {
    DioExceptionType.cancel => const RequestCancelledException(),
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => const NetworkException(
      'Сервер не ответил вовремя.',
    ),
    DioExceptionType.connectionError => const NetworkException(),
    _ => const ServerException(),
  };
}

Future<T> guard<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on DioException catch (error) {
    throw mapDioError(error);
  }
}
