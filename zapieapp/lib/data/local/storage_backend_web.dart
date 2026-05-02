import 'dart:html' as html;

void writeStorageValueSync(String key, String value) {
  html.window.localStorage[key] = value;
}

String? readStorageValueSync(String key) {
  return html.window.localStorage[key];
}

void removeStorageValueSync(String key) {
  html.window.localStorage.remove(key);
}

Future<void> writeStorageValue(String key, String value) async {
  writeStorageValueSync(key, value);
}

Future<String?> readStorageValue(String key) async {
  return readStorageValueSync(key);
}

Future<void> removeStorageValue(String key) async {
  removeStorageValueSync(key);
}
