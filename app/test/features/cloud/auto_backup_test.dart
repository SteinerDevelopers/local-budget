// E7b §3.3 — automatic backups. The tick is pure Dart (no plugin), so
// the retry budget, key enrolment, and schedule sync are unit-testable
// end to end; the Workmanager scheduler itself is only reachable on a
// device and stays behind the CloudAutoScheduler seam tested here.
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:typed_data';

import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/cloud/auto_backup.dart';
import 'package:local_budget/features/cloud/cloud_backup_screen.dart';
import 'package:local_budget/features/cloud/cloud_config.dart';
import 'package:local_budget/features/cloud/cloud_hub.dart';
import 'package:local_budget/features/cloud/secret_store.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

class _FakeTarget implements CloudTarget {
  final Map<String, Uint8List> files = {};
  bool failing = false;

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
  Future<void> put(String relPath, Uint8List bytes) async {
    if (failing) throw StateError('webdav 503');
    files[relPath] = bytes;
  }

  @override
  Future<Uint8List> get(String relPath) async => files[relPath]!;

  @override
  Future<void> delete(String relPath) async => files.remove(relPath);
}

/// Records every reconcile so the widget test can assert the scheduler
/// saw exactly the toggle changes the user made.
class _FakeScheduler implements CloudAutoScheduler {
  final List<List<String>> syncs = [];

  @override
  Future<void> sync({
    required List<CloudDestination> destinations,
    required String? docsDir,
  }) async {
    syncs.add([
      for (final d in destinations)
        if (d.autoBackup) d.id,
    ]);
  }
}

final _base = CloudDestination(
  id: 'nas1',
  label: 'NAS',
  url: 'https://nas.example/dav',
  user: 'steiner',
  folder: 'localbudget',
);

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  late Directory tmp;
  late MemoryCloudSecretStore store;
  late _FakeTarget target;
  late _FakeScheduler scheduler;
  late CloudHub hub;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('autobak');
    store = MemoryCloudSecretStore();
    target = _FakeTarget();
    scheduler = _FakeScheduler();
    hub = CloudHub(
      config: CloudConfigStore(File('${tmp.path}/cloud-destinations.json')),
      secrets: store,
      profileName: 'default',
      targets: (d, pw) => target,
      auto: scheduler,
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> enrol(CloudDestination d, {int autoFails = 0}) async {
    await hub.setBackupKey(d, 'daily key');
    await hub.upsert(d.copyWith(autoBackup: true, autoFails: autoFails));
  }

  Future<bool> tick() =>
      runAutoBackupTick(hub: hub, buildBackup: (k) async => Uint8List(16));

  CloudDestination dest() => hub.destinations().single;

  // ---- the tick (§3.3 retry budget) -------------------------------------

  test(
    'enrolled destination uploads; success keeps the counter at zero',
    () async {
      await enrol(_base);
      expect(await tick(), isTrue);
      expect(target.files.keys, hasLength(1));
      expect(
        target.files.keys.single.startsWith('localbudget/localbudget-default-'),
        isTrue,
      );
      expect(dest().autoFails, 0);
    },
  );

  test(
    'a success after failures resets the counter (§3.3 quiet badge off)',
    () async {
      await enrol(_base, autoFails: kAutoFailBadgeAfter);
      expect(await tick(), isTrue);
      expect(dest().autoFails, 0);
    },
  );

  test('failure inside the budget counts one and asks for a retry', () async {
    await enrol(_base);
    target.failing = true;
    expect(await tick(), isFalse); // WorkManager re-runs with backoff
    expect(dest().autoFails, 1);
    expect(target.files, isEmpty);
  });

  test('the third consecutive failure goes quiet — badge takes over', () async {
    await enrol(_base, autoFails: kAutoFailBadgeAfter - 1);
    target.failing = true;
    // Unbounded WorkManager retries would spam a dead server forever;
    // at the budget we return true and let the Settings badge speak.
    expect(await tick(), isTrue);
    expect(dest().autoFails, kAutoFailBadgeAfter);
  });

  test(
    'a destination without its enrolled key fails like a dead server',
    () async {
      await hub.upsert(_base.copyWith(autoBackup: true)); // toggle sans key
      expect(await tick(), isFalse);
      expect(dest().autoFails, 1);
      expect(target.files, isEmpty);
    },
  );

  test('destinations without the toggle are never touched', () async {
    await hub.upsert(_base);
    expect(await tick(), isTrue);
    expect(target.files, isEmpty);
    expect(dest().autoFails, 0);
  });

  test('the tick persists its outcome — survives a restart', () async {
    await enrol(_base);
    target.failing = true;
    await tick();
    // A fresh hub off the same file: the badge reads disk, not memory.
    final reopened = CloudHub(
      config: CloudConfigStore(File('${tmp.path}/cloud-destinations.json')),
      secrets: store,
      targets: (d, pw) => target,
    );
    expect(reopened.destinations().single.autoFails, 1);
  });

  // ---- config + key lifecycle -------------------------------------------

  test('legacy config without the auto fields loads untouched', () async {
    // The exact shape 5803be0 shipped — pre-§3.3 records must still load.
    File('${tmp.path}/cloud-destinations.json').writeAsStringSync('''
[{"id":"nas1","label":"NAS","url":"https://nas.example/dav","user":"steiner","folder":"localbudget"}]
''');
    final reopened = CloudHub(
      config: CloudConfigStore(File('${tmp.path}/cloud-destinations.json')),
      secrets: store,
    );
    expect(reopened.destinations().single.autoBackup, isFalse);
    expect(reopened.destinations().single.autoFails, 0);
  });

  test('removing a destination scrubs the backup key and re-syncs', () async {
    await enrol(_base);
    await hub.remove(_base);
    expect(await store.get('cloud-autokey-nas1'), isNull);
    expect(scheduler.syncs.last, isEmpty); // schedule cancelled
  });

  // ---- the Settings toggle -----------------------------------------------

  Future<void> pumpScreen(WidgetTester tester) => tester
      .pumpWidget(
        MaterialApp(
          home: CloudBackupScreen(
            hub: hub,
            docsDir: tmp,
            buildBackup: (pw) async => Uint8List.fromList([1]),
          ),
        ),
      )
      .then((_) => tester.pumpAndSettle());

  Future<void> tapReal(WidgetTester tester, Finder f) =>
      tester.runAsync(() async {
        await tester.ensureVisible(f);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(f);
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await tester.pumpAndSettle();
      });

  Future<void> waitReal(WidgetTester tester, Future<bool> Function() done) =>
      tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 10));
          await Future<void>.delayed(const Duration(milliseconds: 5));
          if (await done()) return;
        }
      });

  testWidgets('enrol: passphrase sheet → key stored, tile shows auto daily', (
    tester,
  ) async {
    await tester.runAsync(() => hub.upsert(_base, password: 'pw'));
    await pumpScreen(tester);

    await tapReal(tester, find.byKey(const Key('dest-nas1')));
    await tapReal(tester, find.byKey(const Key('cloud-auto')));

    await tester.enterText(find.byKey(const Key('passphrase-field')), 'dkey');
    await tester.enterText(
      find.byKey(const Key('passphrase-confirm-field')),
      'dkey',
    );
    await tapReal(tester, find.byKey(const Key('passphrase-next')));
    await waitReal(tester, () async => dest().autoBackup);

    expect(await store.get('cloud-autokey-nas1'), 'dkey'); // §3.3 enrol once
    expect(scheduler.syncs.last, ['nas1']);
    expect(find.textContaining('auto: daily'), findsOneWidget);
    expect(find.byKey(const Key('auto-on-nas1')), findsOneWidget);
  });

  testWidgets('cancel the sheet enrols nothing', (tester) async {
    await tester.runAsync(() => hub.upsert(_base, password: 'pw'));
    await pumpScreen(tester);
    await tapReal(tester, find.byKey(const Key('dest-nas1')));
    await tapReal(tester, find.byKey(const Key('cloud-auto')));
    await tester.tapAt(const Offset(5, 5)); // barrier dismiss → pop(null)
    await tester.pumpAndSettle();
    expect(dest().autoBackup, isFalse);
    expect(await store.get('cloud-autokey-nas1'), isNull);
  });

  testWidgets('switch off deletes the key and stops the schedule', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await hub.upsert(_base, password: 'pw');
      await hub.setBackupKey(_base, 'dkey');
      await hub.upsert(_base.copyWith(autoBackup: true));
    });
    await pumpScreen(tester);
    expect(find.byKey(const Key('auto-on-nas1')), findsOneWidget);

    await tapReal(tester, find.byKey(const Key('dest-nas1')));
    await tapReal(tester, find.byKey(const Key('cloud-auto'))); // off: no sheet
    // Wait for BOTH halves of the off-switch (#51): CI must not adjudicate
    // a race between the flag flip and the key scrub. The lib scrubs before
    // flipping, so this settles as one state change; the contract is
    // "off means off" — no moment where off and key-alive coexist.
    await waitReal(
      tester,
      () async =>
          !dest().autoBackup && (await store.get('cloud-autokey-nas1')) == null,
    );

    expect(await store.get('cloud-autokey-nas1'), isNull); // off means off
    expect(scheduler.syncs.last, isEmpty);
    expect(find.byKey(const Key('auto-on-nas1')), findsNothing);
  });

  testWidgets('three failures render the quiet badge on the tile', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await hub.upsert(_base, password: 'pw');
      await hub.setBackupKey(_base, 'dkey');
      await hub.upsert(
        _base.copyWith(autoBackup: true, autoFails: kAutoFailBadgeAfter),
      );
    });
    await pumpScreen(tester);
    expect(find.byKey(const Key('auto-fail-nas1')), findsOneWidget);
    expect(find.textContaining('failing (3×)'), findsOneWidget);
  });
}
