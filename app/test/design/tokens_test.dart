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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/design/theme.dart';
import 'package:local_budget/design/tokens.dart';

/// Pins design-doc §3 (decision 10 makes it binding): if a token drifts from
/// the spec, this test fails before any widget can silently ship the change.
void main() {
  group('tokens match spec §3', () {
    test('seed color', () => expect(Tokens.seed, const Color(0xFF2E7D32)));

    test('spacing scale 4/8/12/16/24', () {
      expect(
        [
          Tokens.space1,
          Tokens.space2,
          Tokens.space3,
          Tokens.space4,
          Tokens.space5,
        ],
        [4, 8, 12, 16, 24],
      );
    });

    test('layout pins', () {
      expect(Tokens.rowHeight, 64);
      expect(Tokens.touchMin, 48);
      expect(Tokens.monthLabelSize, 22);
      expect(Tokens.amountHeroSize, 40);
      expect(Tokens.bodySize, 16);
      expect(Tokens.labelCapsSize, 12);
      expect(Tokens.labelCapsTracking, 0.4);
    });

    test('expense sign is U+2212 MINUS SIGN, not ASCII hyphen', () {
      expect(Tokens.minus, '\u2212');
      expect(Tokens.minus.codeUnitAt(0), 0x2212);
      expect(Tokens.minus, isNot('-'));
    });

    test('amounts use tabular figures', () {
      expect(Tokens.tabular, hasLength(1));
      const style = TextStyle(fontFeatures: Tokens.tabular);
      expect(style.fontFeatures, hasLength(1));
    });
  });

  group('theme derives from the single seed (§3 dark = same spec)', () {
    test('light and dark both Material 3', () {
      expect(AppTheme.light().useMaterial3, isTrue);
      expect(AppTheme.dark().useMaterial3, isTrue);
    });

    test('brightness is the only axis', () {
      expect(AppTheme.light().brightness, Brightness.light);
      expect(AppTheme.dark().brightness, Brightness.dark);
    });

    testWidgets('label-caps color resolves to onSurfaceVariant', (
      tester,
    ) async {
      const scheme = ColorScheme.light();
      late TextStyle style;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: scheme, useMaterial3: true),
          home: Builder(
            builder: (context) {
              style = Tokens.labelCaps(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(style.color, scheme.onSurfaceVariant);
      expect(style.fontSize, Tokens.labelCapsSize);
      expect(style.letterSpacing, Tokens.labelCapsTracking);
    });
  });
}
