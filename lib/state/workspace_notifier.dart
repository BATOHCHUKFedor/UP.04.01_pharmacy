import 'package:flutter/foundation.dart';
import '../models/auth_user.dart';
import '../models/reservation.dart';
import '../repositories/workspace_repository.dart';
import 'load_status.dart';

class WorkspaceNotifier extends ChangeNotifier {
  final WorkspaceRepository repository;
  final String path;
  WorkspaceNotifier(this.repository, this.path);
  LoadStatus status = LoadStatus.idle;
  String? error;
  bool busy = false;
  List<AuthUser> users = [];
  List<Reservation> reservations = [];
  Map<String, dynamic> statistics = {};
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    status = LoadStatus.loading;
    error = null;
    _notify();
    try {
      final data = await repository.read(path);
      if (_disposed) return;
      if (path.contains('reservations')) {
        reservations = (data as List)
            .map(
              (value) =>
                  Reservation.fromJson(Map<String, dynamic>.from(value as Map)),
            )
            .toList();
        if (path == '/reservations') {
          final customers = await repository.read('/customers');
          if (_disposed) return;
          users = (customers as List)
              .map(
                (value) =>
                    AuthUser.fromJson(Map<String, dynamic>.from(value as Map)),
              )
              .where((u) => u.active)
              .toList();
        }
      } else if (path == '/admin/statistics') {
        statistics = Map<String, dynamic>.from(data as Map);
      } else {
        users = (data as List)
            .map(
              (value) =>
                  AuthUser.fromJson(Map<String, dynamic>.from(value as Map)),
            )
            .toList();
      }
      status = LoadStatus.success;
    } catch (failure) {
      error = '$failure';
      status = LoadStatus.error;
    }
    _notify();
  }

  Future<void> mutate(
    String route,
    Map<String, dynamic> data, {
    bool update = false,
  }) async {
    if (busy) return;
    busy = true;
    _notify();
    try {
      if (update) {
        await repository.update(route, data);
      } else {
        await repository.create(route, data);
      }
      if (!_disposed) await load();
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
