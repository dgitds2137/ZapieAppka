import 'package:flutter/material.dart';

import 'app.dart';
import 'data/local/session_persistence.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SessionPersistence.initialize();
  runApp(const ZapieApp());
}
