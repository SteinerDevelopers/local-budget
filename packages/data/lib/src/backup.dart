/// `.lzbak` container: manifest + consistent DB snapshot + every original,
/// PBKDF2-encrypted (E5 spec §3). Backup is free and never touches network.
library;

import 'dart:convert';
import 'dart:io';
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

/// Snapshots [db] with `VACUUM INTO` (atomic, consistent, WAL-free — safe
/// while the app keeps writing), packs it with [attachments] and a manifest,
/// and seals the zip under a PBKDF2/AES-256-GCM container.
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

  final zip = Archive();
  void add(String name, Uint8List data) =>
      zip.addFile(ArchiveFile(name, data.length, data));
  add(
    'manifest.json',
    Uint8List.fromList(utf8.encode(jsonEncode(manifest.toJson()))),
  );
  add('ledger.db', dbBytes);
  originals.forEach(add);
  final zipBytes = Uint8List.fromList(ZipEncoder().encode(zip));

  final header = backupBuildHeader(
    salt: backupRandomSalt(),
    iterations: kdfIterations,
    nonce: backupRandomNonce(),
  );
  final key = backupDeriveKey(
    passphrase: passphrase,
    salt: Uint8List.sublistView(header, 6, 22),
    iterations: kdfIterations,
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
/// newer file is refused with [BackupSchemaTooNewException].
Backup openBackup(
  Uint8List bytes, {
  required String passphrase,
  required int currentSchemaVersion,
}) {
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
