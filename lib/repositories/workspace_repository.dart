import 'package:dio/dio.dart';
import '../core/api_exceptions.dart';

class WorkspaceRepository {
  final Dio _dio;
  WorkspaceRepository(this._dio);
  Future<dynamic> read(String path) =>
      guard(() async => (await _dio.get(path)).data);
  Future<void> create(String path, Map<String, dynamic> data) =>
      guard(() async {
        await _dio.post(path, data: data);
      });
  Future<void> update(String path, Map<String, dynamic> data) =>
      guard(() async {
        await _dio.put(path, data: data);
      });
}
