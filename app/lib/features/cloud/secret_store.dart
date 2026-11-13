// Steiner Budget — local-first budgeting, https://steinerdevelopers.dev
// Copyright (C) 2026 Steiner Developers, L.L.C.
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

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
