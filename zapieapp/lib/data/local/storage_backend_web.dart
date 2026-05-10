// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

Future<void> initializeStorageBackend() async {}

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
