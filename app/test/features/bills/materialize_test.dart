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

// #36 — the app-open materialization pass (design e3 §3.4) against the
// real repository: as-if-manual inserts, one occurrence per rule per pass,
// oldest first, day-gated and race-gated idempotency, and the >365-day
// "paused?" split. Engine ordering itself is covered in packages/budget.
import 'dart:ffi' show DynamicLibrary;

import 'package:core/core.dart' show TransactionSource;
import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/bills/bills_service.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final now = DateTime.now();
  final noon = DateTime(now.year, now.month, now.day, 12);
  DateTime back(int days) => DateTime(now.year, now.month, now.day - days);

  ({AppDatabase db, LedgerRepository repo}) freshRepo() {
    final db = AppDatabase.inMemory();
    return (db: db, repo: LedgerRepository(db));
  }

  Future<int> seedWeekly(
    LedgerRepository repo, {
    required String name,
    required DateTime due,
    int amountMinor = 4500,
  }) => repo.addRule(
    name: name,
    amountMinor: amountMinor,
    currencyCode: 'USD',
    frequency: 'weekly',
    start: DateTime(due.year, due.month, due.day - 14),
    nextDue: due,
    dayOfWeek: due.weekday,
    notify: false,
  );

  Future<List<({String? note, int days, int amount, TransactionSource src})>>
  txsInRange(LedgerRepository repo) async {
    final rows = await repo.transactionsInRange(
      epochDayOf(now) - 420,
      epochDayOf(now) + 7,
    );
    return [
      for (final t in rows)
        (note: t.note, days: t.dateDays, amount: t.amountMinor, src: t.source),
    ];
  }

  group('Lazy materialization at app open (#36, §3.4)', () {
    test('overdue rule inserts as-if-manual and advances the cursor', () async {
      final (:db, :repo) = freshRepo();
      final id = await seedWeekly(repo, name: 'Wifi', due: back(1));
      final outcome = await materializeDueBills(repo, now: noon);

      expect(outcome.skipped, isFalse);
      expect(outcome.insertedRuleIds, [id]);
      final tx = (await txsInRange(
        repo,
      )).singleWhere((t) => t.note == 'Bill: Wifi');
      expect(tx.amount, 4500);
      expect(tx.days, epochDayOf(back(1))); // back-dated to its own day
      expect(tx.src, TransactionSource.manual); // as if typed (§3.4)

      final r = (await repo.rules()).single;
      expect(
        dayFromEpoch(r.nextDueMs ~/ 86400000),
        back(1).add(const Duration(days: 7)),
      );
      expect(await repo.billsLastMaterializeMs(), isNotNull);
      await db.close();
    });

    test('missed weeks materialize ONE per pass, oldest first', () async {
      final (:db, :repo) = freshRepo();
      final a = await seedWeekly(repo, name: 'A', due: back(21));
      final b = await seedWeekly(
        repo,
        name: 'B',
        due: back(21),
        amountMinor: 800,
      );
      final first = await materializeDueBills(repo, now: noon);
      expect(first.insertedRuleIds, [a, b]); // due-date tie → ruleId order

      var all = await txsInRange(repo);
      expect(all.where((t) => t.note != null).length, 2);
      // Cursors moved exactly one step — no backfill dump of 3 occurrences.
      for (final r in await repo.rules()) {
        expect(dayFromEpoch(r.nextDueMs ~/ 86400000), back(14));
      }

      // Same calendar day: rapid resumes replay nothing.
      final again = await materializeDueBills(repo, now: noon);
      expect(again.skipped, isTrue);
      all = await txsInRange(repo);
      expect(all.where((t) => t.note != null).length, 2);

      // Next day opens: the second missed occurrence lands, still one each.
      await repo.setBillsLastMaterializeMs(back(1).millisecondsSinceEpoch);
      final nextDay = await materializeDueBills(repo, now: noon);
      expect(nextDay.insertedRuleIds, [a, b]);
      all = await txsInRange(repo);
      expect(all.where((t) => t.note != null).length, 4);
      for (final r in await repo.rules()) {
        expect(dayFromEpoch(r.nextDueMs ~/ 86400000), back(7));
      }
      await db.close();
    });

    test('concurrent resumes race exactly one pass', () async {
      final (:db, :repo) = freshRepo();
      await seedWeekly(repo, name: 'Wifi', due: back(1));
      final results = await Future.wait([
        materializeDueBills(repo, now: noon),
        materializeDueBills(repo, now: noon),
      ]);
      expect(results.where((o) => o.skipped), hasLength(1));
      expect(results.where((o) => !o.skipped), hasLength(1));
      final all = await txsInRange(repo);
      expect(all.where((t) => t.note == 'Bill: Wifi'), hasLength(1));
      await db.close();
    });

    test('>365-day gaps surface as "paused?", never insert', () async {
      final (:db, :repo) = freshRepo();
      final id = await seedWeekly(repo, name: 'Dormant', due: back(400));
      final outcome = await materializeDueBills(repo, now: noon);

      expect(outcome.pausedRuleIds, [id]);
      expect(outcome.insertedRuleIds, isEmpty);
      expect(await txsInRange(repo), isEmpty);
      // The cursor stays where it was — answering "paused?" is the user's.
      final r = (await repo.rules()).single;
      expect(dayFromEpoch(r.nextDueMs ~/ 86400000), back(400));

      // resumeBill: first occurrence on or after today, rule kept.
      final line = (await loadBillLines(repo, now: noon)).single;
      expect(line.isStale, isTrue);
      await resumeBill(repo, line, now: noon);
      final resumed = (await repo.rules()).single;
      final dueEpoch = resumed.nextDueMs ~/ 86400000;
      expect(dueEpoch, greaterThanOrEqualTo(epochDayOf(noon)));
      expect(dueEpoch, lessThanOrEqualTo(epochDayOf(noon) + 6));

      // pauseBill: archived away, nothing deleted, off the list.
      await pauseBill(repo, (await loadBillLines(repo, now: noon)).single);
      expect(await repo.rules(), isEmpty);
      final archived = (await repo.rules(includeArchived: true)).single;
      expect(archived.archived, isTrue);
      await db.close();
    });

    test('future rules are left alone; the day is still marked', () async {
      final (:db, :repo) = freshRepo();
      await seedWeekly(
        repo,
        name: 'Rent',
        due: DateTime(now.year, now.month, now.day + 10),
      );
      final outcome = await materializeDueBills(repo, now: noon);
      expect(outcome.skipped, isFalse);
      expect(outcome.insertedRuleIds, isEmpty);
      expect(await txsInRange(repo), isEmpty);
      // Second call same day: skipped by the day gate, not the empty plan.
      final second = await materializeDueBills(repo, now: noon);
      expect(second.skipped, isTrue);
      await db.close();
    });
  });
}
