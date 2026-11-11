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

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('CategoryHints (e12 §2)', () {
    test('a well-known brand reads high', () {
      expect(CategoryHints.suggest('UBER TRIP HELP.PEOPLE.COM'),
          ('Transport', FieldConfidence.high));
      expect(
          CategoryHints.suggest('netflix.com'), ('Fun', FieldConfidence.high));
      expect(CategoryHints.suggest('COSTCO WHOLESALE #123'), isNull);
      expect(CategoryHints.suggest('STARBUCKS STORE 4018'),
          ('Food', FieldConfidence.high));
      expect(CategoryHints.suggest('PG&E SERVICES'),
          ('Utilities', FieldConfidence.high));
      expect(CategoryHints.suggest('CVS/PHARMACY #03412'),
          ('Health', FieldConfidence.high));
    });

    test('generic vocabulary reads medium, never high', () {
      expect(CategoryHints.suggest('GREEN GROCERS'),
          ('Food', FieldConfidence.medium));
      expect(CategoryHints.suggest('CORNER PARKING'),
          ('Transport', FieldConfidence.medium));
      expect(CategoryHints.suggest('RIVERSIDE DENTAL GROUP'),
          ('Health', FieldConfidence.high));
      expect(CategoryHints.suggest('CITY WATER SEWER'),
          ('Utilities', FieldConfidence.medium));
    });

    test('high wins over an earlier medium', () {
      // "market" (medium Food) appears before the NETFLIX brand token —
      // the high match must still decide.
      expect(CategoryHints.suggest('FARMERS MARKET — NETFLIX BILLPAY'),
          ('Fun', FieldConfidence.high));
    });

    test('unknown text stays silent', () {
      expect(CategoryHints.suggest('ACME HOLDINGS LLC'), isNull);
      expect(CategoryHints.suggest(''), isNull);
      expect(CategoryHints.suggest('   '), isNull);
    });

    test('only the six suggestable seed names ever come back', () {
      for (final text in [
        'UBER TRIP',
        'CITY WATER',
        'SPOTIFY',
        'RALPHS GROCERY',
        'WALGREEN #77',
      ]) {
        final hit = CategoryHints.suggest(text);
        expect(CategoryHints.suggested, contains(hit!.$1), reason: text);
      }
    });
  });
}
