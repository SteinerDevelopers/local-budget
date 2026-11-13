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

import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/ledger/view_models.dart';
import 'package:local_budget/features/quickadd/quick_add_draft.dart';

void main() {
  group('QuickAddDraft codec (ruling 2)', () {
    test('round trip preserves every field', () {
      final d = QuickAddDraft(
        amount: '12.3',
        currencyCode: 'EUR',
        kind: EntryKind.income,
        categoryId: 7,
        day: DateTime(2026, 11, 9),
        note: 'semi  typed',
      );
      final back = QuickAddDraft.decode(d.encode())!;
      expect(back.amount, '12.3');
      expect(back.currencyCode, 'EUR');
      expect(back.kind, EntryKind.income);
      expect(back.categoryId, 7);
      expect(back.day, DateTime(2026, 11, 9));
      expect(back.note, 'semi  typed');
    });

    test('day is a stable yyyy-MM-dd (local, no clock drift)', () {
      final d = QuickAddDraft(
        amount: '1',
        currencyCode: 'USD',
        kind: EntryKind.expense,
        day: DateTime(2026, 1, 2),
      );
      expect(d.encode(), contains('"day":"2026-01-02"'));
      expect(QuickAddDraft.decode(d.encode())!.day, DateTime(2026, 1, 2));
    });

    test('null/empty/damaged input decodes to null, never throws', () {
      expect(QuickAddDraft.decode(null), isNull);
      expect(QuickAddDraft.decode(''), isNull);
      expect(QuickAddDraft.decode('not json'), isNull);
      expect(QuickAddDraft.decode('[1,2]'), isNull);
      expect(QuickAddDraft.decode('{"amount":42}'), isNull);
      expect(QuickAddDraft.decode('{"amount":"1"}'), isNull); // no currency
      // Unknown/missing kind or category degrade, not die:
      final ok = QuickAddDraft.decode(
        '{"amount":"1","currency":"USD","day":"2026-11-10"}',
      )!;
      expect(ok.kind, EntryKind.expense);
      expect(ok.categoryId, isNull);
    });

    test('hasContent is the restore gate', () {
      QuickAddDraft d(String amount, {String note = ''}) => QuickAddDraft(
        amount: amount,
        currencyCode: 'USD',
        kind: EntryKind.expense,
        day: DateTime(2026, 11, 10),
        note: note,
      );
      expect(d('').hasContent, isFalse);
      expect(d('', note: '   ').hasContent, isFalse);
      expect(d('0.').hasContent, isTrue); // mid-typed counts
      expect(d('', note: 'x').hasContent, isTrue);
    });
  });
}
