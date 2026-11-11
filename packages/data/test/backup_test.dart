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

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:test/test.dart';

void main() {
  // Sequential openFile() instances on one path (close between) are by
  // design in the restore test; silence drift's heuristic warning.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  // 1 024 iterations keeps the suite honest-fast; production default is
  // asserted separately.
  const cheapKdf = 1024;
  final fixedNow = DateTime.utc(2026, 11, 2, 12);
  final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);

  late Directory root;
  late AppDatabase db;
  late LedgerRepository repo;
  late AttachmentStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lzbak-test');
    db = AppDatabase.inMemory();
    repo = LedgerRepository(db);
    store = AttachmentStore(root);
  });
  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  Future<int> usdAccount() =>
      repo.createAccount(name: 'Cash', currencyCode: 'USD');

  Future<void> seed(int n, {int accountShift = 0}) async {
    final a = await usdAccount();
    for (var i = 0; i < n; i++) {
      await repo.addTransaction(
        accountId: a,
        date: DateTime(2026, 11, 1 + ((i + accountShift) % 28)),
        amount: Money.tryParse('${i + 1}.00', Currency.resolve('USD'))!,
        source: TransactionSource.manual,
        merchant: 'Store $i',
      );
    }
  }

  Future<int> txCount(AppDatabase d) async =>
      (await d.select(d.transactions).get()).length;

  Future<Uint8List> makeBackup({String passphrase = 'correct horse'}) =>
      createBackup(
        db: db,
        attachments: store,
        passphrase: passphrase,
        appVersion: '1.2.3',
        kdfIterations: cheapKdf,
        now: fixedNow,
      );

  group('backup container', () {
    test('production KDF default is 600 000 iterations', () {
      expect(backupDefaultKdfIterations, 600000);
    });

    test(
      'E6 §3 transfer snapshot: constant passphrase, same envelope',
      () async {
        await seed(2);
        final bytes = await makeBackup(passphrase: transferPassphrase);
        // Pro opens it with the compiled-in constant — no user prompt anywhere.
        final backup = openBackup(
          bytes,
          passphrase: transferPassphrase,
          currentSchemaVersion: db.schemaVersion,
        );
        expect(backup.manifest.appVersion, '1.2.3');
        final snapFile = File('${root.path}/transfer.db');
        snapFile.writeAsBytesSync(backup.databaseBytes);
        final reopened = AppDatabase.openFile(snapFile.path);
        try {
          expect(await txCount(reopened), 2);
        } finally {
          await reopened.close();
        }
        // The envelope is still a real envelope: the constant is not a bypass.
        expect(
          () => openBackup(
            bytes,
            passphrase: 'not-the-constant',
            currentSchemaVersion: db.schemaVersion,
          ),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('header fields, full round-trip, snapshot is a real DB', () async {
      await seed(2);
      final saved = store.saveOriginal(
        png,
        extension: 'jpg',
        source: TransactionSource.cameraScan,
      );
      final bytes = await makeBackup();

      expect(latin1.decode(bytes.sublist(0, 5)), backupMagic);
      expect(bytes[5], backupFormatVersion);
      expect(
        ByteData.sublistView(bytes, 22, 26).getUint32(0, Endian.big),
        cheapKdf,
      );

      final backup = openBackup(
        bytes,
        passphrase: 'correct horse',
        currentSchemaVersion: db.schemaVersion,
      );
      expect(backup.manifest.appVersion, '1.2.3');
      expect(backup.manifest.schemaVersion, db.schemaVersion);
      expect(backup.manifest.createdAt, fixedNow);
      expect(backup.manifest.attachmentCount, 1);
      expect(backup.attachments.keys.single, saved);
      expect(backup.attachments[saved], png);

      // The snapshot must open as a plain SQLite file and carry the ledger.
      final snapFile = File('${root.path}/reopen.db');
      snapFile.writeAsBytesSync(backup.databaseBytes);
      final reopened = AppDatabase.openFile(snapFile.path);
      try {
        expect(await txCount(reopened), 2);
      } finally {
        await reopened.close();
      }
    });

    test('random salt+nonce: two backups of the same state differ', () async {
      await seed(1);
      final a = await makeBackup();
      final b = await makeBackup();
      expect(a, isNot(equals(b)));
    });

    test('wrong passphrase fails the GCM tag', () async {
      await seed(1);
      final bytes = await makeBackup();
      expect(
        () => openBackup(
          bytes,
          passphrase: 'wrong horse',
          currentSchemaVersion: db.schemaVersion,
        ),
        throwsA(isA<BackupPassphraseException>()),
      );
    });

    test(
      'flipped ciphertext byte is indistinguishable from a wrong pw',
      () async {
        await seed(1);
        final bytes = await makeBackup();
        bytes[backupHeaderBytes + 5] ^= 0x01;
        expect(
          () => openBackup(
            bytes,
            passphrase: 'correct horse',
            currentSchemaVersion: db.schemaVersion,
          ),
          throwsA(isA<BackupPassphraseException>()),
        );
      },
    );

    test(
      'foreign, truncated, or version-mismatched files are format errors',
      () async {
        final junk = Uint8List.fromList(latin1.encode('NOT A BACKUP FILE' * 4));
        expect(
          () => openBackup(
            junk,
            passphrase: 'x',
            currentSchemaVersion: db.schemaVersion,
          ),
          throwsA(isA<BackupFormatException>()),
        );
        await seed(1);
        final bytes = await makeBackup();
        expect(
          () => openBackup(
            bytes.sublist(0, 30),
            passphrase: 'x',
            currentSchemaVersion: db.schemaVersion,
          ),
          throwsA(isA<BackupFormatException>()),
        );
        bytes[5] = 99; // unsupported container version, refused before KDF
        expect(
          () => openBackup(
            bytes,
            passphrase: 'correct horse',
            currentSchemaVersion: db.schemaVersion,
          ),
          throwsA(isA<BackupFormatException>()),
        );
      },
    );

    test(
      'backup from a newer schema is refused: "update the app first"',
      () async {
        await seed(1);
        final bytes = await makeBackup();
        expect(
          () => openBackup(
            bytes,
            passphrase: 'correct horse',
            currentSchemaVersion: db.schemaVersion - 1,
          ),
          throwsA(isA<BackupSchemaTooNewException>()),
        );
      },
    );

    test(
      'applyRestore replaces device state whole (post-backup files go)',
      () async {
        final dbPath = '${root.path}/ledger.db';
        final fileDb = AppDatabase.openFile(dbPath);
        final fileRepo = LedgerRepository(fileDb);
        final a = await fileRepo.createAccount(
          name: 'Cash',
          currencyCode: 'USD',
        );
        await fileRepo.addTransaction(
          accountId: a,
          date: DateTime(2026, 11, 1),
          amount: Money.tryParse('5.00', Currency.resolve('USD'))!,
          source: TransactionSource.manual,
          merchant: 'Before',
        );
        store.saveOriginal(
          png,
          extension: 'jpg',
          source: TransactionSource.cameraScan,
        );
        final bytes = await createBackup(
          db: fileDb,
          attachments: store,
          passphrase: 'pw',
          appVersion: '1.2.3',
          kdfIterations: cheapKdf,
          now: fixedNow,
        );
        await fileDb.close();

        // Life goes on after the backup: a new transaction and a new image.
        final later = AppDatabase.openFile(dbPath);
        await LedgerRepository(later).addTransaction(
          accountId: a,
          date: DateTime(2026, 11, 2),
          amount: Money.tryParse('7.00', Currency.resolve('USD'))!,
          source: TransactionSource.manual,
          merchant: 'After',
        );
        store.saveOriginal(
          Uint8List.fromList([1, 2, 3]),
          extension: 'png',
          source: TransactionSource.screenshotImport,
        );
        await later.close();

        final backup = openBackup(
          bytes,
          passphrase: 'pw',
          currentSchemaVersion: db.schemaVersion,
        );
        await applyRestore(backup, dbPath: dbPath, root: root);

        final restored = AppDatabase.openFile(dbPath);
        try {
          final rows = await restored.select(restored.transactions).get();
          expect(rows, hasLength(1));
          final merchants = await restored.select(restored.merchants).get();
          expect(merchants.map((m) => m.name), ['Before']);
        } finally {
          await restored.close();
        }
        // The "After" image was rolled back too — restore replaces the whole
        // attachments directory (spec §3 coherent device-state rollback).
        final originals = store.listOriginals();
        expect(originals.values.single, png);
      },
    );
  });
}
