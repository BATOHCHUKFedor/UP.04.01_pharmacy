import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_exceptions.dart';
import 'config.dart';

Dio buildDio({String? baseUrl, String? Function()? tokenProvider}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl ?? apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
      validateStatus: (status) => status != null && status < 500,
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = tokenProvider?.call();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        if (kDebugMode) debugPrint('[API] ${options.method} ${options.uri}');
        handler.next(options);
      },
      onResponse: (response, handler) {
        final status = response.statusCode ?? 0;
        if (kDebugMode && status < 400) {
          debugPrint(
            '[API] ${response.requestOptions.method} '
            '${response.requestOptions.uri} → $status',
          );
        }
        if (status >= 400) {
          handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              error: mapHttpError(status, response.data),
            ),
            true,
          );
        } else {
          handler.next(response);
        }
      },
      onError: (error, handler) {
        if (kDebugMode) {
          debugPrint(
            '[API] ${error.requestOptions.method} ${error.requestOptions.uri} '
            '→ ${error.response?.statusCode ?? error.type.name}',
          );
        }
        handler.next(error.copyWith(error: mapDioError(error)));
      },
    ),
  );
  return dio;
}
