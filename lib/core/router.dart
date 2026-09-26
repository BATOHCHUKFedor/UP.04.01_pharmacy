import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/drug_query.dart';
import '../models/supplier_query.dart';
import '../screens/drug_detail_screen.dart';
import '../screens/drug_list_screen.dart';
import '../screens/supplier_detail_screen.dart';
import '../screens/supplier_list_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/drugs',
  routes: [
    GoRoute(path: '/', redirect: (_, _) => '/drugs'),
    GoRoute(
      path: '/drugs',
      builder: (context, state) => DrugListScreen(
        query: DrugQuery.fromParameters(state.uri.queryParameters),
      ),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) => DrugDetailScreen(
            id: int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/suppliers',
      builder: (context, state) => SupplierListScreen(
        query: SupplierQuery.fromParameters(state.uri.queryParameters),
      ),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) => SupplierDetailScreen(
            id: int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
          ),
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link_off, size: 48),
          const SizedBox(height: 12),
          Text('Страница не найдена: ${state.uri.path}'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => context.go('/drugs'),
            child: const Text('К препаратам'),
          ),
        ],
      ),
    ),
  ),
);
