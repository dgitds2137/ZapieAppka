import 'package:flutter/material.dart';

import '../features/auth/auth_callback_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';

class AppRoutes {
  static const login = '/';
  static const authCallback = '/auth/callback';
  static const dashboard = '/dashboard';
}

Route<dynamic> generateAppRoute(RouteSettings settings) {
  final routeName = settings.name ?? AppRoutes.login;
  final uri = Uri.tryParse(routeName) ?? Uri(path: routeName);

  if (_isAuthCallbackUri(uri)) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => AuthCallbackScreen(callbackUri: uri),
    );
  }

  if (uri.path == AppRoutes.dashboard) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => const DashboardScreen(),
    );
  }

  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => const LoginScreen(),
  );
}

bool _isAuthCallbackUri(Uri uri) {
  return uri.path == AppRoutes.authCallback ||
      uri.path == '/callback' ||
      (uri.scheme == 'zapieapp' &&
          uri.host == 'auth' &&
          uri.path == '/callback');
}

Map<String, WidgetBuilder> buildRoutes() {
  return {
    AppRoutes.login: (_) => const LoginScreen(),
    AppRoutes.authCallback: (_) => AuthCallbackScreen(
          callbackUri: Uri(path: AppRoutes.authCallback),
        ),
    AppRoutes.dashboard: (_) => const DashboardScreen(),
  };
}
