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

// #31 — benchmark corpus generator.
//
// Renders synthetic receipts to PNG at the screenshot resolutions of the
// device matrix (720p/1080p/1440p portrait), light and dark mode, latin and
// cyrillic scripts, and writes a manifest with the ground truth plus a
// `.lines.txt` sidecar per image. Everything is deterministic from --seed;
// no fonts, no image packages, no network.
//
//   dart run tool/corpus_gen.dart --out tool/corpus [--seed N] [--per-cell K]
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'document_scripts.dart';
import 'font5x7.dart';
import 'png_writer.dart';
import 'receipt_scripts.dart';

const Map<String, (int, int)> kResolutions = {
  '720p': (720, 1280),
  '1080p': (1080, 1920),
  '1440p': (1440, 2560),
};

int _arg(List<String> args, String name, int fallback) {
  final i = args.indexOf('--$name');
  if (i == -1 || i + 1 >= args.length) return fallback;
  return int.parse(args[i + 1]);
}

String _argStr(List<String> args, String name, String fallback) {
  final i = args.indexOf('--$name');
  if (i == -1 || i + 1 >= args.length) return fallback;
  return args[i + 1];
}

void main(List<String> args) {
  final outDir = Directory(_argStr(args, 'out', 'corpus'));
  final seed = _arg(args, 'seed', 20261102);
  final perCell = _arg(args, 'per-cell', 4);

  outDir.createSync(recursive: true);
  final images = <Map<String, Object?>>[];
  // A fresh run replaces the corpus wholesale; stale images would otherwise
  // keep being benchmarked after the seed or scripts change.
  for (final f in outDir.listSync().whereType<File>()) {
    if (f.path.endsWith('.png') ||
        f.path.endsWith('.lines.txt') ||
        f.path.endsWith('manifest.json')) {
      f.deleteSync();
    }
  }

  for (final script in const ['latin', 'cyrillic']) {
    for (final mode in const ['light', 'dark']) {
      for (final e in kResolutions.entries) {
        final res = e.key;
        final (w, h) = e.value;
        final rnd = Random(seed + script.hashCode + mode.hashCode);
        for (var i = 0; i < perCell; i++) {
          final r = makeReceipt(script, rnd);
          final name = '${script}_${res}_${mode}_$i.png';
          final bytes = renderReceipt(r, w, h, dark: mode == 'dark');
          File('${outDir.path}/$name').writeAsBytesSync(bytes);
          File('${outDir.path}/$name'.replaceAll('.png', '.lines.txt'))
              .writeAsStringSync('${r.lines.join('\n')}\n');
          images.add({
            'file': name,
            'kind': 'receipt',
            'script': script,
            'resolution': res,
            'mode': mode,
            'width': w,
            'height': h,
            'currency': r.currency,
            'expected': {
              'merchant': r.merchant,
              'date':
                  '${r.date.year.toString()}-${r.date.month.toString().padLeft(2, '0')}-${r.date.day.toString().padLeft(2, '0')}',
              'totalCents': r.totalCents,
            },
            'lines': r.lines,
          });
        }
      }
    }
  }

  // E11 §6 — statements (both scripts) and US bills (latin only: the bill
  // vocabulary the draft reads is English). Same cell matrix as receipts.
  for (final kind in const ['statement', 'bill']) {
    for (final script in kind == 'statement'
        ? const ['latin', 'cyrillic']
        : const ['latin']) {
      for (final mode in const ['light', 'dark']) {
        for (final e in kResolutions.entries) {
          final res = e.key;
          final (w, h) = e.value;
          final rnd =
              Random(seed + kind.hashCode + script.hashCode + mode.hashCode);
          for (var i = 0; i < perCell; i++) {
            final name = '${kind}_${script}_${res}_${mode}_$i.png';
            final Map<String, Object?> entry;
            final List<String> lines;
            if (kind == 'statement') {
              final s = makeStatement(script, rnd);
              lines = s.lines;
              entry = {
                'currency': s.currency,
                'expected': {
                  'rows': [for (final r in s.rows) r.toJson()],
                },
              };
            } else {
              final b = makeBill(rnd);
              lines = b.lines;
              entry = {
                'currency': b.currency,
                'expected': {
                  'payee': b.payee,
                  'amountCents': b.amountCents,
                  'dueDate': isoDate(b.dueDate),
                },
              };
            }
            final bytes = renderLines(lines, w, h, dark: mode == 'dark');
            File('${outDir.path}/$name').writeAsBytesSync(bytes);
            File('${outDir.path}/$name'.replaceAll('.png', '.lines.txt'))
                .writeAsStringSync('${lines.join('\n')}\n');
            images.add({
              'file': name,
              'kind': kind,
              'script': script,
              'resolution': res,
              'mode': mode,
              'width': w,
              'height': h,
              ...entry,
              'lines': lines,
            });
          }
        }
      }
    }
  }

  final manifest = {
    'seed': seed,
    'perCell': perCell,
    'benchNow': kBenchNow.toIso8601String(),
    'generatedBy': 'tool/corpus_gen.dart',
    'images': images,
  };
  File('${outDir.path}/manifest.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n');
  stdout.writeln(
      'wrote ${images.length} images + manifest.json -> ${outDir.path}');
}

/// Paint one receipt into a [w]x[h] portrait PNG (light or dark mode).
Uint8List renderReceipt(ReceiptScript r, int w, int h, {bool dark = false}) =>
    renderLines(r.lines, w, h, dark: dark);

/// Paint arbitrary document lines — receipts, statements, bills all land
/// here; the fit rule is a property of the text, not the document kind.
Uint8List renderLines(List<String> lines, int w, int h, {bool dark = false}) {
  final maxLen = lines.fold<int>(1, (m, l) => l.length > m ? l.length : m);
  // Fit the widest line into 86% of the width, but never exceed the
  // resolution's own scale (w/180) — smaller text at 1440p is as realistic
  // as larger text at 720p.
  final scale = [
    w ~/ 180,
    (w * 0.86 / (maxLen * advance)).floor(),
  ].reduce(min).clamp(2, 16);
  final lineHeight = (glyphH + 4) * scale;
  final left = (w * 0.07).round();

  final pm = Pixmap(w, h);
  pm.fillGray(dark ? 0 : 255);
  var y = (h * 0.06).round();
  for (final line in lines) {
    drawText(pm, line, left, y, scale, dark ? 255 : 0);
    y += lineHeight;
  }
  return encodePng(pm);
}

/// Bitmap-text draw; unsupported codepoints paint a hollow box so text
/// never silently shifts.
void drawText(Pixmap pm, String text, int x0, int y0, int scale, int gray) {
  var x = x0;
  for (final unit in text.toUpperCase().codeUnits) {
    final ch = String.fromCharCode(unit);
    final g = glyphFor(ch) ??
        ['#####', '#...#', '#...#', '#...#', '#...#', '#...#', '#####'];
    for (var row = 0; row < glyphH; row++) {
      final bits = g[row];
      for (var col = 0; col < glyphW; col++) {
        if (bits.codeUnitAt(col) == 0x23 /* # */) {
          pm.fillRect(x + col * scale, y0 + row * scale, scale, scale, gray);
        }
      }
    }
    x += advance * scale;
  }
}
