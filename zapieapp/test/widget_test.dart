import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zapieapp_flutter_starter/app.dart';
import 'package:zapieapp_flutter_starter/data/local/session_persistence.dart';
import 'package:zapieapp_flutter_starter/features/auth/auth_callback_screen.dart';
import 'package:zapieapp_flutter_starter/router/app_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SessionPersistence.initialize();
    await SessionPersistence.clearAll();
  });

  testWidgets('ZapieApp renders the login flow on startup', (tester) async {
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _TestAssetBundle(),
        child: const ZapieApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Witaj z powrotem'), findsOneWidget);
    expect(find.text('Logowanie'), findsOneWidget);
    expect(find.text('Zaloguj sie'), findsOneWidget);
    expect(find.text('Rejestracja'), findsOneWidget);
    expect(find.text('Kontynuuj z Google'), findsOneWidget);
    expect(find.text('Kontynuuj z Apple'), findsOneWidget);
    expect(
      find.text(
        'Google otworzy konto zalogowane na urzadzeniu. Apple pozostaje logowaniem dodatkowym.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('auth callback route renders callback error feedback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: generateAppRoute,
        initialRoute:
            '/auth/callback?error=access_denied&error_description=Odmowa+zgody',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nie udalo sie zalogowac'), findsOneWidget);
    expect(find.text('Odmowa zgody'), findsOneWidget);
    expect(find.text('Wroc do logowania'), findsOneWidget);
  });

  testWidgets('auth callback success saves session and redirects to dashboard',
      (tester) async {
    final mockClient = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/google-auth/callback');

      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['code'], 'google-code');
      expect(payload['state'], 'signed-state');
      expect(payload['redirect_uri'], 'zapieapp://auth/callback');

      return http.Response(
        jsonEncode({
          'jwt': 'jwt-token',
          'session_token': 'session-token',
          'role': 'user',
          'user_id': 17,
          'email': 'daniel.gromak2137@gmail.com',
          'loyalty_points': 12,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.dashboard) {
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(
                body: Text('Dashboard test target'),
              ),
            );
          }
          return MaterialPageRoute<void>(
            builder: (_) => const SizedBox.shrink(),
          );
        },
        home: AuthCallbackScreen(
          callbackUri: Uri.parse(
            'http://127.0.0.1:3001/auth/callback?code=google-code&state=signed-state&provider=google',
          ),
          httpClient: mockClient,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard test target'), findsOneWidget);

    final session = SessionPersistence.loadAuthSessionSync();
    expect(session, isNotNull);
    expect(session!.email, 'daniel.gromak2137@gmail.com');
    expect(session.sessionToken, 'session-token');
    expect(session.jwt, 'jwt-token');
    expect(session.role, 'user');
    expect(session.authProvider, 'google');
    expect(session.loyaltyPoints, 12);
  });

  testWidgets('apple auth callback success saves session and redirects to dashboard',
      (tester) async {
    final mockClient = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/apple-auth/callback');

      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['code'], 'apple-code');
      expect(payload['state'], 'apple-signed-state');
      expect(payload['redirect_uri'], 'https://apple.example.com/auth/callback');
      expect(payload['name'], 'Daniel Gromak');

      return http.Response(
        jsonEncode({
          'jwt': 'apple-jwt-token',
          'session_token': 'apple-session-token',
          'role': 'user',
          'user_id': 23,
          'email': 'daniel.gromak2137@gmail.com',
          'loyalty_points': 7,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.dashboard) {
            return MaterialPageRoute<void>(
              builder: (_) => const Scaffold(
                body: Text('Dashboard test target'),
              ),
            );
          }
          return MaterialPageRoute<void>(
            builder: (_) => const SizedBox.shrink(),
          );
        },
        home: AuthCallbackScreen(
          callbackUri: Uri.parse(
            'http://127.0.0.1:3001/auth/callback?code=apple-code&state=apple-signed-state&provider=apple&user=%7B%22email%22%3A%22daniel.gromak2137%40gmail.com%22%2C%22name%22%3A%7B%22firstName%22%3A%22Daniel%22%2C%22lastName%22%3A%22Gromak%22%7D%7D',
          ),
          httpClient: mockClient,
          googleRedirectUri: 'zapieapp://auth/callback',
          appleRedirectUri: 'https://apple.example.com/auth/callback',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard test target'), findsOneWidget);

    final session = SessionPersistence.loadAuthSessionSync();
    expect(session, isNotNull);
    expect(session!.email, 'daniel.gromak2137@gmail.com');
    expect(session.sessionToken, 'apple-session-token');
    expect(session.jwt, 'apple-jwt-token');
    expect(session.role, 'user');
    expect(session.authProvider, 'apple');
    expect(session.loyaltyPoints, 7);
  });
}

class _TestAssetBundle extends CachingAssetBundle {
  static final ByteData _transparentImage = ByteData.view(
    Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+yRnsAAAAASUVORK5CYII=',
      ),
    ).buffer,
  );
  static final ByteData _emptyManifest = StandardMessageCodec().encodeMessage(
    <String, List<String>>{},
  )!;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return _emptyManifest;
    }
    return _transparentImage;
  }
}
