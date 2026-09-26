import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';

import 'core/router.dart';
import 'repositories/drug_repository.dart';
import 'repositories/in_memory_drug_repository.dart';
import 'repositories/in_memory_supplier_repository.dart';
import 'repositories/supplier_repository.dart';
import 'state/drug_details_notifier.dart';
import 'state/drug_list_notifier.dart';
import 'state/supplier_details_notifier.dart';
import 'state/supplier_list_notifier.dart';

void main() {
  usePathUrlStrategy();
  runApp(
    MultiProvider(
      providers: [
        Provider<DrugRepository>(create: (_) => InMemoryDrugRepository()),
        Provider<SupplierRepository>(
          create: (_) => InMemorySupplierRepository(),
        ),
        ChangeNotifierProvider(
          create: (context) => DrugListNotifier(context.read<DrugRepository>()),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              SupplierListNotifier(context.read<SupplierRepository>()),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              DrugDetailsNotifier(context.read<DrugRepository>()),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              SupplierDetailsNotifier(context.read<SupplierRepository>()),
        ),
      ],
      child: const PharmacyApp(),
    ),
  );
}

class PharmacyApp extends StatelessWidget {
  const PharmacyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Аптечный каталог',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF147D73),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(isDense: true),
      ),
    );
  }
}
