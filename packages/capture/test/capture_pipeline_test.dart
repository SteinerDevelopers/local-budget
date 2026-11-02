import 'dart:typed_data';

import 'package:capture/capture.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

final usd = Currency.resolve('USD');

const grocery = [
  'FRESH MART #204',
  '4400 LAKEVIEW AVE',
  '03/15/2026 14:22:01',
  'BANANAS 1.29',
  'SUBTOTAL 9.78',
  'TOTAL 10.33',
  'THANK YOU!',
];

class FakeExtractor implements TextExtractor {
  FakeExtractor(this.lines);
  final List<String> lines;
  @override
  Future<List<String>> extractText(Object bytes) async => lines;
}

class CountingStructurer implements LlmStructurer {
  CountingStructurer({this.available = true, this.reply});
  final bool available;
  final ReceiptDraft? reply;
  int calls = 0;

  @override
  bool isAvailable() => available;

  @override
  Future<ReceiptDraft?> structure(Object bytes, List<String> lines) async {
    calls++;
    return reply;
  }
}

void main() {
  final now = DateTime(2026, 11, 2);
  final img = Uint8List.fromList([1, 2, 3]);

  CapturePipeline pipe({
    TextExtractor? extractor,
    LlmStructurer? structurer,
  }) =>
      CapturePipeline(
        currency: usd,
        extractor: extractor,
        structurer: structurer,
        now: now,
      );

  group('tiers 1+2', () {
    test('image → extractor lines → prefilled draft', () async {
      final draft =
          await pipe(extractor: FakeExtractor(grocery)).fromImage(img);
      expect(draft.merchant, 'FRESH MART #204');
      expect(draft.date, DateTime(2026, 3, 15));
      expect(draft.total!.minorUnits, 1033);
      expect(draft.isComplete, true);
    });

    test('garbage OCR is a state, not an error — empty draft, lines kept',
        () async {
      final draft = await pipe(extractor: FakeExtractor(['00 11 ##', '***']))
          .fromImage(img);
      expect(draft.isComplete, false);
      expect(draft.total, isNull);
      expect(draft.rawLines, ['00 11 ##', '***']);
    });

    test('no extractor (host without OCR) still yields a reviewable draft',
        () async {
      final draft = await pipe().fromImage(img);
      expect(draft.isComplete, false);
      expect(draft.usedLlm, false);
    });

    test('text-layer lines path needs no extractor', () async {
      final draft = await pipe().fromTextLines(grocery);
      expect(draft.total!.minorUnits, 1033);
      expect(draft.merchant, 'FRESH MART #204');
    });
  });

  group('tier-3 gating', () {
    test('confident draft short-circuits — structurer never called', () async {
      final st = CountingStructurer(reply: null);
      await pipe(extractor: FakeExtractor(grocery), structurer: st)
          .fromImage(img);
      expect(st.calls, 0);
    });

    test('missing total triggers structuring; fill lands, usedLlm set',
        () async {
      final st = CountingStructurer(
        reply: ReceiptDraft(
          total: Money(1033, usd),
          totalConfidence: FieldConfidence.medium,
        ),
      );
      final draft = await pipe(
        extractor: FakeExtractor(['STORE', '03/15/2026', 'CASH 10.33']),
        structurer: st,
      ).fromImage(img);
      expect(st.calls, 1);
      expect(draft.total!.minorUnits, 1033);
      expect(draft.usedLlm, true);
    });

    test('device without Nano: isAvailable false costs nothing', () async {
      final st = CountingStructurer(available: false, reply: null);
      final draft = await pipe(
        extractor: FakeExtractor(['STORE', 'NO NUMBERS HERE']),
        structurer: st,
      ).fromImage(img);
      expect(st.calls, 0);
      expect(draft.usedLlm, false);
      expect(draft.isComplete, false);
    });

    test('structurer returning null leaves the heuristic draft untouched',
        () async {
      final st = CountingStructurer(reply: null);
      final draft = await pipe(
        extractor: FakeExtractor(['STORE', 'NO NUMBERS HERE']),
        structurer: st,
      ).fromImage(img);
      expect(st.calls, 1);
      expect(draft.usedLlm, false);
    });
  });
}
