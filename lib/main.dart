import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';

import 'core/form_leave_guard.dart';
import 'core/router.dart';
import 'repositories/catalog_repository.dart';
import 'core/api_client.dart';
import 'repositories/api_catalog_repository.dart';
import 'state/catalog_store.dart';
import 'repositories/auth_repository.dart';
import 'repositories/workspace_repository.dart';
import 'state/auth_notifier.dart';
import 'widgets/session_activity.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  runApp(
    ChangeNotifierProvider(
      create: (_) {
        final auth = AuthNotifier(
          ApiAuthRepository(buildDio()),
          PreferencesSessionStorage(),
        );
        unawaited(auth.restore());
        return auth;
      },
      child: const PharmacyApp(),
    ),
  );
}

class PharmacyApp extends StatefulWidget {
  const PharmacyApp({super.key});

  @override
  State<PharmacyApp> createState() => _PharmacyAppState();
}

class _PharmacyAppState extends State<PharmacyApp> {
  late final GoRouter _router;
  @override
  void initState() {
    super.initState();
    _router = buildRouter(auth: context.read<AuthNotifier>());
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    return MultiProvider(
      key: ValueKey(auth.session?.id ?? 'signed-out'),
      providers: [
        Provider<Dio>(
          create: (_) => buildDio(
            tokenProvider: () => auth.accessToken,
            refreshToken: auth.refreshTokens,
            sessionProvider: () => auth.session?.id,
            onSessionExpired: () =>
                auth.logout('Сессия завершена. Войдите снова.'),
          ),
          dispose: (_, dio) => dio.close(force: true),
        ),
        Provider<CatalogRepository>(
          create: (context) => ApiCatalogRepository(context.read<Dio>()),
        ),
        Provider<WorkspaceRepository>(
          create: (context) => WorkspaceRepository(context.read<Dio>()),
        ),
        Provider<FormLeaveGuard>(create: (_) => FormLeaveGuard()),
        ChangeNotifierProvider(
          create: (context) => CatalogStore(context.read<CatalogRepository>()),
        ),
      ],
      child: MaterialApp.router(
        title: 'Аптечный каталог',
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
        builder: (_, child) =>
            SessionActivity(child: child ?? const SizedBox.shrink()),
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF147D73)),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(isDense: true),
        ),
      ),
    );
  }
}
