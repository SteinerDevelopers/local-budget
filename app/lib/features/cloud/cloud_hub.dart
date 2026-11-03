// E7b §3.1 — the seam the UI talks to: destination records + their secret
// + a CloudTarget per destination. Tests hand this fakes on all three
// sides; production composes the real ones in main.dart (behind the
// proTrio gate, so the free flavor never touches the keystore).
import 'package:data/data.dart';

import 'cloud_config.dart';
import 'secret_store.dart';

class CloudHub {
  CloudHub({
    required this.config,
    required this.secrets,
    CloudTarget Function(CloudDestination d, String? password)? targets,
    this.profileName = 'default',
  }) : _targets =
           targets ??
           ((d, password) =>
               WebdavClient(baseUrl: d.url, user: d.user, password: password));

  final CloudConfigStore config;
  final CloudSecretStore secrets;
  final String profileName;
  final CloudTarget Function(CloudDestination d, String? password) _targets;

  List<CloudDestination> destinations() => config.load();

  /// Only ever hand out a target that carries the stored secret (§3.1:
  /// Basic auth against the user's box needs it; a silent null would
  /// surface as an unexplained 401).
  Future<CloudTarget> targetWith(CloudDestination d) async =>
      _targets(d, await secrets.get(d.id));

  /// §3.2 object name for a new upload on [d].
  String nextObjectName() =>
      backupObjectName(profileName: profileName, now: DateTime.now());

  Future<void> upsert(CloudDestination d, {String? password}) async {
    // load() hands out an unmodifiable view — edit a copy.
    final all = [...destinations()];
    final i = all.indexWhere((e) => e.id == d.id);
    if (i >= 0) {
      all[i] = d;
    } else {
      all.add(d);
    }
    await config.save(all);
    if (password != null && password.isNotEmpty) {
      await secrets.put(d.id, password);
    }
  }

  /// §3.1: deleting scrubs the secret; remote files stay the user's own.
  Future<void> remove(CloudDestination d) async {
    await config.save([
      for (final e in destinations())
        if (e.id != d.id) e,
    ]);
    await secrets.remove(d.id);
  }

  Future<void> setPassword(CloudDestination d, String password) =>
      secrets.put(d.id, password);
}
