import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/catalog_item.dart';
import '../models/auth_user.dart';
import '../state/auth_notifier.dart';

List<(String, String)> navigationFor(AppRole? role) => switch (role) {
  AppRole.customer => [('/my-reservations', 'Мои бронирования')],
  AppRole.pharmacist => [
    ('/work/reservations', 'Бронирования'),
    ('/work/customers', 'Пользователи аптеки'),
  ],
  AppRole.admin => [
    ('/admin/users', 'Пользователи и роли'),
    ('/admin/statistics', 'Статистика'),
  ],
  null => [],
};
bool canAct(BuildContext context, Permission permission) =>
    context.watch<AuthNotifier?>()?.allows(permission) ?? false;

class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? leading;
  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier?>();
    return Scaffold(
      appBar: AppBar(
        leading: leading,
        title: Text(title),
        actions: [
          if (auth?.user != null && MediaQuery.sizeOf(context).width >= 700)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('${auth!.user!.name} · ${auth.user!.role.label}'),
            ),
          PopupMenuButton<String>(
            tooltip: 'Разделы',
            icon: const Icon(Icons.menu_book_outlined),
            onSelected: context.go,
            itemBuilder: (_) => [
              const PopupMenuItem(value: '/', child: Text('Главный экран')),
              for (final kind in EntityKind.values)
                if (auth?.user?.role != AppRole.customer ||
                    kind == EntityKind.drugs)
                  PopupMenuItem(
                    value: '/${kind.path}',
                    child: Text(kind.title),
                  ),
              for (final entry in navigationFor(auth?.user?.role))
                PopupMenuItem(value: entry.$1, child: Text(entry.$2)),
              if (auth?.user != null)
                PopupMenuItem(
                  enabled: false,
                  child: Text('${auth!.user!.name} · ${auth.user!.role.label}'),
                ),
            ],
          ),
          ...?actions,
          if (auth?.authenticated == true)
            IconButton(
              tooltip: 'Выйти',
              onPressed: () => auth!.logout(
                "Вы вышли из системы. Сессия завершена."
              ),
              icon: const Icon(Icons.logout),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (auth?.warningRemaining case final remaining?)
            Semantics(
              liveRegion: true,
              child: MaterialBanner(
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                content: Text('Выход через $remaining с из-за бездействия.'),
                actions: [
                  TextButton(
                    onPressed: auth!.touch,
                    child: const Text('Продолжить работу'),
                  ),
                ],
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
