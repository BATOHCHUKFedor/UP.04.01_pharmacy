import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/catalog_item.dart';

class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          PopupMenuButton<EntityKind>(
            tooltip: 'Разделы каталога',
            icon: const Icon(Icons.menu_book_outlined),
            onSelected: (kind) => context.go('/${kind.path}'),
            itemBuilder: (_) => [
              for (final kind in EntityKind.values)
                PopupMenuItem(value: kind, child: Text(kind.title)),
            ],
          ),
          ...?actions,
          const SizedBox(width: 8),
        ],
      ),
      body: body,
    );
  }
}
