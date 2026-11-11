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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

/// E7c §4.2/§4.4 parity contract, Dart half. The same fixture file lives
/// beside the Kotlin reader's test (android unit test), so a schema rename
/// on either side fails at least one suite.
void main() {
  final fixtureFile = File('test/fixtures/widget_state.json');

  test('fixture round-trips through the codec', () {
    final bytes = fixtureFile.readAsBytesSync();
    final s = decodeWidgetSnapshot(bytes);
    expect(s.yearMonth, '2026-11');
    expect(s.currency, 'USD');
    expect(s.spentMinor, 41275);
    expect(
      s.envelopes.map((e) => (e.name, e.remainingMinor)),
      [('Groceries', 12100), ('Fun', -800)],
    );
    // Re-encoding is byte-identical: the Kotlin parser sees exactly the
    // key set this test pins, in this order.
    expect(utf8.decode(encodeWidgetSnapshot(s)), utf8.decode(bytes));
  });

  test('encoded keys are exactly the allow-list (§4.4)', () {
    final bytes = encodeWidgetSnapshot(
      WidgetSnapshot(
        updatedAtMs: 1793692800000,
        yearMonth: '2026-11',
        currency: 'EUR',
        spentMinor: 1,
        budgetSpentMinor: 1,
        budgetLimitMinor: 2,
        envelopes: const [WidgetEnvelope(name: 'X', remainingMinor: 0)],
      ),
    );
    expect(
      (jsonDecode(utf8.decode(bytes)) as Map).keys.toList(),
      widgetSnapshotKeys,
    );
    final env = ((jsonDecode(utf8.decode(bytes)) as Map)['envelopes'] as List)
        .first as Map;
    expect(env.keys.toList(), widgetEnvelopeKeys);
  });

  test('unknown keys are rejected, not tolerated (§4.4)', () {
    final tainted = jsonDecode(fixtureFile.readAsStringSync())
      ..['merchantName'] = 'Corner Café';
    expect(
      () => decodeWidgetSnapshot(
        Uint8List.fromList(utf8.encode(jsonEncode(tainted))),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('a future schema version fails loudly', () {
    final future = jsonDecode(fixtureFile.readAsStringSync())..['v'] = 2;
    expect(
      () => decodeWidgetSnapshot(
        Uint8List.fromList(utf8.encode(jsonEncode(future))),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
