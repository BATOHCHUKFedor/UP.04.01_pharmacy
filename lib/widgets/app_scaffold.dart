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
    final width = MediaQuery.sizeOf(context).width;
    final signedIn = auth?.authenticated == true;
    final role = auth?.user?.role;
    final entries = <(String, String)>[
      ('/', 'Главная'),
      for (final kind in EntityKind.values)
        if (role != AppRole.customer || kind == EntityKind.drugs)
          ('/${kind.path}', kind.title),
      ...navigationFor(role),
    ];
    final path =
        GoRouter.maybeOf(context)?.routeInformationProvider.value.uri.path ??
        '/';
    final selected = entries.indexWhere(
      (entry) =>
          path == entry.$1 ||
          (entry.$1 != '/' && path.startsWith('${entry.$1}/')),
    );
    final content = FocusTraversalGroup(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: body,
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        leading: leading,
        title: Tooltip(
          message: title,
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          if (auth?.user != null && width >= 1280)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 240,
                child: Text(
                  '${auth!.user!.name} · ${auth.user!.role.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
              onPressed: () =>
                  auth!.logout('Вы вышли из системы. Сессия завершена.'),
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
          Expanded(
            child: Row(
              children: [
                if (signedIn && width >= 600)
                  FocusTraversalGroup(
                    child: SizedBox(
                      width: width >= 1280 ? 224 : 76,
                      child: Material(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: [
                            for (var i = 0; i < entries.length; i++)
                              Tooltip(
                                message: entries[i].$2,
                                child: width >= 1280
                                    ? ListTile(
                                        selected: selected == i,
                                        leading: Icon(_iconFor(entries[i].$1)),
                                        title: Text(
                                          entries[i].$2,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onTap: () => context.go(entries[i].$1),
                                      )
                                    : Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                          horizontal: 12,
                                        ),
                                        child: IconButton(
                                          tooltip: entries[i].$2,
                                          isSelected: selected == i,
                                          onPressed: () =>
                                              context.go(entries[i].$1),
                                          icon: Icon(_iconFor(entries[i].$1)),
                                        ),
                                      ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(child: content),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: signedIn && width < 600
          ? NavigationBar(
              selectedIndex: selected == 0
                  ? 0
                  : path.startsWith('/drugs')
                  ? 1
                  : navigationFor(role).any((entry) => entry.$1 == path)
                  ? 2
                  : 3,
              onDestinationSelected: (index) {
                if (index == 3) {
                  showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (sheetContext) => SafeArea(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final entry in entries)
                              ListTile(
                                leading: Icon(_iconFor(entry.$1)),
                                title: Text(entry.$2),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  context.go(entry.$1);
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                } else {
                  context.go(
                    index == 0
                        ? '/'
                        : index == 1
                        ? '/drugs'
                        : navigationFor(role).first.$1,
                  );
                }
              },
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  label: 'Главная',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.medication_outlined),
                  label: 'Каталог',
                ),
                NavigationDestination(
                  icon: Icon(_iconFor(navigationFor(role).first.$1)),
                  label: 'Мой раздел',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.menu),
                  label: 'Ещё',
                ),
              ],
            )
          : null,
    );
  }
}

IconData _iconFor(String path) => switch (path) {
  '/' => Icons.home_outlined,
  '/drugs' => Icons.medication_outlined,
  '/suppliers' => Icons.local_shipping_outlined,
  '/manufacturers' => Icons.factory_outlined,
  '/categories' => Icons.category_outlined,
  '/licenses' => Icons.badge_outlined,
  '/admin/statistics' => Icons.bar_chart,
  '/admin/users' || '/work/customers' => Icons.people_outline,
  _ => Icons.event_available_outlined,
};
