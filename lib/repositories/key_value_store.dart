abstract interface class KeyValueStore {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}
