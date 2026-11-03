// E7 §2 — AnalyticsService over a real in-memory repo, plus the range
// presets and labels the Insights header leans on. Deliberately
// flavor-neutral: this file runs in the FREE CI suite (E7 §6 — the math is
// not the paid part; only its surfacing is), so it must pass under the
// default define and under APP_FLAVOR=pro alike.
import 'dart:ffi';

import 'package:budget/budget.dart' show DayRange, dayOf;
import 'package:core/core.dart' show Currency, Money, TransactionSource;
import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/analytics/analytics_service.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;

void main() {
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final usd = Currency.resolve('USD');
  // A fixed civil "today": 2026 is not a leap year, so Feb is 28 and the
  // preset day-counts below are constants.
  final today = DateTime(2026, 3, 15);

  ({AppDatabase db, LedgerRepository repo}) freshRepo() {
    final db = AppDatabase.inMemory();
    return (db: db, repo: LedgerRepository(db));
  }

  Future<void> spend(
    LedgerRepository repo, {
    required int catId,
    required DateTime date,
    required int minor,
    String? merchant,
    bool isIncome = false,
  }) async {
    final acc = await repo.defaultAccount();
    await repo.addTransaction(
      accountId: acc.id,
      date: date,
      amount: Money(minor, usd),
      source: TransactionSource.manual,
      categoryId: catId,
      merchant: merchant,
      isIncome: isIncome,
    );
  }

  group('presets', () {
    test('day windows match their names', () {
      final m = dayRangeFor(RangePreset.thisMonth, today: today);
      expect(m.startDay, dayOf(DateTime.utc(2026, 3)));
      expect(m.endDay, dayOf(DateTime.utc(2026, 4)));
      expect(m.lengthDays, 31);

      final lm = dayRangeFor(RangePreset.lastMonth, today: today);
      expect(lm.startDay, dayOf(DateTime.utc(2026, 2)));
      expect(lm.lengthDays, 28); // 2026: no leap day.

      final y = dayRangeFor(RangePreset.thisYear, today: today);
      expect(y.startDay, dayOf(DateTime.utc(2026)));
      expect(y.lengthDays, 365);

      final ly = dayRangeFor(RangePreset.lastYear, today: today);
      expect(ly.startDay, dayOf(DateTime.utc(2025)));
      expect(ly.endDay, dayOf(DateTime.utc(2026)));
    });

    test('labels stay compact and unambiguous', () {
      expect(
        formatRangeLabel(dayRangeFor(RangePreset.thisMonth, today: today)),
        'Mar 2026',
      );
      expect(
        formatRangeLabel(dayRangeFor(RangePreset.thisYear, today: today)),
        '2026',
      );
      final week = DayRange(
        startDay: dayOf(DateTime.utc(2026, 3, 3)),
        endDay: dayOf(DateTime.utc(2026, 3, 10)),
      );
      expect(formatRangeLabel(week), 'Mar 3 – Mar 9, 2026');
      final across = DayRange(
        startDay: dayOf(DateTime.utc(2025, 12, 28)),
        endDay: dayOf(DateTime.utc(2026, 1, 3)),
      );
      expect(formatRangeLabel(across), 'Dec 28, 2025 – Jan 2, 2026');
    });
  });

  group('load', () {
    test('delta compares against the shifted-back year', () async {
      final r = freshRepo();
      addTearDown(r.db.close);
      final food = await r.repo.addCategory('Food');
      // Mar 2026 spends 30.00 total; Mar 2025 spends 25.00.
      await spend(
        r.repo,
        catId: food,
        date: DateTime(2026, 3, 5),
        minor: 2510,
      );
      await spend(
        r.repo,
        catId: food,
        date: DateTime(2026, 3, 7),
        minor: 490,
        merchant: 'Coffee',
      );
      await spend(
        r.repo,
        catId: food,
        date: DateTime(2025, 3, 6),
        minor: 2500,
      );
      final svc = AnalyticsService(r.repo);
      final rep = await svc.load(
        range: dayRangeFor(RangePreset.thisMonth, today: today),
        compare: dayRangeFor(
          RangePreset.thisMonth,
          today: today,
        ).shiftedBackYear(),
      );
      expect(rep.totals.spentMinor, 3000);
      expect(rep.delta!.deltaBp, 2000); // +20.0%, equal 31-day spans.
      expect(rep.delta!.baseDays, 31);
      expect(rep.delta!.compareDays, 31);
      expect(rep.buckets.single.yearMonth, '2026-03');
      expect(rep.buckets.single.spentMinor, 3000);
      expect(rep.compareBuckets.single.yearMonth, '2025-03');
      expect(rep.compareBuckets.single.spentMinor, 2500);
      expect(rep.currency, usd);
      expect(rep.categories.map((c) => c.name), contains('Food'));
    });

    test('income never lands in spentMinor', () async {
      final r = freshRepo();
      addTearDown(r.db.close);
      final food = await r.repo.addCategory('Food');
      final pay = await r.repo.addCategory('Pay', isIncome: true);
      await spend(
        r.repo,
        catId: food,
        date: DateTime(2026, 3, 5),
        minor: 3000,
      );
      await spend(
        r.repo,
        catId: pay,
        date: DateTime(2026, 3, 1),
        minor: 9999,
        isIncome: true,
      );
      final rep = await AnalyticsService(
        r.repo,
      ).load(range: dayRangeFor(RangePreset.thisMonth, today: today));
      expect(rep.totals.spentMinor, 3000);
      expect(rep.totals.incomeMinor, 9999);
      // No compare asked, no comparison invented (§2.1).
      expect(rep.delta, isNull);
      expect(rep.compareBuckets, isEmpty);
    });

    test('the detector rides through to the report', () async {
      final r = freshRepo();
      addTearDown(r.db.close);
      final food = await r.repo.addCategory('Food');
      // Three monthly hits: Jan 10 → Feb 7 → Mar 7 (28-day gaps, inside
      // the 27–33 band) around 5.00.
      await spend(
        r.repo,
        catId: food,
        date: DateTime(2026, 1, 10),
        minor: 500,
        merchant: 'Coffee',
      );
      await spend(
        r.repo,
        catId: food,
        date: DateTime(2026, 2, 7),
        minor: 510,
        merchant: 'Coffee',
      );
      await spend(
        r.repo,
        catId: food,
        date: DateTime(2026, 3, 7),
        minor: 490,
        merchant: 'Coffee',
      );
      final rep = await AnalyticsService(
        r.repo,
      ).load(range: dayRangeFor(RangePreset.thisYear, today: today));
      final s = rep.suggestions.single;
      expect(s.merchantName, 'Coffee');
      expect(s.hits, 3);
      expect(s.amountAvgMinor, 500);
    });
  });
}
