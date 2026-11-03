import 'dart:convert';
import 'dart:io';

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
    final env = ((jsonDecode(utf8.decode(bytes)) as Map)['envelopes']
        as List).first as Map;
    expect(env.keys.toList(), widgetEnvelopeKeys);
  });

  test('unknown keys are rejected, not tolerated (§4.4)', () {
    final tainted = jsonDecode(fixtureFile.readAsStringSync())
      ..['merchantName'] = 'Corner Café';
    expect(
      () => decodeWidgetSnapshot(
        utf8.encode(jsonEncode(tainted)) as dynamic,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('a future schema version fails loudly', () {
    final future = jsonDecode(fixtureFile.readAsStringSync())..['v'] = 2;
    expect(
      () => decodeWidgetSnapshot(utf8.encode(jsonEncode(future)) as dynamic),
      throwsA(isA<FormatException>()),
    );
  });
}
