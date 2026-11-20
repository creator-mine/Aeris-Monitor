import 'package:aeris/core/security/secret_store.dart';

/// In-memory [SecretStore] for tests: no platform channels involved.
class FakeSecretStore implements SecretStore {
  FakeSecretStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
