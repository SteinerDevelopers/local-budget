import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:capture/capture.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

/// Minimal generated PDF: content streams only (the reader locates streams
/// directly — a faithful shape of what receipt generators actually emit).
Uint8List pdfFixture(List<String> streams, {List<bool> flate = const []}) {
  final sb = StringBuffer('%PDF-1.4\n');
  for (var i = 0; i < streams.length; i++) {
    final isF = i < flate.length && flate[i];
    final body = isF
        ? ZLibCodec().encode(utf8.encode(streams[i]))
        : utf8.encode(streams[i]);
    sb.write('${i + 1} 0 obj\n'
        '<< ${isF ? '/Filter /FlateDecode ' : ''}/Length ${body.length} >>\n'
        'stream\n${String.fromCharCodes(body)}\nendstream\nendobj\n');
  }
  sb.write('%%EOF');
  return Uint8List.fromList(
      sb.toString().codeUnits.map((c) => c & 0xFF).toList());
}

String content(List<String> lines) {
  final ops = StringBuffer('BT /F1 12 Tf 72 720 Td');
  for (final l in lines) {
    ops.write(' (${l.replaceAll('(', r'\(').replaceAll(')', r'\)')}) Tj'
        ' 0 -14 Td');
  }
  ops.write(' ET');
  return ops.toString();
}

final receiptLines = [
  'GREEN GROCERS',
  '03/15/2026 14:22',
  'SUBTOTAL 9.78',
  'TOTAL 12.34',
];

class CountingRenderer implements TextRenderer {
  Uint8List? lastInput;
  int calls = 0;
  @override
  Future<Uint8List> renderPage1(Uint8List pdf) async {
    calls++;
    lastInput = pdf;
    return Uint8List.fromList([9, 9, 9]); // opaque "rendered page"
  }
}

class StubExtractor implements TextExtractor {
  StubExtractor(this.lines);
  final List<String> lines;
  @override
  Future<List<String>> extractText(Uint8List image) async => lines;
}

void main() {
  const pdfText = SimplePdfText();
  final usd = Currency.resolve('USD');

  group('SimplePdfText', () {
    test('literal strings split into lines on Td', () {
      final lines = pdfText.readTextLayer(pdfFixture([content(receiptLines)]));
      expect(lines, receiptLines);
      expect(hasTextLayer(lines), isTrue);
    });

    test('FlateDecode streams are transparent', () {
      final lines = pdfText
          .readTextLayer(pdfFixture([content(receiptLines)], flate: [true]));
      expect(lines, receiptLines);
    });

    test('escapes: parentheses and octal latin-1', () {
      final lines = pdfText.readTextLayer(pdfFixture([
        content(['Total (incl) VAT', r'Caf\351'])
      ]));
      expect(lines, ['Total (incl) VAT', 'Café']);
    });

    test('TJ kerning arrays concatenate; digit runs stay intact', () {
      const ops = r'BT [(TOTA) -20 (L) 5 ( ) -10 (1) 2 (2.50)] TJ T*'
          r' [(2) -1 (4.00)] TJ ET';
      final lines = pdfText.readTextLayer(pdfFixture([ops]));
      expect(lines, ['TOTAL 12.50', '24.00']);
    });

    test('hex strings decode', () {
      const ops =
          r'BT <4752414E4420544F54414C2039392E3030> Tj ET'; // GRAND TOTAL 99.00
      final lines = pdfText.readTextLayer(pdfFixture([ops]));
      expect(lines, ['GRAND TOTAL 99.00']);
    });

    test('image-only stream yields no text', () {
      final bytes = pdfFixture(['\u00FF\u00D8\u00FF\u00DB junk no operators']);
      expect(pdfText.readTextLayer(bytes), isEmpty);
      expect(hasTextLayer(pdfText.readTextLayer(bytes)), isFalse);
    });

    test('page boundary: sentinel between streams; page 1 decides', () {
      final bytes = pdfFixture([
        content(['OK']), // tiny page 1
        content(receiptLines), // real text on page 2
      ]);
      final lines = pdfText.readTextLayer(bytes);
      expect(lines.first, 'OK');
      expect(lines, contains(''));
      expect(hasTextLayer(lines), isFalse); // page 1 alone ⇒ scanned
    });

    test('undecodable Flate stream is skipped, never throws', () {
      final bad = Uint8List.fromList(
          utf8.encode('1 0 obj\n<< /Filter /FlateDecode >>\nstream\n') +
              utf8.encode('not-deflate') +
              utf8.encode('\nendstream\nendobj'));
      expect(pdfText.readTextLayer(bad), isEmpty);
    });
  });

  group('pipeline.fromPdf', () {
    test('text-layer PDF goes straight to Tier 2 — no render, no OCR',
        () async {
      final renderer = CountingRenderer();
      final pipe = CapturePipeline(
          currency: usd,
          extractor: StubExtractor(['BOGUS']),
          now: DateTime(2026, 11, 2));
      final draft = await pipe.fromPdf(pdfFixture([content(receiptLines)]),
          renderer: renderer);
      expect(renderer.calls, 0);
      expect(draft.merchant, 'GREEN GROCERS');
      expect(draft.date, DateTime(2026, 3, 15));
      expect(draft.total!.minorUnits, 1234);
    });

    test('scanned PDF renders page 1 and OCRs it', () async {
      final renderer = CountingRenderer();
      final pipe = CapturePipeline(
        currency: usd,
        extractor: StubExtractor(receiptLines),
        now: DateTime(2026, 11, 2),
      );
      final scanned = pdfFixture(
          ['\u00FF\u00D8 binary image data with no text operators whatsoever']);
      final draft = await pipe.fromPdf(scanned, renderer: renderer);
      expect(renderer.calls, 1);
      expect(draft.merchant, 'GREEN GROCERS');
      expect(draft.total!.minorUnits, 1234);
    });

    test('scanned + no renderer: partial text layer still helps', () async {
      final pipe = CapturePipeline(currency: usd, now: DateTime(2026, 11, 2));
      final draft = await pipe.fromPdf(pdfFixture([
        content(['TOTAL 9.99'])
      ])); // < 20 chars
      expect(draft.total!.minorUnits, 999);
    });
  });
}
