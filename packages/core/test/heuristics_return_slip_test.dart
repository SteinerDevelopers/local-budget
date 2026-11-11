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

// Device feedback 2026-11-04, photos 20261104_031719/_031728: a Vera Bradley
// RETURN captured no total. Return slips print every amount accounting-
// negative — `TOTAL AMOUNT:  (215.60)` — and the old `_bestAmount` dropped
// any token that failed `isPositive`, so the anchor line yielded nothing.
// The magnitude is the number the user wants; the sign (charge vs credit)
// is theirs to confirm, so a negative token resolves to its absolute value
// demoted one confidence level.
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 11, 4);
  final usd = Currency.resolve('USD');
  ReceiptHeuristics h() => ReceiptHeuristics(currency: usd, now: now);

  test('card slip: TOTAL AMOUNT: (215.60) -> magnitude, demoted', () {
    // Verbatim printed lines of photo 20261104_031728.
    final r = h().guessTotal([
      'vera bradley',
      'The Summit',
      '214 Summit Boulevard',
      'Birmingham, AL 35243-3179',
      'USA',
      'Return',
      'VISA',
      'Broker: Dynamics 365 Payment Connector for Adyen',
      'Date: 12/27/2024 Time: 17:11',
      '************************1',
      'TOTAL AMOUNT:              (215.60)',
      'Refunded to the above card',
      '000801:15',
      'EFT Store nr.: 000801    EFT Terminal nr.: 000801',
      'Sequence nr:             Authorization code:',
      "Card holder's copy",
    ]);
    expect(r?.amount.minorUnits, 21560);
    expect(r?.confidence, FieldConfidence.low);
  });

  test('itemised return: bottom-up finds "Total (215.60)", not an item price',
      () {
    // Verbatim printed lines of photo 20261104_031719.
    final r = h().guessTotal([
      'vera bradley',
      'The Summit',
      '214 Summit Boulevard',
      'Birmingham AL 35243',
      '(205)977-7840',
      'Transact 0008-000801-163925',
      'Receipt 00080008015001128',
      'Date.: 12/27/2024 Time.: 05:11 PM',
      'Employe : 28554',
      'Customer Info',
      'Kirya Lessman              1015506505',
      'ITEM            QTY    PRICE     TOTAL',
      'Hathaway Tote : Trilli  -1   180.00   (126.00)',
      'Trillium',
      '50389-20070',
      'SALE 30% OFF                      54.00',
      "Baird Hipster : She's  -1    70.00    (70.00)",
      "She's So Good",
      '51846-21213',
      'Subtotal                         (196.00)',
      'Total tax                         (19.60)',
      'Total                            (215.60)',
      'Charge back (Credit Card)        (215.60)',
      '0 0 0 8 0 0 8 0 1 5 0 0 1 1 2 8',
    ]);
    expect(r?.amount.minorUnits, 21560);
    expect(r?.confidence, FieldConfidence.low);
  });

  test('minus-sign form: TOTAL AMOUNT: -215.60', () {
    final r = h().guessTotal(['SUBTOTAL 196.00', 'TOTAL AMOUNT: -215.60']);
    expect(r?.amount.minorUnits, 21560);
    expect(r?.confidence, FieldConfidence.low);
  });

  test('column header alone must not look down into item prices', () {
    // The header line is an anchor with no amount of its own; a look-down
    // would grab `180.00` (an item price) as the total. No total at all is
    // the honest answer here.
    final r = h().guessTotal([
      'ITEM            QTY    PRICE     TOTAL',
      'Hathaway Tote   -1     180.00    (126.00)',
      "Baird Hipster   -1      70.00     (70.00)",
    ]);
    expect(r, isNull);
  });

  test('bare negative integers stay out (qty -1 is a count, not money)', () {
    final r = h().guessTotal(['Apple -1', 'TOTAL -1']);
    expect(r, isNull);
  });
}
