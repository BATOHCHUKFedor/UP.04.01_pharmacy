enum AppRole {
  customer('Пользователь'),
  pharmacist('Фармацевт'),
  admin('Администратор');

  const AppRole(this.label);
  final String label;
  static AppRole parse(Object? value) => AppRole.values.firstWhere(
    (role) => role.name == value,
    orElse: () => AppRole.customer,
  );
}

enum Permission {
  read,
  write,
  delete,
  hardDelete,
  restore,
  dispense,
  customers,
  reservations,
  ownReservations,
  extend,
  users,
  statistics,
}

bool roleAllows(AppRole role, Permission permission) => switch (role) {
  AppRole.customer => const {
    Permission.read,
    Permission.ownReservations,
    Permission.extend,
  }.contains(permission),
  AppRole.pharmacist => const {
    Permission.read,
    Permission.write,
    Permission.delete,
    Permission.dispense,
    Permission.customers,
    Permission.reservations,
  }.contains(permission),
  AppRole.admin => const {
    Permission.read,
    Permission.write,
    Permission.delete,
    Permission.hardDelete,
    Permission.restore,
    Permission.users,
    Permission.statistics,
  }.contains(permission),
};

class AuthUser {
  final int id;
  final String username;
  final String name;
  final AppRole role;
  final bool active;
  const AuthUser({
    required this.id,
    required this.username,
    required this.name,
    required this.role,
    this.active = true,
  });
  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: (json['id'] as num?)?.toInt() ?? 0,
    username: json['username'] as String? ?? '',
    name: json['name'] as String? ?? '',
    role: AppRole.parse(json['role']),
    active: json['active'] as bool? ?? true,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'name': name,
    'role': role.name,
    'active': active,
  };
}

class AuthSession {
  final String id;
  final DateTime startedAt;
  final DateTime expiresAt;
  final DateTime lastActivity;
  final int idleSeconds;
  final int warningSeconds;
  const AuthSession({
    required this.id,
    required this.startedAt,
    required this.expiresAt,
    required this.lastActivity,
    required this.idleSeconds,
    required this.warningSeconds,
  });
  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    id: json['id'] as String? ?? '',
    startedAt: DateTime.fromMillisecondsSinceEpoch(
      (json['startedAt'] as num?)?.toInt() ?? 0,
    ),
    expiresAt: DateTime.fromMillisecondsSinceEpoch(
      (json['expiresAt'] as num?)?.toInt() ?? 0,
    ),
    lastActivity: DateTime.fromMillisecondsSinceEpoch(
      (json['lastActivity'] as num?)?.toInt() ?? 0,
    ),
    idleSeconds: (json['idleSeconds'] as num?)?.toInt() ?? 180,
    warningSeconds: (json['warningSeconds'] as num?)?.toInt() ?? 30,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
    'lastActivity': lastActivity.millisecondsSinceEpoch,
    'idleSeconds': idleSeconds,
    'warningSeconds': warningSeconds,
  };
}
