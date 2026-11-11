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

// E7b §6 — the cloud destinations UI over an in-memory CloudTarget:
// editor (config JSON holds no secret), upload→prune on "Back up now",
// the versions list, the LAN red banner, and the free/pro gate on the
// Manage tile (the CI grep-guard covers imports; this covers composition).
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:typed_data';

import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/cloud/cloud_backup_screen.dart';
import 'package:local_budget/features/cloud/cloud_config.dart';
import 'package:local_budget/features/cloud/cloud_hub.dart';
import 'package:local_budget/features/cloud/secret_store.dart';
import 'package:local_budget/flavor.dart';
import 'package:local_budget/main.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

class _FakeTarget implements CloudTarget {
  final Map<String, Uint8List> files = {};

  @override
  Future<void> ensureCollection(String relPath) async {}

  @override
  Future<List<CloudObject>> list(String relPath) async => [
    for (final e in files.entries)
      if (e.key.startsWith('$relPath/'))
        CloudObject(
          name: e.key.substring(relPath.length + 1),
          path: e.key,
          size: e.value.length,
          modified: DateTime.utc(2026, 10, 1),
        ),
  ];

  @override
  Future<void> put(String relPath, Uint8List bytes) async =>
      files[relPath] = bytes;

  @override
  Future<Uint8List> get(String relPath) async => files[relPath]!;

  @override
  Future<void> delete(String relPath) async => files.remove(relPath);
}

const _nas = CloudDestination(
  id: 'nas1',
  label: 'NAS',
  url: 'https://nas.example/dav',
  user: 'steiner',
  folder: 'localbudget',
);

const _lan = CloudDestination(
  id: 'lan1',
  label: 'Kitchen box',
  url: 'http://192.168.1.9:8080/dav',
  user: 'guest',
  folder: 'localbudget',
);

/// Backup names on 2026-10-[day] at distinct hours (same-day overflow is
/// what §3.2 collapse actually prunes).
String _objHour(int day, int hour) =>
    'localbudget-default-202610${day.toString().padLeft(2, '0')}-'
    '${hour.toString().padLeft(2, '0')}00.lzbak';

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );
  final isPro = appFlavor == AppFlavor.pro;

  late Directory tmp;
  late MemoryCloudSecretStore store;
  late _FakeTarget target;
  late CloudHub hub;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cloudcfg');
    store = MemoryCloudSecretStore();
    target = _FakeTarget();
    hub = CloudHub(
      config: CloudConfigStore(File('${tmp.path}/cloud-destinations.json')),
      secrets: store,
      profileName: 'default',
      targets: (d, pw) => target,
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// Config writes are real file IO — the fake-async zone needs runAsync
  /// around any tap (or seed) that persists the destination list.
  Future<void> seed(WidgetTester tester, CloudDestination d) =>
      tester.runAsync(() => hub.upsert(d, password: 'pw'));

  Future<void> tapReal(WidgetTester tester, Finder f) =>
      tester.runAsync(() async {
        // the §3.3 auto row pushed the lower actions off short viewports
        await tester.ensureVisible(f);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tap(f);
        await tester.pumpAndSettle(); // modal pop animation is fake-time
        // hub continuation (secret + config file IO) runs after the pop…
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await tester.pumpAndSettle(); // …so the list redraw follows
      });

  /// Poll until [done]: pump (fake) flushes the widget-side continuations,
  /// the real delay lets file IO land — neither alone is enough here.
  Future<void> waitReal(WidgetTester tester, Future<bool> Function() done) =>
      tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 10));
          await Future<void>.delayed(const Duration(milliseconds: 5));
          if (await done()) return;
        }
      });

  Future<void> pumpScreen(WidgetTester tester) => tester
      .pumpWidget(
        MaterialApp(
          home: CloudBackupScreen(
            hub: hub,
            // fake encrypt step — no db, no KDF (the seam CI's host needs)
            buildBackup: (pw) async => Uint8List.fromList([1, 2, 3, 4]),
          ),
        ),
      )
      .then((_) => tester.pumpAndSettle());

  // ---- hub + config (no widgets) --------------------------------------

  test('config roundtrips through disk; remove scrubs the secret', () async {
    await hub.upsert(_nas, password: 's3cret');
    await hub.upsert(_lan, password: 'guestpw');
    final file = File('${tmp.path}/cloud-destinations.json');
    expect(file.readAsStringSync(), contains('NAS'));
    expect(file.readAsStringSync(), isNot(contains('s3cret')));

    final reopened = CloudHub(
      config: CloudConfigStore(file),
      secrets: store,
      targets: (d, pw) => target,
    );
    expect(reopened.destinations().map((d) => d.id), ['nas1', 'lan1']);
    expect(await store.get('nas1'), 's3cret');

    await reopened.remove(_nas);
    expect(reopened.destinations().map((d) => d.id), ['lan1']);
    expect(await store.get('nas1'), isNull); // §3.1: scrubbed
    expect(await store.get('lan1'), 'guestpw');
  });

  test('nextObjectName follows the §3.2 grammar', () {
    final name = hub.nextObjectName();
    expect(isBackupObject(name), isTrue);
    expect(parseBackupObjectTime(name), isNotNull);
  });

  // ---- editor ------------------------------------------------------------

  testWidgets('add destination: saves config, stores secret masked', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tapReal(tester, find.byKey(const Key('cloud-add')));
    await tester.enterText(find.byKey(const Key('dest-label')), 'Box');
    await tester.enterText(
      find.byKey(const Key('dest-url')),
      'https://box.example/dav',
    );
    await tester.enterText(find.byKey(const Key('dest-user')), 'me');
    await tester.enterText(find.byKey(const Key('dest-password')), 'hunter2');
    await tapReal(tester, find.byKey(const Key('cloud-save')));
    await waitReal(tester, () async {
      final ds = hub.destinations();
      return ds.length == 1 && await store.get(ds.single.id) == 'hunter2';
    });

    expect(find.text('Box'), findsOneWidget);
    final id = hub.destinations().single.id;
    expect(await store.get(id), 'hunter2');
    expect(
      File('${tmp.path}/cloud-destinations.json').readAsStringSync(),
      isNot(contains('hunter2')),
    );
  });

  testWidgets('editor refuses a non-WebDAV URL and stays open', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('cloud-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('dest-label')), 'X');
    await tester.enterText(find.byKey(const Key('dest-url')), 'ftp://nope');
    await tester.enterText(find.byKey(const Key('dest-user')), 'u');
    await tester.tap(find.byKey(const Key('cloud-save')));
    await tester.pumpAndSettle();
    expect(hub.destinations(), isEmpty);
    expect(find.byKey(const Key('dest-url')), findsOneWidget); // still editing
  });

  testWidgets('plain-HTTP LAN url gets the red banner on the tile', (
    tester,
  ) async {
    await seed(tester, _lan);
    await pumpScreen(tester);
    expect(find.byKey(const Key('lan-banner-lan1')), findsOneWidget);
  });

  testWidgets('https destination has no banner', (tester) async {
    await seed(tester, _nas);
    await pumpScreen(tester);
    expect(find.byKey(const Key('lan-banner-nas1')), findsNothing);
  });

  // ---- back up now ---------------------------------------------------------

  testWidgets('back up now: confirm → passphrase → upload + §3.2 prune', (
    tester,
  ) async {
    for (var hour = 1; hour <= 13; hour++) {
      target.files['localbudget/${_objHour(5, hour)}'] = Uint8List(8);
    }
    await seed(tester, _nas);
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('dest-nas1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cloud-backup-now')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cloud-backup-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cloud-backup-go')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('passphrase-field')),
      'correct horse',
    );
    await tester.enterText(
      find.byKey(const Key('passphrase-confirm-field')),
      'correct horse',
    );
    await tester.tap(find.byKey(const Key('passphrase-next')));
    await tester.pumpAndSettle();

    final names = target.files.keys.map((k) => k.split('/').last).toList();
    final fresh = names.firstWhere((n) => !n.contains('20261005'));
    expect(isBackupObject(fresh), isTrue);
    // 13 seeded on one day + 1 new, newest 12 kept → the two oldest
    // same-day objects collapse away (§3.2), the rest of that day stays.
    expect(target.files, hasLength(12));
    expect(target.files.containsKey('localbudget/${_objHour(5, 1)}'), isFalse);
    expect(target.files.containsKey('localbudget/${_objHour(5, 2)}'), isFalse);
    expect(target.files.containsKey('localbudget/${_objHour(5, 13)}'), isTrue);
    expect(find.textContaining('Uploaded $fresh'), findsOneWidget);
  });

  // ---- versions -------------------------------------------------------------

  testWidgets('versions list filters foreign files; delete removes', (
    tester,
  ) async {
    target.files['localbudget/${_objHour(3, 12)}'] = Uint8List(2048);
    target.files['localbudget/notes.txt'] = Uint8List(4);
    await seed(tester, _nas);
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('dest-nas1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cloud-versions')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('version-${_objHour(3, 12)}')), findsOneWidget);
    expect(find.textContaining('2026-10-03 12:00 UTC'), findsOneWidget);
    expect(find.textContaining('2 kB'), findsOneWidget);
    expect(find.textContaining('notes.txt'), findsNothing);

    await tester.tap(find.byKey(Key('drop-${_objHour(3, 12)}')));
    await tester.pumpAndSettle();
    expect(target.files.containsKey('localbudget/${_objHour(3, 12)}'), isFalse);
    expect(find.textContaining('Deleted ${_objHour(3, 12)}'), findsOneWidget);
  });

  testWidgets('remove destination scrubs the secret but keeps remote files', (
    tester,
  ) async {
    target.files['localbudget/${_objHour(5, 9)}'] = Uint8List(8);
    await seed(tester, _nas);
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('dest-nas1')));
    await tester.pumpAndSettle();
    await tapReal(tester, find.byKey(const Key('cloud-delete-dest')));
    await waitReal(
      tester,
      () async => hub.destinations().isEmpty && await store.get('nas1') == null,
    );

    expect(hub.destinations(), isEmpty);
    expect(await store.get('nas1'), isNull);
    expect(target.files, hasLength(1)); // §3.1: the files stay — user's data
  });

  // ---- the free/pro gate on the Manage tile ------------------------------

  Future<void> openManage(WidgetTester tester, Widget app) async {
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('receipt-add')));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Manage'),
      find.byKey(const Key('chip-row')),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Manage'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('About & help'),
      find.byType(ListView).last,
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
  }

  Future<void> manageWithHub(WidgetTester tester) async {
    final db = AppDatabase.inMemory();
    final repo = LedgerRepository(db);
    await openManage(
      tester,
      LocalBudgetApp(repository: repo, db: db, cloud: hub),
    );
    await db.close(); // inside the body — tearDown closing deadlocks
  }

  testWidgets('free flavor never composes the Cloud backups tile', (
    tester,
  ) async {
    await manageWithHub(tester);
    expect(find.byKey(const Key('cloud-backups')), findsNothing);
    expect(find.text('Restore from backup'), findsOneWidget); // scrolled there
  }, skip: isPro); // free-only assertion (pro self-skips like the E7a gates)

  testWidgets('pro flavor builds the Cloud backups tile', (tester) async {
    await manageWithHub(tester);
    expect(find.byKey(const Key('cloud-backups')), findsOneWidget);
  }, skip: !isPro); // pro rows run only with --dart-define=APP_FLAVOR=pro
}
