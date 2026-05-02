import 'dart:ui';

import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'router/app_router.dart';

class ZapieApp extends StatelessWidget {
  const ZapieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zapie Appka',
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: AppConfig.showPerformanceOverlay,
      theme: buildAppTheme(),
      scrollBehavior: const _AppScrollBehavior(),
      initialRoute: AppRoutes.login,
      routes: buildRoutes(),
    );
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
