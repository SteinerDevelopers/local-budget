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

// E7b §3.1 — the seam the UI talks to: destination records + their secret
// + a CloudTarget per destination. Tests hand this fakes on all three
// sides; production composes the real ones in main.dart (behind the
// proTrio gate, so the free flavor never touches the keystore).
import 'dart:typed_data';

import 'package:data/data.dart';

import 'cloud_config.dart';
import 'secret_store.dart';

/// Uploads [bytes] then prunes per §3.2 — the CloudTarget-shaped twin of
/// WebdavClient.putAndPrune, so the Drive follow-up reuses this flow.
Future<List<CloudObject>> putAndPruneVia(
  CloudTarget target, {
  required String folder,
  required String name,
  required Uint8List bytes,
}) async {
  await target.ensureCollection(folder);
  await target.put('$folder/$name', bytes);
  final listing = await target.list(folder);
  final plan = prunePlan(listing);
  for (final doomed in plan.delete) {
    await target.delete(doomed.path);
  }
  return plan.keep;
}

/// §3.3 scheduling seam: the UI calls [sync] after any destination or
/// toggle change; auto_backup.dart owns the Workmanager implementation,
/// tests record calls. Lives here so the hub can carry it to every screen
/// without importing the plugin's file.
abstract class CloudAutoScheduler {
  /// Register the daily task if any destination wants it, else cancel.
  Future<void> sync({
    required List<CloudDestination> destinations,
    required String? docsDir,
  });
}

class CloudHub {
  CloudHub({
    required this.config,
    required this.secrets,
    CloudTarget Function(CloudDestination d, String? password)? targets,
    this.profileName = 'default',
    this.auto,
  }) : _targets =
           targets ??
           ((d, password) =>
               WebdavClient(baseUrl: d.url, user: d.user, password: password));

  final CloudConfigStore config;
  final CloudSecretStore secrets;
  final String profileName;

  /// §3.3 scheduler (null in tests that never touch auto-backup).
  final CloudAutoScheduler? auto;
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
  /// The §3.3 backup key rides out with it — nothing survives the record.
  Future<void> remove(CloudDestination d) async {
    final remaining = [
      for (final e in destinations())
        if (e.id != d.id) e,
    ];
    await config.save(remaining);
    await secrets.remove(d.id);
    await secrets.remove(_autoKeySlot(d.id));
    // Removing the last auto destination must take the schedule with it;
    // the inputData never changes, so a null docsDir is honest here.
    await auto?.sync(destinations: remaining, docsDir: null);
  }

  Future<void> setPassword(CloudDestination d, String password) =>
      secrets.put(d.id, password);

  // §3.3 backup key: what unattended uploads encrypt with. Stored like the
  // destination secret (same keystore trust domain — uploads already need
  // that one to run at all, so this adds no new exposure class).
  static String _autoKeySlot(String id) => 'cloud-autokey-$id';

  Future<String?> backupKey(CloudDestination d) =>
      secrets.get(_autoKeySlot(d.id));

  Future<void> setBackupKey(CloudDestination d, String key) =>
      secrets.put(_autoKeySlot(d.id), key);

  Future<void> clearBackupKey(CloudDestination d) =>
      secrets.remove(_autoKeySlot(d.id));
}
