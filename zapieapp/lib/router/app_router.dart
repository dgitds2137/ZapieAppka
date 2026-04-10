import 'package:flutter/material.dart';

import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';

class AppRoutes {
  static const login = '/';
  static const dashboard = '/dashboard';
}

Map<String, WidgetBuilder> buildRoutes() {
  return {
    AppRoutes.login: (_) => const LoginScreen(),
    AppRoutes.dashboard: (_) => const DashboardScreen(),
  };
}
