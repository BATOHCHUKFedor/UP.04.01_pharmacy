import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
          if (MediaQuery.sizeOf(context).width >= 600) ...[
            TextButton.icon(
              onPressed: () => context.go('/drugs'),
              icon: const Icon(Icons.medication_outlined),
              label: const Text('Препараты'),
            ),
            TextButton.icon(
              onPressed: () => context.go('/suppliers'),
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Поставщики'),
            ),
          ],
          ...?actions,
          const SizedBox(width: 8),
        ],
      ),
      drawer: MediaQuery.sizeOf(context).width < 600
          ? Drawer(
              child: SafeArea(
                child: ListView(
                  children: [
                    const ListTile(title: Text('Аптечный каталог')),
                    ListTile(
                      leading: const Icon(Icons.medication_outlined),
                      title: const Text('Препараты'),
                      onTap: () => context.go('/drugs'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.local_shipping_outlined),
                      title: const Text('Поставщики'),
                      onTap: () => context.go('/suppliers'),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: body,
    );
  }
}
