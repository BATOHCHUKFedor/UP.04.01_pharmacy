import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'form_leave_guard.dart';
import '../models/catalog_item.dart';
import '../models/catalog_query.dart';
import '../screens/catalog_detail_screen.dart';
import '../screens/catalog_form_screen.dart';
import '../screens/catalog_list_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/workspace_screen.dart';
import '../state/auth_notifier.dart';
import '../widgets/app_scaffold.dart';
import 'access_policy.dart';

EntityKind? kindFromPath(String? path) {
  for (final kind in EntityKind.values) {
    if (kind.path == path) return kind;
  }
  return null;
}

GoRouter buildRouter({required AuthNotifier auth}) => GoRouter(
  initialLocation: '/',
  refreshListenable: auth,
  redirect: (context, state) {
    final path = state.uri.path;
    final public = path == '/login' || path == '/register';
    final from = safeReturnPath(state.uri.queryParameters['from']);
    if (auth.initializing || auth.bootstrapError != null) {
      return path == '/session'
          ? null
          : Uri(
              path: '/session',
              queryParameters: {
                'from': public ? from : safeReturnPath(state.uri.toString()),
              },
            ).toString();
    }
    if (!auth.authenticated) {
      return public
          ? null
          : Uri(
              path: '/login',
              queryParameters: {
                'from': path == '/session'
                    ? from
                    : safeReturnPath(state.uri.toString()),
              },
            ).toString();
    }
    if (public || path == '/session') return from;
    if (path != '/forbidden' && !canOpenRoute(auth.user!.role, path)) {
      return '/forbidden';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (_, _) => const _HomePage()),
    GoRoute(
      path: '/login',
      builder: (_, state) => AuthScreen(
        key: const ValueKey('login'),
        from: state.uri.queryParameters['from'],
      ),
    ),
    GoRoute(
      path: '/register',
      builder: (_, state) => AuthScreen(
        key: const ValueKey('register'),
        register: true,
        from: state.uri.queryParameters['from'],
      ),
    ),
    GoRoute(path: '/session', builder: (_, _) => const SessionScreen()),
    GoRoute(path: '/forbidden', builder: (_, _) => const _ForbiddenPage()),
    GoRoute(
      path: '/my-reservations',
      builder: (_, _) => const WorkspaceScreen(path: '/reservations/mine'),
    ),
    GoRoute(
      path: '/work/reservations',
      builder: (_, state) => WorkspaceScreen(
        path: '/reservations',
        drugId: int.tryParse(state.uri.queryParameters['drugId'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/work/customers',
      builder: (_, _) => const WorkspaceScreen(path: '/customers'),
    ),
    GoRoute(
      path: '/admin/users',
      builder: (_, _) => const WorkspaceScreen(path: '/admin/users'),
    ),
    GoRoute(
      path: '/admin/statistics',
      builder: (_, _) => const WorkspaceScreen(path: '/admin/statistics'),
    ),
    GoRoute(
      path: '/:kind',
      builder: (context, state) {
        final kind = kindFromPath(state.pathParameters['kind']);
        if (kind == null) return const _UnknownPage();
        return CatalogListScreen(
          kind: kind,
          query: CatalogQuery.fromParameters(state.uri.queryParameters),
        );
      },
      routes: [
        GoRoute(
          path: 'new',
          builder: (context, state) {
            final kind = kindFromPath(state.pathParameters['kind']);
            return kind == null
                ? const _UnknownPage()
                : CatalogFormScreen(kind: kind);
          },
          onExit: (context, state) => !auth.authenticated
              ? true
              : context.read<FormLeaveGuard>().confirm(),
        ),
        GoRoute(
          path: ':id',
          builder: (context, state) {
            final kind = kindFromPath(state.pathParameters['kind']);
            final id = int.tryParse(state.pathParameters['id'] ?? '');
            return kind == null || id == null
                ? const _UnknownPage()
                : CatalogDetailScreen(kind: kind, id: id);
          },
          routes: [
            GoRoute(
              path: 'edit',
              builder: (context, state) {
                final kind = kindFromPath(state.pathParameters['kind']);
                final id = int.tryParse(state.pathParameters['id'] ?? '');
                return kind == null || id == null
                    ? const _UnknownPage()
                    : CatalogFormScreen(kind: kind, id: id);
              },
              onExit: (context, state) => !auth.authenticated
                  ? true
                  : context.read<FormLeaveGuard>().confirm(),
            ),
          ],
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => const _UnknownPage(),
);

class _HomePage extends StatelessWidget {
  const _HomePage();
  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthNotifier>().user;
    return AppScaffold(
      title: 'Аптечный каталог',
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Здравствуйте, ${user?.name ?? ''}!',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(user?.role.label ?? ''),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/drugs'),
              child: const Text('Открыть каталог'),
            ),
            for (final entry in navigationFor(user?.role))
              TextButton(
                onPressed: () => context.go(entry.$1),
                child: Text(entry.$2),
              ),
          ],
        ),
      ),
    );
  }
}

class _ForbiddenPage extends StatelessWidget {
  const _ForbiddenPage();
  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Доступ запрещён',
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Ваша роль не позволяет открыть этот раздел.'),
          FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('На главный экран'),
          ),
        ],
      ),
    ),
  );
}

class _UnknownPage extends StatelessWidget {
  const _UnknownPage();
  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Страница не найдена',
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Страница не найдена'),
          FilledButton(
            onPressed: () => context.go('/drugs'),
            child: const Text('К препаратам'),
          ),
        ],
      ),
    ),
  );
}
