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

void main() {
  group('structurerPrompt', () {
    test('names the three keys and quotes the OCR lines', () {
      final p = structurerPrompt(['ACME MART', 'TOTAL 4.20', '']);
      expect(p, contains('"amountCents"'));
      expect(p, contains('ACME MART'));
      expect(p, contains('TOTAL 4.20'));
      // Empty line is a page boundary: nothing after it belongs to page 1.
      expect(p, isNot(contains('SECOND PAGE')));
    });

    test('caps the OCR block and says so', () {
      final lines = List.filled(400, 'x' * 40);
      final p = structurerPrompt(lines);
      expect(p, contains('(truncated)'));
      expect(p.length, lessThan(2600));
    });
  });

  group('parseStructurerJson', () {
    test('accepts a clean object and fills every field at low', () {
      final d = parseStructurerJson(
        '{"merchant":"Aldi","date":"2026-10-05","amountCents":2349}',
        currency: usd,
      );
      expect(d, isNotNull);
      expect(d!.merchant, 'Aldi');
      expect(d.date, DateTime.parse('2026-10-05'));
      expect(d.total, Money(2349, usd));
      // A structurer never claims confidence (decision 10).
      expect(d.merchantConfidence, FieldConfidence.low);
      expect(d.dateConfidence, FieldConfidence.low);
      expect(d.totalConfidence, FieldConfidence.low);
      expect(d.usedLlm, isFalse); // merge, not the parser, sets metadata
    });

    test('survives markdown fences and surrounding prose', () {
      const raw = 'Here you go:\n```json\n{"merchant":"Lidl"}\n```\nEnjoy!';
      expect(parseStructurerJson(raw, currency: usd)!.merchant, 'Lidl');
    });

    test('unknowns are null, not errors; all-null means nothing structured',
        () {
      final d = parseStructurerJson(
        '{"merchant":null,"date":null,"amountCents":null}',
        currency: usd,
      );
      expect(d, isNull);
    });

    test('garbage, prose and broken JSON yield null', () {
      for (final raw in ['', 'ALDI 2026 4.20', '{oops', '{"a":[1,}', '[]']) {
        expect(parseStructurerJson(raw, currency: usd), isNull, reason: raw);
      }
    });

    test('dates are strict ISO; slop is dropped', () {
      final d = parseStructurerJson(
        '{"date":"05/10/2026","merchant":"A"}',
        currency: usd,
      );
      expect(d!.date, isNull); // would be an invented date
      expect(d.merchant, 'A');
    });

    test('amounts: whole numbers only, ints or integer-valued numerics', () {
      // Fractional cents and unparsable strings reject the only field, so
      // nothing was structured - the honest answer is null.
      expect(
          parseStructurerJson('{"amountCents":12.49}', currency: usd), isNull);
      expect(
        parseStructurerJson('{"amountCents":"1249"}', currency: usd)!.total,
        Money(1249, usd),
      );
      expect(
        parseStructurerJson('{"amountCents":-350}', currency: usd)!.total,
        Money(-350, usd), // refunds exist
      );
      expect(
        parseStructurerJson('{"amountCents":"EUR 12.49"}', currency: usd),
        isNull,
      );
    });

    test('currency comes from the caller, never the model', () {
      final d = parseStructurerJson(
        '{"amountCents":500}',
        currency: eur,
      );
      expect(d!.total!.currency.code, 'EUR');
    });

    test('rambling merchant answers are truncated, not trusted', () {
      final d = parseStructurerJson(
        '{"merchant":"${"M" * 400}"}',
        currency: usd,
      );
      expect(d!.merchant!.length, 120);
    });

    test('ambiguity flag is honoured only alongside a date', () {
      final d = parseStructurerJson(
        '{"merchant":"A","dateIsAmbiguous":true}',
        currency: usd,
      );
      expect(d!.dateIsAmbiguous, isFalse);
      final e = parseStructurerJson(
        '{"date":"2026-04-03","dateIsAmbiguous":true}',
        currency: usd,
      );
      expect(e!.dateIsAmbiguous, isTrue);
    });
  });
}
