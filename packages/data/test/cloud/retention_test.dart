// E7b §3.2 — "keep the newest 12, collapse older ones to the newest per
// calendar day"; foreign objects and the fresh upload are untouchable.
import 'package:data/cloud/cloud.dart';
import 'package:test/test.dart';

CloudObject bak(String name, {int? size}) => CloudObject(
  name: name,
  path: 'bk/$name',
  size: size ?? 100,
  modified: parseBackupObjectTime(name) ?? DateTime.utc(1970),
);

CloudObject foreign(String name) => CloudObject(
  name: name,
  path: 'bk/$name',
  size: 7,
  modified: DateTime.utc(2026, 1, 1),
);

String old(int day, int minute) => backupObjectName(
  profileName: 'NAS',
  now: DateTime.utc(2026, 10, day, 9, minute),
);

void main() {
  test('12 or fewer: nothing to prune', () {
    final all = List.generate(12, (i) => bak(old(1, i)));
    final plan = prunePlan(all);
    expect(plan.delete, isEmpty);
    expect(plan.keep.length, 12);
  });

  test('newest 12 always survive, whatever the day pattern', () {
    final all = [
      for (var m = 0; m < 15; m++) bak(old(5, m)), // one day, 15 deep
    ];
    final plan = prunePlan(all);
    expect(plan.keep.length, 12); // the day is already in the window
    expect(plan.delete.length, 3);
    // The deleted ones are exactly the three OLDEST of the day,
    // newest-first iteration order.
    expect(plan.delete.map((o) => o.name).toList(), [
      old(5, 2),
      old(5, 1),
      old(5, 0),
    ]);
  });

  test('older entries collapse to one survivor per UTC day', () {
    final all = [
      bak(old(1, 10)), bak(old(1, 20)), bak(old(1, 30)), // Oct 1 — 3 candidates
      bak(old(2, 10)), // Oct 2 — clean
    ];
    final plan = prunePlan(all, newestToKeep: 1);
    // keep: Oct2 newest; Oct1 ×2 deleted after the day's survivor... day 1
    // has 3 entries: newest-of-day survives, two go.
    expect(plan.keep.map((o) => o.name), [old(2, 10), old(1, 30)]);
    expect(plan.delete.map((o) => o.name), [old(1, 20), old(1, 10)]);
  });

  test('foreign objects are never prune candidates', () {
    final all = [
      foreign('holiday.jpg'),
      foreign('readme.txt'),
      for (var m = 0; m < 14; m++) bak(old(3, m)),
    ];
    final plan = prunePlan(all);
    expect(plan.delete.every((o) => isBackupObject(o.name)), isTrue);
    expect(
      plan.keep.map((o) => o.name),
      containsAll(['holiday.jpg', 'readme.txt']),
    );
  });

  test('name grammar beats a lying LastModified for ordering', () {
    final honest = CloudObject(
      name: old(9, 0),
      path: 'bk/x',
      size: 1,
      modified: DateTime.utc(1999), // server clock lost
    );
    final liarLate = CloudObject(
      name: old(1, 20),
      path: 'bk/y',
      size: 1,
      modified: DateTime.utc(2031), // future-dated server
    );
    final liarEarly = CloudObject(
      name: old(1, 10),
      path: 'bk/z',
      size: 1,
      modified: DateTime.utc(2030),
    );
    // LastModified-sorted, liarLate would win the single window slot;
    // name grammar keeps the true newest and collapses the Oct-1 pair.
    final plan = prunePlan([honest, liarLate, liarEarly], newestToKeep: 1);
    expect(plan.keep.first.name, old(9, 0));
    expect(plan.delete.single.name, old(1, 10));
  });
}
