import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_exceptions.dart';
import 'config.dart';

Dio buildDio({
  String? baseUrl,
  String? Function()? tokenProvider,
  Future<bool> Function()? refreshToken,
  Future<void> Function()? onSessionExpired,
  String? Function()? sessionProvider,
}) {
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
        if (sessionProvider != null) {
          options.extra.putIfAbsent('authSession', () => sessionProvider());
        }
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
      onError: (error, handler) async {
        if (kDebugMode) {
          debugPrint(
            '[API] ${error.requestOptions.method} ${error.requestOptions.uri} '
            '→ ${error.response?.statusCode ?? error.type.name}',
          );
        }
        final options = error.requestOptions;
        if (error.response?.statusCode == 401 &&
            refreshToken != null &&
            !options.path.startsWith('/auth/') &&
            (sessionProvider == null ||
                options.extra['authSession'] == sessionProvider())) {
          final newerToken = tokenProvider?.call();
          final alreadyRefreshed =
              newerToken != null &&
              options.headers['Authorization'] != 'Bearer $newerToken';
          if (options.extra['authRetried'] != true &&
              (alreadyRefreshed || await refreshToken())) {
            if (options.cancelToken?.isCancelled == true) {
              handler.next(
                error.copyWith(
                  type: DioExceptionType.cancel,
                  error: const RequestCancelledException(),
                ),
              );
              return;
            }
            options.extra['authRetried'] = true;
            options.headers['Authorization'] =
                'Bearer ${tokenProvider?.call()}';
            try {
              handler.resolve(await dio.fetch<dynamic>(options));
            } on DioException catch (retryError) {
              handler.next(retryError);
            }
            return;
          }
          if (sessionProvider == null ||
              options.extra['authSession'] == sessionProvider()) {
            await onSessionExpired?.call();
          }
        }
        handler.next(error.copyWith(error: mapDioError(error)));
      },
    ),
  );
  return dio;
}
