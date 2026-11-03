// E7b §3.1: destination secrets live in flutter_secure_storage — the only
// file in lib/ allowed to import it, which is also what keeps the plugin
// off every other code path (widget tests inject an in-memory fake).
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class CloudSecretStore {
  Future<void> put(String id, String secret);
  Future<String?> get(String id);
  Future<void> remove(String id);
}

class SecureCloudSecretStore implements CloudSecretStore {
  const SecureCloudSecretStore([this._store = const FlutterSecureStorage()]);

  final FlutterSecureStorage _store;

  static String _key(String id) => 'cloud-dest-$id';

  @override
  Future<void> put(String id, String secret) =>
      _store.write(key: _key(id), value: secret);

  @override
  Future<String?> get(String id) => _store.read(key: _key(id));

  @override
  Future<void> remove(String id) => _store.delete(key: _key(id));
}

class MemoryCloudSecretStore implements CloudSecretStore {
  final Map<String, String> _secrets = {};

  @override
  Future<void> put(String id, String secret) async => _secrets[id] = secret;

  @override
  Future<String?> get(String id) async => _secrets[id];

  @override
  Future<void> remove(String id) async => _secrets.remove(id);
}
