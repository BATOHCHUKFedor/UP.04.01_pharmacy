import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/form_leave_guard.dart';
import 'core/router.dart';
import 'repositories/catalog_repository.dart';
import 'repositories/local_catalog_repository.dart';
import 'state/catalog_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  final repository = LocalCatalogRepository(SharedPreferencesAsync());
  await repository.initialize();
  runApp(
    MultiProvider(
      providers: [
        Provider<CatalogRepository>.value(value: repository),
        Provider<FormLeaveGuard>(create: (_) => FormLeaveGuard()),
        ChangeNotifierProvider(create: (_) => CatalogStore(repository)),
      ],
      child: const PharmacyApp(),
    ),
  );
}

class PharmacyApp extends StatelessWidget {
  const PharmacyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Аптечный каталог',
    debugShowCheckedModeBanner: false,
    routerConfig: appRouter,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF147D73)),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(isDense: true),
    ),
  );
}
