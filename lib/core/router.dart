import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'form_leave_guard.dart';
import '../models/catalog_item.dart';
import '../models/catalog_query.dart';
import '../screens/catalog_detail_screen.dart';
import '../screens/catalog_form_screen.dart';
import '../screens/catalog_list_screen.dart';

EntityKind? kindFromPath(String? path) {
  for (final kind in EntityKind.values) {
    if (kind.path == path) return kind;
  }
  return null;
}

final appRouter = GoRouter(
  initialLocation: '/drugs',
  routes: [
    GoRoute(path: '/', redirect: (_, _) => '/drugs'),
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
          onExit: (context, state) => context.read<FormLeaveGuard>().confirm(),
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
              onExit: (context, state) =>
                  context.read<FormLeaveGuard>().confirm(),
            ),
          ],
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => const _UnknownPage(),
);

class _UnknownPage extends StatelessWidget {
  const _UnknownPage();
  @override
  Widget build(BuildContext context) => Scaffold(
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
