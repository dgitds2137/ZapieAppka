import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zapieapp_flutter_starter/app.dart';
import 'package:zapieapp_flutter_starter/data/local/session_persistence.dart';

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
        'Wpisz e-mail i przejdz do oficjalnego logowania Google lub Apple.',
      ),
      findsOneWidget,
    );
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
