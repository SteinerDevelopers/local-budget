// E7b §3.2 — the object-name grammar is the identity of a cloud backup:
// write, parse and filter must stay exact inverses.
import 'package:data/cloud/cloud.dart';
import 'package:test/test.dart';

void main() {
  group('profileSlug', () {
    test('folds case, spaces and runs of symbols to single dashes', () {
      expect(profileSlug('Kitchen NAS'), 'kitchen-nas');
      expect(profileSlug('  Home -- Box!! '), 'home-box');
      expect(profileSlug('Zürich²'), 'z-rich');
    });
    test('empty or symbol-only falls back to default', () {
      expect(profileSlug(''), 'default');
      expect(profileSlug('?!~'), 'default');
    });
    test('already-clean slugs pass through', () {
      expect(profileSlug('nas-2'), 'nas-2');
    });
  });

  group('backupObjectName', () {
    test('pinned UTC minute stamp', () {
      expect(
        backupObjectName(
          profileName: 'Kitchen NAS',
          now: DateTime.utc(2026, 3, 9, 7, 5),
        ),
        'localbudget-kitchen-nas-20260309-0705.lzbak',
      );
    });
    test('local time converts to UTC before stamping', () {
      // 2026-03-09 02:05 in UTC+3 → same UTC minute as the case above.
      final name = backupObjectName(
        profileName: 'Kitchen NAS',
        now: DateTime.utc(2026, 3, 9, 7, 5).toLocal(),
      );
      expect(isBackupObject(name), isTrue);
    });
  });

  group('parse/filter round-trip', () {
    test('own names parse back to the upload minute', () {
      final t = DateTime.utc(2025, 12, 28, 23, 59);
      final name = backupObjectName(profileName: 'NAS', now: t);
      expect(isBackupObject(name), isTrue);
      expect(parseBackupObjectTime(name), t);
    });
    test('foreign files are never ours', () {
      expect(isBackupObject('holiday.jpg'), isFalse);
      expect(isBackupObject('localbudget-nas-20260309-0705.zip'), isFalse);
      expect(parseBackupObjectTime('notes.txt'), isNull);
    });
    test('impossible dates do not normalize into a real minute', () {
      expect(
        parseBackupObjectTime('localbudget-x-20260231-0100.lzbak'),
        isNull,
      );
      expect(
        parseBackupObjectTime('localbudget-x-20261301-0100.lzbak'),
        isNull,
      );
      expect(
        parseBackupObjectTime('localbudget-x-20260309-2461.lzbak'),
        isNull,
      );
    });
    test('slug with dashes parses time from the fixed tail', () {
      final name = 'localbudget-kitchen-nas-20260309-0705.lzbak';
      expect(parseBackupObjectTime(name), DateTime.utc(2026, 3, 9, 7, 5));
    });
  });
}
