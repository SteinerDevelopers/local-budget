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

import 'package:capture/capture.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

final usd = Currency.resolve('USD');
final eur = Currency.resolve('EUR');

const high = FieldConfidence.high;
const med = FieldConfidence.medium;
const low = FieldConfidence.low;

void main() {
  group('fill-only merge (e2-capture.md §3)', () {
    test('null llm → base returned unchanged', () {
      final base = ReceiptDraft(merchant: 'A', merchantConfidence: med);
      expect(mergeDraft(base, null), same(base));
    });

    test('null field is filled at the structurer confidence', () {
      final base = ReceiptDraft(total: null);
      final llm = ReceiptDraft(total: Money(500, usd), totalConfidence: med);
      final m = mergeDraft(base, llm);
      expect(m.total!.minorUnits, 500);
      expect(m.totalConfidence, med);
      expect(m.usedLlm, true);
    });

    test('low-confidence value is replaced; medium is never overwritten', () {
      final base = ReceiptDraft(
        merchant: 'OCR GROCER',
        merchantConfidence: low,
        date: DateTime(2026, 3, 15),
        dateConfidence: high,
        total: Money(999, usd),
        totalConfidence: med,
      );
      final llm = ReceiptDraft(
        merchant: 'GREEN GROCERS',
        merchantConfidence: med,
        date: DateTime(2025, 1, 1),
        dateConfidence: high,
        total: Money(111, eur),
        totalConfidence: high,
      );
      final m = mergeDraft(base, llm);
      expect(m.merchant, 'GREEN GROCERS'); // low → filled
      expect(m.date, DateTime(2026, 3, 15)); // high → untouched
      expect(m.total!.minorUnits, 999); // medium → untouched
      expect(m.total!.currency.code, 'USD');
    });

    test('user-edited fields are untouchable, even when null+low', () {
      final base = ReceiptDraft(merchant: null, merchantConfidence: low);
      final llm = ReceiptDraft(merchant: 'GUESS', merchantConfidence: high);
      final m = mergeDraft(
        base,
        llm,
        userEdited: {DraftField.merchant},
      );
      expect(m.merchant, isNull);
      expect(m.usedLlm, false); // nothing actually filled
    });

    test('ambiguity flag follows the filling structurer value', () {
      final base = ReceiptDraft(
          date: DateTime(2026, 3, 4),
          dateConfidence: low,
          dateIsAmbiguous: true);
      final llm = ReceiptDraft(
          date: DateTime(2026, 4, 3),
          dateConfidence: med,
          dateIsAmbiguous: false);
      final m = mergeDraft(base, llm);
      expect(m.date, DateTime(2026, 4, 3));
      expect(m.dateIsAmbiguous, false);
    });

    test('llm adds nothing new → same draft, usedLlm false', () {
      final base = ReceiptDraft(
        merchant: 'A',
        merchantConfidence: high,
        date: DateTime(2026, 1, 1),
        dateConfidence: high,
        total: Money(1, usd),
        totalConfidence: high,
      );
      final llm = ReceiptDraft(
        merchant: 'B',
        merchantConfidence: high,
        total: Money(2, usd),
        totalConfidence: high,
      );
      final m = mergeDraft(base, llm);
      expect(m.merchant, 'A');
      expect(m.usedLlm, false);
      expect(identical(m, base), isTrue);
    });

    test('rawLines always survive the merge', () {
      final base = ReceiptDraft(rawLines: const ['L1', 'L2']);
      final m = mergeDraft(
          base, ReceiptDraft(total: Money(7, usd), totalConfidence: low));
      expect(m.rawLines, ['L1', 'L2']);
    });
  });
}
