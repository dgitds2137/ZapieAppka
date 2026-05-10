final Map<String, String> _memoryStorage = <String, String>{};

Future<void> initializeStorageBackend() async {}

void writeStorageValueSync(String key, String value) {
  _memoryStorage[key] = value;
}

String? readStorageValueSync(String key) {
  return _memoryStorage[key];
}

void removeStorageValueSync(String key) {
  _memoryStorage.remove(key);
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
