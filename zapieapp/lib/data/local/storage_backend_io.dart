import 'package:shared_preferences/shared_preferences.dart';

SharedPreferences? _prefs;
final Map<String, String> _cache = <String, String>{};

Future<void> initializeStorageBackend() async {
  _prefs ??= await SharedPreferences.getInstance();
  _cache
    ..clear()
    ..addEntries(
      _prefs!.getKeys().map(
        (key) => MapEntry(key, _prefs!.getString(key) ?? ''),
      ),
    );
}

void writeStorageValueSync(String key, String value) {
  _cache[key] = value;
  _prefs?.setString(key, value);
}

String? readStorageValueSync(String key) {
  return _cache[key];
}

void removeStorageValueSync(String key) {
  _cache.remove(key);
  _prefs?.remove(key);
}

Future<void> writeStorageValue(String key, String value) async {
  _cache[key] = value;
  if (_prefs == null) {
    await initializeStorageBackend();
  }
  await _prefs!.setString(key, value);
}

Future<String?> readStorageValue(String key) async {
  if (_prefs == null) {
    await initializeStorageBackend();
  }
  return _cache[key];
}

Future<void> removeStorageValue(String key) async {
  _cache.remove(key);
  if (_prefs == null) {
    await initializeStorageBackend();
  }
  await _prefs!.remove(key);
}
