import 'package:core/core.dart';
import 'package:test/test.dart';

/// E11 bill-route groundwork (e11-document-import.md §4): the due-date and
/// frequency vocabulary a photographed bill carries, plus the statement
/// period-end fallback. Everything is pinned against a frozen clock.
void main() {
  final usd = Currency.known['USD']!;
  final now = DateTime.utc(2026, 11, 4);

  group('guessDueDate', () {
    test('due vocabulary on the line yields a high-confidence date', () {
      final r = BillDraft.guessDueDate(
        ['ACME POWER', 'DUE DATE 11/15/2026', 'TOTAL 84.00'],
        now: now,
      );
      expect(r, isNotNull);
      expect(r!.date, DateTime.utc(2026, 11, 15));
      expect(r.confidence, FieldConfidence.high);
    });

    test('month-name spellings parse', () {
      final r = BillDraft.guessDueDate(['PAY BY NOV 15, 2026'], now: now);
      expect(r?.date, DateTime.utc(2026, 11, 15));
    });

    test('OCR-split value on the next line reads medium', () {
      final r = BillDraft.guessDueDate(
        ['ACME POWER UTILITIES', 'DUE DATE', '11/15/2026'],
        now: now,
      );
      expect(r?.date, DateTime.utc(2026, 11, 15));
      expect(r?.confidence, FieldConfidence.medium);
    });

    test('the last date on the line is the operative one', () {
      // `BILLING PERIOD 10/01/2026 - 10/31/2026` must float from the END.
      final r = BillDraft.guessDueDate(
        ['STATEMENT PERIOD 10/01/2026 - 10/31/2026'],
        now: now,
      );
      expect(r?.date, DateTime.utc(2026, 11, 21)); // 10/31 + 21d float
      expect(r?.confidence, FieldConfidence.low);
    });

    test('dates outside the short-cycle window are refused', () {
      // now + ~198 d: nobody bills that far ahead.
      expect(BillDraft.guessDueDate(['DUE DATE 05/21/2027'], now: now), isNull);
      // now − 38 d: last month's bill, not a bill to draft.
      expect(BillDraft.guessDueDate(['DUE DATE 09/27/2026'], now: now), isNull);
    });

    test('a bill due three days ago is still draftable', () {
      // Day-first reading: 01/11 = the 1st of November.
      final r = BillDraft.guessDueDate(['DUE DATE 01/11/2026'], now: now);
      expect(r?.date, DateTime.utc(2026, 11, 1));
    });

    test('year-less period end borrows the year and floats', () {
      final r = BillDraft.guessDueDate(['PERIOD END 12/31'], now: now);
      expect(r?.date, DateTime.utc(2027, 1, 21));
      expect(r?.confidence, FieldConfidence.low);
    });

    test('period float landing out of window refuses the fallback', () {
      // End 88 d out: inside the due window, but outside the 60-day
      // proximity belt the period fallback trusts its float against.
      expect(
        BillDraft.guessDueDate(['BILLING PERIOD 01/01/2027 - 01/31/2027'],
            now: now),
        isNull,
      );
    });
  });

  group('_guessFrequency (through the draft)', () {
    (BillFrequencyHint, FieldConfidence) freq(List<String> lines) {
      final d = BillDraft.draft(lines, currency: usd, now: now);
      return (d.frequency, d.frequencyConfidence);
    }

    test('monthly vocabulary is high', () {
      expect(freq(['BILLING CYCLE: MONTHLY']),
          (BillFrequencyHint.monthly, FieldConfidence.high));
    });

    test('annual wording reads yearly', () {
      expect(freq(['ANNUAL SERVICE FEE']),
          (BillFrequencyHint.yearly, FieldConfidence.high));
    });

    test('quarterly degrades to monthly at medium, never a fake frequency', () {
      expect(freq(['QUARTERLY INSTALLMENT']),
          (BillFrequencyHint.monthly, FieldConfidence.medium));
    });

    test('weekly reads weekly', () {
      expect(freq(['WEEKLY DELIVERY']),
          (BillFrequencyHint.weekly, FieldConfidence.high));
    });

    test('no vocabulary leaves monthly at low', () {
      expect(freq(['ACME POWER', 'TOTAL 40.00']),
          (BillFrequencyHint.monthly, FieldConfidence.low));
    });
  });

  group('BillDraft.draft', () {
    test('a full bill wires payee, amount, due date and frequency', () {
      final d = BillDraft.draft(
        [
          'CITY WATER & SEWER',
          'DUE DATE 11/15/2026',
          'BILLING CYCLE: MONTHLY',
          'TOTAL AMOUNT DUE 84.00',
        ],
        currency: usd,
        now: now,
      );
      expect(d.isEmpty, isFalse);
      expect(d.payee?.toLowerCase(), contains('water'));
      expect(d.amountDue?.minorUnits, 8400);
      expect(d.dueDate, DateTime.utc(2026, 11, 15));
      expect(d.dueDateConfidence, FieldConfidence.high);
      expect(d.frequency, BillFrequencyHint.monthly);
      expect(d.frequencyConfidence, FieldConfidence.high);
    });

    test('an unrecognisable page drafts empty', () {
      final d = BillDraft.draft(
        ['~~~~~~~~', '----'],
        currency: usd,
        now: now,
      );
      expect(d.isEmpty, isTrue);
    });
  });
}
