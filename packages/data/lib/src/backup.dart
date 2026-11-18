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

/// `.lzbak` container: manifest + consistent DB snapshot + every original,
/// PBKDF2-encrypted (E5 spec §3). Backup is free and never touches network.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

import 'attachment_store.dart';
import 'backup_crypto.dart';
import 'database.dart';
import 'integrity.dart';

/// Passphrase for the E6 §3 free→paid *transfer snapshot*: one pipeline, one
/// envelope, zero plaintext special-casing. It is obfuscation, not a secret
/// (compiled into both apps of the same family; the spec's threat model says
/// so out loud) — its job is format honesty, not confidentiality against a
/// rooted device.
const String transferPassphrase = 'localbudget-app-transfer-v1';

/// The four fields the spec promises in `manifest.json` — deliberately
/// minimal, all we need to explain and vet a restore before touching disk.
class BackupManifest {
  const BackupManifest({
    required this.appVersion,
    required this.schemaVersion,
    required this.createdAt,
    required this.attachmentCount,
  });

  final String appVersion;
  final int schemaVersion;
  final DateTime createdAt;
  final int attachmentCount;

  Map<String, Object> toJson() => {
    'appVersion': appVersion,
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'attachmentCount': attachmentCount,
  };

  static BackupManifest parse(String text) {
    Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException {
      throw const BackupFormatException('manifest is not JSON');
    }
    if (raw is! Map) {
      throw const BackupFormatException('manifest is not an object');
    }
    final v = raw['appVersion'], s = raw['schemaVersion'];
    final c = raw['createdAt'], a = raw['attachmentCount'];
    if (v is! String || s is! int || c is! String || a is! int) {
      throw const BackupFormatException('manifest fields malformed');
    }
    final created = DateTime.tryParse(c);
    if (created == null) throw const BackupFormatException('bad createdAt');
    return BackupManifest(
      appVersion: v,
      schemaVersion: s,
      createdAt: created.toUtc(),
      attachmentCount: a,
    );
  }
}

/// A decrypted, tag-verified backup, ready to be shown to the user and then
/// applied: the `VACUUM INTO` snapshot plus attachments keyed exactly like
/// `transactions.imageRef` stores them (`attachments/<name>`).
class Backup {
  const Backup({
    required this.manifest,
    required this.databaseBytes,
    required this.attachments,
  });

  final BackupManifest manifest;
  final Uint8List databaseBytes;
  final Map<String, Uint8List> attachments;
}

/// A backup from a *newer* app cannot be opened by this build; the schema it
/// describes may carry columns we would silently drop on reopen.
class BackupSchemaTooNewException implements Exception {
  const BackupSchemaTooNewException(this.fileSchema, this.buildSchema);
  final int fileSchema;
  final int buildSchema;
  @override
  String toString() =>
      'BackupSchemaTooNewException: backup schema v$fileSchema needs a '
      'newer app (this build is v$buildSchema)';
}

/// VisibleForTesting opt-out seam for the worker-isolate offload in
/// [createBackup]/[openBackup]. Widget tests drive these paths with a fake
/// clock that can never observe a real isolate completing (measured: flutter
/// test does not propagate declaration zones into test bodies either), so a
/// test file flips this flag once and keeps the crypto on the caller's
/// isolate — byte-for-byte the same seal/open functions, only the thread
/// changes. The isolate path is what ships, and it is tested unconditionally
/// by the data package (`test/backup_test.dart`) and the bench soak; no
/// production entry point ever touches this flag (each test file is its own
/// isolate, so the flag cannot leak across files).
bool backupSyncForTest = false;

/// Snapshots [db] with `VACUUM INTO` (atomic, consistent, WAL-free — safe
/// while the app keeps writing), packs it with [attachments] and a manifest,
/// and seals the zip under a PBKDF2/AES-256-GCM container.
///
/// The heavy half — zip encode + PBKDF2 + AES-GCM — runs on a worker
/// isolate. Release-mode ANR, 2026-11-18 soak bench: the production KDF
/// cost alone froze the UI isolate past the 5 s input-dispatch budget, and
/// the background cgroup's CPU share stretched the seal to ~30 s once the
/// user switched apps mid-copy. A user-facing computation longer than a
/// heartbeat may never run on the UI isolate (playbook device law). Only
/// the millisecond-scale `VACUUM INTO` snapshot stays here: it needs the
/// open database handle, which cannot cross isolates.
Future<Uint8List> createBackup({
  required AppDatabase db,
  required AttachmentStore attachments,
  required String passphrase,
  required String appVersion,
  int kdfIterations = backupDefaultKdfIterations,
  DateTime? now,
}) async {
  if (passphrase.isEmpty) {
    throw const BackupFormatException('backup needs a passphrase');
  }
  final snapDir = Directory.systemTemp.createTempSync('lzbak');
  final Uint8List dbBytes;
  try {
    // §7: a restore must never be missing recent commits — checkpoint WAL
    // before the snapshot (no-op on rollback-journal databases).
    await DbIntegrity.walCheckpoint(db);
    final target = '${snapDir.path}/ledger.db';
    await db.customStatement('VACUUM INTO ?', [target]);
    dbBytes = File(target).readAsBytesSync();
  } finally {
    snapDir.deleteSync(recursive: true);
  }

  final originals = attachments.listOriginals();
  final manifest = BackupManifest(
    appVersion: appVersion,
    schemaVersion: db.schemaVersion,
    createdAt: (now ?? DateTime.now()).toUtc(),
    attachmentCount: originals.length,
  );

  final job = _SealJob(
    // Insertion order is part of the format: manifest, ledger, attachments.
    files: {
      'manifest.json': Uint8List.fromList(
        utf8.encode(jsonEncode(manifest.toJson())),
      ),
      'ledger.db': dbBytes,
      ...originals,
    },
    passphrase: passphrase,
    iterations: kdfIterations,
    salt: backupRandomSalt(),
    nonce: backupRandomNonce(),
  );
  // The heavy half runs off the UI isolate (see the method doc); salt and
  // nonce are drawn here so the CSPRNG stays seeded by the platform.
  if (backupSyncForTest) return _sealBackup(job);
  return Isolate.run(() => _sealBackup(job));
}

class _SealJob {
  const _SealJob({
    required this.files,
    required this.passphrase,
    required this.iterations,
    required this.salt,
    required this.nonce,
  });
  final Map<String, Uint8List> files;
  final String passphrase;
  final int iterations;
  final Uint8List salt;
  final Uint8List nonce;
}

Uint8List _sealBackup(_SealJob job) {
  final zip = Archive();
  job.files.forEach(
    (name, data) => zip.addFile(ArchiveFile(name, data.length, data)),
  );
  final zipBytes = Uint8List.fromList(ZipEncoder().encode(zip));

  final header = backupBuildHeader(
    salt: job.salt,
    iterations: job.iterations,
    nonce: job.nonce,
  );
  final key = backupDeriveKey(
    passphrase: job.passphrase,
    salt: Uint8List.sublistView(header, 6, 22),
    iterations: job.iterations,
  );
  final body = backupSeal(
    plaintext: zipBytes,
    key: key,
    nonce: Uint8List.sublistView(header, 26, 38),
    aad: header,
  );
  final container = Uint8List(header.length + body.length);
  container.setRange(0, header.length, header);
  container.setRange(header.length, container.length, body);
  return container;
}

/// Verifies magic → header sanity → derives → GCM tag → zip → manifest.
/// [currentSchemaVersion] is the caller's `AppDatabase.schemaVersion`; a
/// newer file is refused with [BackupSchemaTooNewException]. The PBKDF2
/// derive + GCM open run off the UI isolate like [createBackup] (same ANR
/// law); the refusal exceptions are plain data and cross the isolate
/// boundary unchanged.
Future<Backup> openBackup(
  Uint8List bytes, {
  required String passphrase,
  required int currentSchemaVersion,
}) {
  if (backupSyncForTest) {
    return Future.value(
      _openBackupSync(bytes, passphrase, currentSchemaVersion),
    );
  }
  return Isolate.run(
    () => _openBackupSync(bytes, passphrase, currentSchemaVersion),
  );
}

Backup _openBackupSync(
  Uint8List bytes,
  String passphrase,
  int currentSchemaVersion,
) {
  final header = backupParseHeader(bytes);
  final key = backupDeriveKey(
    passphrase: passphrase,
    salt: header.salt,
    iterations: header.iterations,
  );
  final zipBytes = backupOpen(
    sealed: Uint8List.sublistView(bytes, backupHeaderBytes),
    key: key,
    nonce: header.nonce,
    aad: Uint8List.sublistView(bytes, 0, backupHeaderBytes),
  );

  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zipBytes);
  } catch (_) {
    throw const BackupFormatException('sealed payload is not a zip');
  }

  BackupManifest? manifest;
  Uint8List? dbBytes;
  final attachments = <String, Uint8List>{};
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final data = file.content;
    if (file.name == 'manifest.json') {
      manifest = BackupManifest.parse(utf8.decode(data));
    } else if (file.name == 'ledger.db') {
      dbBytes = data;
    } else if (AttachmentStore.isSafeRel(file.name)) {
      // Restore input is hostile-by-default: only `attachments/<file>` lands.
      attachments[file.name] = data;
    }
  }
  if (manifest == null || dbBytes == null) {
    throw const BackupFormatException('manifest or ledger.db missing');
  }
  if (manifest.schemaVersion > currentSchemaVersion) {
    throw BackupSchemaTooNewException(
      manifest.schemaVersion,
      currentSchemaVersion,
    );
  }
  if (manifest.attachmentCount != attachments.length) {
    throw const BackupFormatException('attachment count mismatch');
  }
  return Backup(
    manifest: manifest,
    databaseBytes: dbBytes,
    attachments: attachments,
  );
}

/// Replaces the live device state wholesale (spec §3: a coherent rollback —
/// files created after the backup go too, by design). The caller **must**
/// close its `AppDatabase` first and cold-restart the UI stack afterwards;
/// this is the only destructive path in the app and the UI asks once,
/// explicitly, naming both casualties before calling it.
Future<void> applyRestore(
  Backup backup, {
  required String dbPath,
  required Directory root,
}) async {
  for (final side in ['$dbPath-wal', '$dbPath-shm']) {
    final f = File(side);
    if (f.existsSync()) f.deleteSync();
  }
  await File(dbPath).writeAsBytes(backup.databaseBytes, flush: true);

  final dir = Directory('${root.path}/${AttachmentStore.dirName}');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  for (final entry in backup.attachments.entries) {
    // Names were vetted at open; re-assert before touching the filesystem.
    if (!AttachmentStore.isSafeRel(entry.key)) {
      throw ArgumentError.value(entry.key, 'attachments', 'not a path');
    }
    await File(
      '${root.path}/${entry.key}',
    ).writeAsBytes(entry.value, flush: true);
  }
}
