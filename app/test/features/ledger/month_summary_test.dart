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
import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/ledger/ledger_screen.dart';

/// Hardening #22: the month strip must sum base-currency *values*, never raw
/// minor units across currencies (¥1,485 is not $14.85).
void main() {
  final usd = Currency.resolve('USD');

  LedgerEntryData row({
    int amountMinor = 0,
    String currencyCode = 'USD',
    int? baseAmountMinor,
    bool isIncome = false,
  }) => LedgerEntryData(
    id: 1,
    day: DateTime(2026, 11, 2),
    amountMinor: amountMinor,
    currencyCode: currencyCode,
    baseAmountMinor: baseAmountMinor,
    isIncome: isIncome,
    categoryId: 1,
    categoryName: 'Food',
    note: null,
  );

  group('summarizeMonth (#22 FX-safe)', () {
    test('single-currency month unchanged', () {
      final s = summarizeMonth([
        row(amountMinor: 1000),
        row(amountMinor: 250),
        row(amountMinor: 5000, isIncome: true),
      ], usd);
      expect(s.expenses.minorUnits, 1250);
      expect(s.income.minorUnits, 5000);
    });

    test('foreign rows count at their FX snapshot, not face value', () {
      final s = summarizeMonth([
        row(amountMinor: 1000), // $10.00 base
        row(
          amountMinor: 1485,
          currencyCode: 'JPY',
          baseAmountMinor: 950, // ¥1,485 ≈ $9.50
        ),
        row(
          amountMinor: 1500,
          currencyCode: 'JPY',
          baseAmountMinor: 120,
          isIncome: true,
        ),
      ], usd);
      expect(s.expenses.minorUnits, 1950); // 1000 + 950 — never 2485
      expect(s.income.minorUnits, 120);
    });

    test('foreign row without a snapshot is skipped, never guessed', () {
      final s = summarizeMonth([
        row(amountMinor: 1000),
        row(amountMinor: 1485, currencyCode: 'JPY'), // no fx snapshot
      ], usd);
      expect(s.expenses.minorUnits, 1000);
    });

    test('summary currency labels the base currency', () {
      final s = summarizeMonth([
        row(amountMinor: 1485, currencyCode: 'JPY', baseAmountMinor: 950),
      ], usd);
      expect(s.expenses.currency.code, 'USD');
    });
  });
}
