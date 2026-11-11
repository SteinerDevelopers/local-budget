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

// E7b §3.3 — unattended uploads. WorkManager wakes a background isolate
// at most daily, with network + battery-not-saving constraints; the tick
// below is plain Dart (unit-testable), the scheduler is a seam (widget
// tests record calls, the app runs WorkManager underneath). Android
// needs zero native setup at workmanager 0.10 — the plugin is endorsed.
import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data';

import 'package:data/data.dart';
import 'package:workmanager/workmanager.dart';

import '../../version.dart';
import 'cloud_config.dart';
import 'cloud_hub.dart';
import 'secret_store.dart';

/// The one production hub composition (main + the §3.3 background
/// isolate build it identically — same file, same keystore). The Android
/// scheduler rides along: iOS/iPad is parked, everything else has no
/// WorkManager to talk to.
CloudHub cloudHubFor(Directory docsDir) => CloudHub(
  config: CloudConfigStore(File('${docsDir.path}/cloud-destinations.json')),
  secrets: const SecureCloudSecretStore(),
  auto: Platform.isAndroid ? const WorkmanagerAutoScheduler() : null,
);

/// Pro boot: register the dispatcher and reconcile the schedule with the
/// stored toggles (register's policy is *update*, so cadence survives
/// app updates; sync is cheap and idempotent either way).
Future<void> initCloudAutoBackups(Directory dir) async {
  if (!Platform.isAndroid) return;
  Workmanager().initialize(cloudAutoBackupDispatcher);
  final hub = cloudHubFor(dir);
  await hub.auto?.sync(destinations: hub.destinations(), docsDir: dir.path);
}

/// Task + unique names the dispatcher and the scheduler agree on.
const kCloudAutoTask = 'cloud-auto-backup';
const kCloudAutoUnique = 'cloud-auto';

/// Consecutive failures before the Settings badge appears (§3.3 "three
/// retries, then a quiet badge") — and before we stop returning `false`,
/// because WorkManager retries backoff-policy forever otherwise. The
/// daily wake re-attempts regardless; the badge is what stays quiet-
/// loud until the next success.
const kAutoFailBadgeAfter = 3;

/// WorkManager's own retry backoff between the attempts that make up
/// §3.3's "3 retries with backoff" (a failed return false re-runs the
/// task after this delay, exponentially).
const kAutoBackoffDelay = Duration(minutes: 15);

/// The single tick: every auto-enabled destination gets one encrypted
/// upload of the *current* database using its enrolled backup key.
/// Returns false while any destination is still inside its retry budget,
/// so WorkManager re-runs the whole tick with backoff (§3.3); a
/// destination past the budget stops influencing the result — its
/// failure count is what the badge reads. Outcome counts persist to the
/// config file — the Settings badge reads the file, not memory.
Future<bool> runAutoBackupTick({
  required CloudHub hub,
  required Future<Uint8List> Function(String backupKey) buildBackup,
}) async {
  var retry = false;
  final all = [...hub.destinations()];
  for (var i = 0; i < all.length; i++) {
    final d = all[i];
    if (!d.autoBackup) continue;
    CloudDestination next;
    try {
      final key = await hub.backupKey(d);
      if (key == null || key.isEmpty) throw StateError('backup key missing');
      final bytes = await buildBackup(key);
      final target = await hub.targetWith(d);
      await putAndPruneVia(
        target,
        folder: d.folder,
        name: hub.nextObjectName(),
        bytes: bytes,
      );
      next = d.copyWith(autoFails: 0);
    } on Object {
      final fails = d.autoFails + 1;
      next = d.copyWith(autoFails: fails);
      if (fails < kAutoFailBadgeAfter) retry = true;
    }
    all[i] = next;
    await hub.config.save(all);
  }
  return !retry;
}

/// Production tick body: the same hub + E5 pipeline the manual flow uses,
/// rebuilt from the docs dir the schedule carried (inputData is plain
/// JSON — a path is all it needs; everything else is derived).
Future<bool> autoBackupFromDisk(String docsDirPath) async {
  final dir = Directory(docsDirPath);
  final hub = cloudHubFor(dir);
  final db = AppDatabase.openFile('${dir.path}/localbudget.sqlite');
  try {
    // Awaited, not returned straight: the finally below must not close
    // the database while the tick is still encrypting from it.
    return await runAutoBackupTick(
      hub: hub,
      buildBackup: (key) => createBackup(
        db: db,
        attachments: AttachmentStore(dir),
        passphrase: key,
        appVersion: appVersion,
      ),
    );
  } finally {
    await db.close();
  }
}

/// The background entry point WorkManager starts an isolate for. Kept a
/// top-level function so a unit test can call it without the plugin.
@pragma('vm:entry-point')
void cloudAutoBackupDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != kCloudAutoTask) return true;
    final docsDir = inputData?['docsDir'];
    if (docsDir is! String || docsDir.isEmpty) return true;
    try {
      return await autoBackupFromDisk(docsDir);
    } on Object {
      // A crashed tick must not wedge the schedule; the fail counts
      // already reflect earlier partial attempts (or none — the daily
      // wake will try again either way).
      return false;
    }
  });
}

/// The Workmanager-backed scheduler. One periodic task serves every
/// destination; [sync] is the only verb — call it after any destination
/// or toggle change and it registers (policy: update, so the cadence
/// survives app updates) or cancels when nothing wants auto-backup.
class WorkmanagerAutoScheduler implements CloudAutoScheduler {
  const WorkmanagerAutoScheduler();

  @override
  Future<void> sync({
    required List<CloudDestination> destinations,
    required String? docsDir,
  }) async {
    final wanted = destinations.any((d) => d.autoBackup);
    if (!wanted) {
      await Workmanager().cancelByUniqueName(kCloudAutoUnique);
      return;
    }
    // Scheduling without a docs dir would build a task that can never
    // find the database — that state only exists in tests.
    if (docsDir == null) return;
    await Workmanager().registerPeriodicTask(
      kCloudAutoUnique,
      kCloudAutoTask,
      frequency: const Duration(days: 1),
      inputData: {'docsDir': docsDir},
      constraints: Constraints(
        // §3.3: uploads wait for a network and a phone that is not
        // fighting to save battery — never a foreground-service.
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: kAutoBackoffDelay,
    );
  }
}
