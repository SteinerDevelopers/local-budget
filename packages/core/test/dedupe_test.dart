import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  DedupeKey k(int account, String date, int amount) => DedupeKey.of(
      accountId: account,
      date: DateTime.parse(date),
      amountMinor: amount,
      currencyCode: 'USD');

  group('classify', () {
    test('exact duplicate flagged (already in ledger)', () {
      final d = Dedupeer(existing: {k(1, '2026-03-15', 1050)});
      final rows = ['a'];
      final res = d.classify(rows, (r) => k(1, '2026-03-15', 1050));
      expect(res.single.verdict, DedupeVerdict.duplicateExact);
    });

    test('duplicate within the same import batch flagged too', () {
      final d = Dedupeer(existing: {});
      final rows = ['a', 'b'];
      final res = d.classify(rows, (r) => k(1, '2026-03-15', 1050));
      expect(res.map((r) => r.verdict),
          [DedupeVerdict.fresh, DedupeVerdict.duplicateExact]);
    });

    test('same amount ±1 day = suspect (surfaced, not dropped)', () {
      final d = Dedupeer(existing: {k(7, '2026-03-15', 2500)});
      final res = d.classify(['x'], (r) => k(7, '2026-03-16', 2500));
      expect(res.single.verdict, DedupeVerdict.duplicateSuspect);
    });

    test('different amount same day = fresh', () {
      final d = Dedupeer(existing: {k(1, '2026-03-15', 1050)});
      final res = d.classify(['x'], (r) => k(1, '2026-03-15', 1051));
      expect(res.single.verdict, DedupeVerdict.fresh);
    });

    test('different account same key = fresh', () {
      final d = Dedupeer(existing: {k(1, '2026-03-15', 1050)});
      final res = d.classify(['x'], (r) => k(2, '2026-03-15', 1050));
      expect(res.single.verdict, DedupeVerdict.fresh);
    });

    test('suspect window 0 disables proximity', () {
      final d =
          Dedupeer(existing: {k(7, '2026-03-15', 2500)}, suspectDayWindow: 0);
      final res = d.classify(['x'], (r) => k(7, '2026-03-16', 2500));
      expect(res.single.verdict, DedupeVerdict.fresh);
    });
  });
}
