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
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/design/money_display.dart';
import 'package:local_budget/design/theme.dart';
import 'package:local_budget/design/tokens.dart';
import 'package:local_budget/features/ledger/balance_strip.dart';
import 'package:local_budget/features/ledger/day_label.dart';
import 'package:local_budget/features/ledger/empty_month.dart';
import 'package:local_budget/features/ledger/transaction_row.dart';
import 'package:local_budget/features/ledger/view_models.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(body: child),
);

Money _usd(int cents) => Money(cents, Currency.resolve('USD'));

void main() {
  group('MoneyDisplay (§3 expense-sign)', () {
    test('expense uses U+2212, income uses +', () {
      expect(MoneyDisplay.signed(_usd(1240), isExpense: true), '\u2212\$12.40');
      expect(
        MoneyDisplay.signed(_usd(240000), isExpense: false),
        '+\$2,400.00',
      );
    });

    test('net is plain when >= 0, U+2212 when negative', () {
      expect(MoneyDisplay.net(_usd(500)), '\$5.00');
      expect(MoneyDisplay.net(_usd(-500)), '\u2212\$5.00');
      // never the ASCII hyphen from Money.format()
      expect(MoneyDisplay.net(_usd(-500)), isNot(contains('-')));
    });
  });

  group('DayLabel (§2.1)', () {
    final today = DateTime(2026, 11, 2); // Monday
    test('today / yesterday', () {
      expect(DayLabel.of(today, today: today), 'Today');
      expect(DayLabel.of(DateTime(2026, 11, 1), today: today), 'Yesterday');
    });
    test('older day = Wed 29 Oct form (2026 calendar: a Thursday)', () {
      expect(DayLabel.of(DateTime(2026, 10, 29), today: today), 'Thu 29 Oct');
    });
  });

  testWidgets('TransactionRow expense: minus sign, onSurface, 64dp', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        TransactionRow(
          tile: EntryTile(
            id: 1,
            icon: Icons.local_cafe_outlined,
            title: 'Coffee',
            memo: 'Blue Bottle',
            amount: _usd(1240),
            kind: EntryKind.expense,
            day: DateTime(2026, 10, 29),
          ),
        ),
      ),
    );
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('Blue Bottle'), findsOneWidget);
    final amount = tester.widget<Text>(find.text('\u2212\$12.40'));
    expect(amount.style?.color, isNot(AppTheme.light().colorScheme.primary));
    expect(
      amount.style?.fontFeatures,
      Tokens.tabular,
      reason: 'amounts use tabular figures',
    );
    expect(tester.getSize(find.byType(TransactionRow)).height, 64);
  });

  testWidgets('200% text scale grows the row instead of clipping it (#48)', (
    tester,
  ) async {
    // Bench evidence (Flip6, 2026-11-09): at font_scale 2.0 the fixed 64 dp
    // box overflowed every row by 10 px and clipped merchant sub-labels.
    // The box is scale-aware now: double the text, double the room — and
    // the sub-label stays inside the painted box.
    await tester.pumpWidget(
      _host(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: TransactionRow(
            tile: EntryTile(
              id: 1,
              icon: Icons.local_cafe_outlined,
              title: 'Coffee',
              memo: 'Blue Bottle',
              amount: _usd(1240),
              kind: EntryKind.expense,
              day: DateTime(2026, 10, 29),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(TransactionRow)).height, 128);
    final memo = tester.getRect(find.text('Blue Bottle'));
    final row = tester.getRect(find.byType(TransactionRow));
    expect(memo.bottom, lessThanOrEqualTo(row.bottom));
    expect(memo.top, greaterThanOrEqualTo(row.top));
  });

  testWidgets('200% text scale keeps the strip whole on a phone (#52)', (
    tester,
  ) async {
    // Bench evidence (#52, Flip6 at font_scale 2.0): the 56 dp strip clipped
    // every amount mid-glyph and the year vanished from the month title.
    // The strip grows with the scale; above it the whole stat table takes
    // one uniform shrink factor across fixed gutters (owner review: a
    // lossless table with touching columns is still unreadable). Asserted
    // at a real phone width — the default 800 dp test surface is wider
    // than any phone.
    await tester.pumpWidget(
      _host(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              child: BalanceStrip(
                summary: BalanceSummary(
                  income: _usd(240000),
                  expenses: _usd(65733),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(BalanceStrip)).height, 112);
    final strip = tester.getRect(find.byType(BalanceStrip));
    final rects = [
      for (final v in ['\$2,400.00', '\$657.33', '\$1,742.67'])
        tester.getRect(find.text(v)),
    ];
    for (var i = 0; i < rects.length; i++) {
      final r = rects[i];
      // Whole glyphs: the printed box sits inside the strip, no clip.
      expect(r.bottom, lessThanOrEqualTo(strip.bottom), reason: '$i');
      expect(r.top, greaterThanOrEqualTo(strip.top), reason: '$i');
      expect(r.right, lessThanOrEqualTo(strip.right), reason: '$i');
      expect(r.left, greaterThanOrEqualTo(strip.left), reason: '$i');
    }
    // Owner review of #52: whole glyphs are not enough — the columns must
    // read as a table. The old per-column fit filled the thirds at 200%
    // and touched ('$2,400.00$657.33' scanned as one number); the whole
    // table now takes one shrink factor across real gutters, so adjacent
    // amounts keep provable air.
    for (var i = 0; i + 1 < rects.length; i++) {
      expect(
        rects[i + 1].left - rects[i].right,
        greaterThan(8),
        reason: 'gutter between stat $i and ${i + 1}',
      );
    }
  });

  testWidgets('TransactionRow income: +, primary color', (tester) async {
    await tester.pumpWidget(
      _host(
        TransactionRow(
          tile: EntryTile(
            id: 2,
            icon: Icons.work_outline,
            title: 'Salary',
            amount: _usd(240000),
            kind: EntryKind.income,
            day: DateTime(2026, 10, 30),
          ),
        ),
      ),
    );
    final amount = tester.widget<Text>(find.text('+\$2,400.00'));
    expect(amount.style?.color, AppTheme.light().colorScheme.primary);
    expect(find.text('Salary'), findsOneWidget);
  });

  testWidgets('BalanceStrip: caps labels, positive totals, net primary', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        BalanceStrip(
          summary: BalanceSummary(income: _usd(240000), expenses: _usd(9950)),
        ),
      ),
    );
    expect(find.text('INCOME'), findsOneWidget);
    expect(find.text('EXPENSES'), findsOneWidget);
    expect(find.text('NET'), findsOneWidget);
    expect(find.text('\$2,400.00'), findsOneWidget); // income, unsigned
    expect(find.text('\$99.50'), findsOneWidget); // expenses, unsigned
    final net = tester.widget<Text>(find.text('\$2,300.50'));
    expect(net.style?.color, AppTheme.light().colorScheme.primary);
    expect(tester.getSize(find.byType(BalanceStrip)).height, 56);
  });

  testWidgets('BalanceStrip net negative uses U+2212', (tester) async {
    await tester.pumpWidget(
      _host(
        BalanceStrip(
          summary: BalanceSummary(income: _usd(1000), expenses: _usd(2500)),
        ),
      ),
    );
    expect(find.text('\u2212\$15.00'), findsOneWidget);
  });

  testWidgets('EmptyMonth shows the hint pair', (tester) async {
    await tester.pumpWidget(_host(const EmptyMonth()));
    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.text('Tap + to add your first one'), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
  });
}
