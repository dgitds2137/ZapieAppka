import 'dart:ui';

import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'data/local/session_persistence.dart';
import 'router/app_router.dart';

class ZapieApp extends StatelessWidget {
  const ZapieApp({super.key});

  @override
  Widget build(BuildContext context) {
    final initialRoute = _resolveInitialRoute();
    return MaterialApp(
      title: 'Zapie Appka',
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: AppConfig.showPerformanceOverlay,
      theme: buildAppTheme(),
      scrollBehavior: const _AppScrollBehavior(),
      initialRoute: initialRoute,
      onGenerateRoute: generateAppRoute,
    );
  }

  String _resolveInitialRoute() {
    final browserBase = Uri.base;
    if (_isAuthCallback(browserBase)) {
      final resolved = browserBase.hasQuery
          ? '${browserBase.path}?${browserBase.query}'
          : browserBase.path;
      return resolved.isEmpty ? AppRoutes.authCallback : resolved;
    }

    final browserRoute = PlatformDispatcher.instance.defaultRouteName;
    final fallbackRoute = browserRoute.isEmpty ? AppRoutes.login : browserRoute;
    final browserUri = Uri.tryParse(fallbackRoute);
    if (browserUri != null && _isAuthCallback(browserUri)) {
      return fallbackRoute;
    }
    return SessionPersistence.hasValidAuthSessionSync()
        ? AppRoutes.dashboard
        : AppRoutes.login;
  }

  bool _isAuthCallback(Uri uri) {
    return uri.path == AppRoutes.authCallback ||
        uri.path == '/callback' ||
        (uri.scheme == 'zapieapp' &&
            uri.host == 'auth' &&
            uri.path == '/callback');
  }
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };
}
