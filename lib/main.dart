import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';

import 'core/form_leave_guard.dart';
import 'core/router.dart';
import 'repositories/catalog_repository.dart';
import 'core/api_client.dart';
import 'repositories/api_catalog_repository.dart';
import 'state/catalog_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  runApp(
    MultiProvider(
      providers: [
        Provider<Dio>(
          create: (_) => buildDio(),
          dispose: (_, dio) => dio.close(force: true),
        ),
        ProxyProvider<Dio, CatalogRepository>(
          update: (_, dio, previous) => previous ?? ApiCatalogRepository(dio),
        ),
        Provider<FormLeaveGuard>(create: (_) => FormLeaveGuard()),
        ChangeNotifierProvider(
          create: (context) => CatalogStore(context.read<CatalogRepository>()),
        ),
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
