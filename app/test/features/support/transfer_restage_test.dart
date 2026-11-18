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

import 'dart:io';
import 'dart:typed_data';

import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/support/transfer.dart';

class _StageThrows extends FakeFreeTransfer {
  _StageThrows() : super(pro: true, snapshot: Uint8List.fromList([1, 2, 3]));

  @override
  Future<void> stage(Uint8List bytes) async =>
      throw StateError('provider gone');
}

void main() {
  late Directory dir;
  late File dbFile;
  late AppDatabase db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('restage');
    dbFile = File('${dir.path}/localbudget.sqlite');
    await dbFile.writeAsBytes([0]);
    db = AppDatabase.inMemory();
  });
  tearDown(() async => dir.delete(recursive: true));

  TransferRestager make(FreeTransfer t) => TransferRestager(
    transfer: t,
    db: db,
    attachments: AttachmentStore(dir),
    dbFile: dbFile,
    kdfIterations: 1000, // the policy default is slow on purpose; this is not
  );

  /// A wal newer than the staged snapshot: the §3 "anything changed" probe.
  Future<void> touchWalNewerThan(int metaMs) async {
    final wal = File('${dbFile.path}-wal');
    await wal.writeAsBytes([9]);
    final future = DateTime.fromMillisecondsSinceEpoch(metaMs + 60000);
    await wal.setLastModified(future);
  }

  test('no Pro installed: nothing stages, even with a fresh wal', () async {
    final t = FakeFreeTransfer(pro: false, snapshot: Uint8List(4));
    await touchWalNewerThan(t.metaMs);
    await make(t).restageIfStale();
    expect(t.staged, isNull);
  });

  test(
    'button is the only entrance: nothing staged before the first tap',
    () async {
      final t = FakeFreeTransfer(pro: true); // snapshot == null → no meta
      await touchWalNewerThan(t.metaMs);
      await make(t).restageIfStale();
      expect(t.staged, isNull);
    },
  );

  test('unchanged since the last stage: no re-stage', () async {
    final fresh = DateTime.now().add(const Duration(hours: 1));
    final t = FakeFreeTransfer(
      pro: true,
      snapshot: Uint8List(4),
      metaMs: fresh.millisecondsSinceEpoch,
    );
    await make(t).restageIfStale();
    expect(t.staged, isNull);
  });

  test('changed wal after the last stage: the snapshot is re-staged', () async {
    final t = FakeFreeTransfer(pro: true, snapshot: Uint8List(4));
    await touchWalNewerThan(t.metaMs);
    await make(t).restageIfStale();
    expect(t.staged, isNotNull);
    expect(t.staged!.length, greaterThan(100)); // a real envelope, not stubs
  });

  test(
    'a failing stage is swallowed — the old snapshot keeps serving',
    () async {
      final t = _StageThrows();
      await touchWalNewerThan(t.metaMs);
      await expectLater(make(t).restageIfStale(), completes);
    },
  );

  test('two pauses on one restager stage once — the guard holds', () async {
    final t = _Counting();
    await touchWalNewerThan(t.metaMs);
    final r = make(t);
    // One instance, two overlapping pauses (rapid background flips).
    await Future.wait([r.restageIfStale(), r.restageIfStale()]);
    expect(t.stages, 1);
  });
}

class _Counting extends FakeFreeTransfer {
  _Counting() : super(pro: true, snapshot: Uint8List(4));

  int stages = 0;

  @override
  Future<void> stage(Uint8List bytes) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    super.stage(bytes);
    stages++;
  }
}
