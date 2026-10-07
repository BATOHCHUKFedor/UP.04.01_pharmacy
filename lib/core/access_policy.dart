import '../models/auth_user.dart';

String safeReturnPath(String? path) {
  final uri = Uri.tryParse(path ?? '');
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !uri.path.startsWith('/') ||
      uri.path.startsWith('//') ||
      uri.path.contains('\\') ||
      const [
        '/login',
        '/register',
        '/session',
        '/forbidden',
      ].contains(uri.path)) {
    return '/';
  }
  return uri.toString();
}

Permission? routePermission(String path) {
  path =
      '/${Uri.parse(path).normalizePath().pathSegments.where((part) => part.isNotEmpty).join('/')}';
  if (path == '/my-reservations') return Permission.ownReservations;
  if (path == '/work/reservations') return Permission.reservations;
  if (path == '/work/customers') return Permission.customers;
  if (path == '/admin/users') return Permission.users;
  if (path == '/admin/statistics') return Permission.statistics;
  if (path.startsWith('/admin/')) return Permission.users;
  if (path.startsWith('/work/')) return Permission.reservations;
  final parts = Uri.parse(path).pathSegments;
  if (parts.isNotEmpty &&
      const [
        'drugs',
        'suppliers',
        'manufacturers',
        'categories',
        'licenses',
      ].contains(parts.first)) {
    if (parts.last == 'new' || parts.last == 'edit') return Permission.write;
    return Permission.read;
  }
  return null;
}

bool canOpenRoute(AppRole role, String path) {
  final parts = Uri.parse(path).pathSegments;
  if (role == AppRole.customer &&
      parts.isNotEmpty &&
      const [
        'suppliers',
        'manufacturers',
        'categories',
        'licenses',
      ].contains(parts.first)) {
    return false;
  }
  final permission = routePermission(path);
  return permission == null || roleAllows(role, permission);
}
