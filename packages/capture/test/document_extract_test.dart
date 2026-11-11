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

import 'dart:typed_data';

import 'package:capture/capture.dart';
import 'package:test/test.dart';

/// Lines keyed by the first byte of the "image" so a test can hand
/// different pages to one extractor; a negative first byte makes it throw.
class _FakeExtractor implements TextExtractor {
  _FakeExtractor(this.linesFor, {this.throwOn = const {}});
  final List<String> Function(int pageTag) linesFor;
  final Set<int> throwOn;
  final List<int> calls = [];

  @override
  Future<List<String>> extractText(Uint8List image) async {
    final tag = image.isEmpty ? 0 : image.first;
    calls.add(tag);
    if (throwOn.contains(tag)) throw StateError('ocr down');
    return linesFor(tag);
  }
}

/// Text layer whose page groups are the constructor's inner lists (the
/// [PdfTextPages] extension splits on the blank-line stream boundaries
/// `SimplePdfText` itself emits).
class _FakePdfText implements PdfText {
  _FakePdfText(this.pages, {this.throws = false});
  final List<List<String>> pages;
  final bool throws;

  @override
  List<String> readTextLayer(Uint8List pdf) {
    if (throws) throw StateError('corrupt');
    final flat = <String>[];
    for (var i = 0; i < pages.length; i++) {
      if (i > 0) flat.add('');
      flat.addAll(pages[i]);
    }
    return flat;
  }
}

class _FakeRenderer implements TextRenderer {
  _FakeRenderer({this.png = const [7], this.throws = false});
  final List<int> png;
  final bool throws;

  @override
  Future<Uint8List> renderPage1(Uint8List pdf) async {
    if (throws) throw StateError('pdf broken');
    return Uint8List.fromList(png);
  }
}

/// A concrete multi-page rasterizer — `renderPages` is torn off from the
/// *concrete* class, mirroring how the app wires the channel adapter.
class _FakePages {
  _FakePages(this.count, {this.throwFrom = 0});
  final int count;
  final int throwFrom;

  Future<List<Uint8List>> renderPages(Uint8List pdf) async {
    if (throwFrom > 0) throw StateError('pdf broken');
    return [
      for (var i = 1; i <= count; i++) Uint8List.fromList([i])
    ];
  }
}

final _bytes = Uint8List.fromList([1, 2, 3]);
final _img = Uint8List.fromList([9]);

/// ≥ kTextLayerMinChars characters so page 1 counts as born-digital.
final _rich = 'BANK OF TEST — STATEMENT PAGE ONE 001'; // 37 chars

void main() {
  group('DocumentExtractor.fromImage', () {
    test('OCR lines come back blank-trimmed, one page', () async {
      final read = await const DocumentExtractor(
        extractor: _TagExtractor(),
      ).fromImage(_img);
      expect(read, isNotNull);
      expect(read!.lines, ['TOTAL 12.34', 'CARD 1234']);
      expect(read.pagesRead, 1);
      expect(read.truncated, isFalse);
    });

    test('no extractor, a throw, or zero lines all read as null', () async {
      expect(await const DocumentExtractor(extractor: null).fromImage(_img),
          isNull);
      expect(
        await DocumentExtractor(
          extractor: _FakeExtractor((_) => const [], throwOn: const {9}),
        ).fromImage(_img),
        isNull,
      );
      expect(
        await DocumentExtractor(
          extractor: _FakeExtractor((_) => const ['', '   ']),
        ).fromImage(_img),
        isNull,
      );
    });
  });

  group('DocumentExtractor.fromPdf', () {
    test('a trusted text layer is taken whole, OCR never runs', () async {
      final ex = _FakeExtractor((_) => ['SHOULD NOT RUN']);
      final read = await DocumentExtractor(
        extractor: ex,
        pdfText: _FakePdfText([
          [_rich],
          ['10/01/2026 CORNER MARKET 24.60 1,204.60'],
        ]),
      ).fromPdf(_bytes);
      expect(read!.lines, [
        _rich,
        '10/01/2026 CORNER MARKET 24.60 1,204.60',
      ]);
      expect(read.pagesRead, 2);
      expect(read.truncated, isFalse);
      expect(ex.calls, isEmpty);
    });

    test('scanned pdf: multi-page render + per-page OCR', () async {
      final pages = _FakePages(3);
      final ex = _FakeExtractor((tag) => ['page $tag line', '  ']);
      final read = await DocumentExtractor(
        extractor: ex,
        scannedPdfPages: pages.renderPages,
        pdfText: _FakePdfText([
          ['note'], // < kTextLayerMinChars ⇒ scanned
        ]),
      ).fromPdf(_bytes);
      expect(read!.lines, ['page 1 line', 'page 2 line', 'page 3 line']);
      expect(read.pagesRead, 3);
      expect(read.truncated, isFalse);
      expect(ex.calls, [1, 2, 3]);
    });

    test('rendering is capped at kRenderedPageCap and disclosed', () async {
      final pages = _FakePages(kRenderedPageCap + 2);
      final read = await DocumentExtractor(
        extractor: _FakeExtractor((tag) => ['row $tag']),
        scannedPdfPages: pages.renderPages,
        pdfText: _FakePdfText([
          ['x']
        ]),
      ).fromPdf(_bytes);
      expect(read!.pagesRead, kRenderedPageCap);
      expect(read.truncated, isTrue);
      expect(read.lines.length, kRenderedPageCap);
    });

    test('page-1-only renderer is the fallback when no multi-page one',
        () async {
      final read = await DocumentExtractor(
        extractor: _FakeExtractor((_) => ['only page']),
        renderer: _FakeRenderer(png: const [42]),
        pdfText: _FakePdfText([
          ['x']
        ]),
      ).fromPdf(_bytes);
      expect(read!.lines, ['only page']);
      expect(read.pagesRead, 1);
      expect(read.truncated, isFalse);
    });

    test('a broken pdf (render throws) is null, never a partial yes', () async {
      expect(
        await DocumentExtractor(
          extractor: _FakeExtractor((_) => ['x']),
          renderer: _FakeRenderer(throws: true),
          pdfText: _FakePdfText([
            ['x']
          ]),
        ).fromPdf(_bytes),
        isNull,
      );
      // …same when even the text-layer read explodes first.
      expect(
        await DocumentExtractor(
          extractor: _FakeExtractor((_) => ['x']),
          renderer: _FakeRenderer(throws: true),
          pdfText: _FakePdfText(const [], throws: true),
        ).fromPdf(_bytes),
        isNull,
      );
      // …and when the *multi-page* rasterizer itself throws (the channel
      // failure path the app actually takes).
      expect(
        await DocumentExtractor(
          extractor: _FakeExtractor((_) => ['x']),
          scannedPdfPages: _FakePages(3, throwFrom: 1).renderPages,
          pdfText: _FakePdfText([
            ['x']
          ]),
        ).fromPdf(_bytes),
        isNull,
      );
    });

    test('one unreadable OCR page keeps the rest', () async {
      final pages = _FakePages(2);
      final read = await DocumentExtractor(
        extractor: _FakeExtractor((tag) => ['ok $tag'], throwOn: const {2}),
        scannedPdfPages: pages.renderPages,
        pdfText: _FakePdfText([
          ['x']
        ]),
      ).fromPdf(_bytes);
      expect(read!.lines, ['ok 1']);
      expect(read.pagesRead, 2);
    });

    test('no OCR at all still yields a (thin) text layer', () async {
      final read = await DocumentExtractor(
        extractor: null,
        pdfText: _FakePdfText([
          ['page one'],
          ['page two'],
        ]),
      ).fromPdf(_bytes);
      expect(read!.lines, ['page one', 'page two']);
      expect(read.pagesRead, 2);
      expect(read.truncated, isFalse);
    });

    test('nothing readable is null', () async {
      expect(
        await DocumentExtractor(
          extractor: null,
          pdfText: _FakePdfText(const []),
        ).fromPdf(_bytes),
        isNull,
      );
    });
  });
}

class _TagExtractor implements TextExtractor {
  const _TagExtractor();
  @override
  Future<List<String>> extractText(Uint8List image) async =>
      const ['TOTAL 12.34', '  ', 'CARD 1234'];
}
