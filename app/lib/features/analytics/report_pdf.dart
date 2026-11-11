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

import 'package:core/core.dart' show Money;
import 'package:data/data.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// E7 §2.3 — the pro "PDF report": the multi-page document (summary,
/// monthly tables, category breakdown) rendered from the very [ReportData]
/// the Excel sheets print, so the two exports agree by construction.
///
/// Typography is the built-in Helvetica family only — §2.3 allows no
/// network fonts, which also means glyphs outside the core-font charset
/// substitute instead of embedding a megabyte of CJK.
abstract final class ReportPdf {
  /// Deterministic document metadata (the PDF /Title), matching the
  /// workbook Summary sheet's first label.
  static const String title = 'Steiner Budget report';

  /// Share-sheet file name; same date stem as the workbook's.
  static String fileName(DateTime now) =>
      ReportWorkbook.fileName(now).replaceAll('.xlsx', '.pdf');

  static Future<Uint8List> build(ReportData d) async {
    final doc = pw.Document(title: title, creator: 'Steiner Budget');
    String money(int minor) => Money(minor, d.currency).format();
    final showCompare = d.months.any((m) => m.compareSpentMinor != null);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 44, 40, 40),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${d.rangeLabel} · page ${ctx.pageNumber}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          pw.Text(
            title,
            // (pdf 3.12 cannot const-evaluate a bold TextStyle's font fallbacks.)
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            '${d.rangeLabel} · generated ${isoDateTime(d.generatedAt)}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 16),
          _heading('Summary'),
          _table(
            ['Total', d.currency.code],
            [
              ['Spent', money(d.spentMinor)],
              ['Income', money(d.incomeMinor)],
              ['Net', money(d.netMinor)],
              if (d.compareLabel != null) ['Compare range', d.compareLabel!],
              if (d.compareSpentMinor != null)
                ['Compare spent', money(d.compareSpentMinor!)],
              if (d.compareNormalizedMinor != null)
                [
                  'Compare spent (normalized)',
                  money(d.compareNormalizedMinor!),
                ],
              if (d.deltaBp != null)
                [
                  'Change',
                  '${d.deltaBp! >= 0 ? '+' : ''}'
                      '${(d.deltaBp! / 100).toStringAsFixed(1)}%',
                ],
            ],
          ),
          pw.SizedBox(height: 16),
          _heading('Months'),
          if (d.months.isEmpty)
            _empty('No spending in this range.')
          else
            _table(
              ['Month', 'Spent', if (showCompare) 'Spent (compare)'],
              [
                for (final m in d.months)
                  [
                    m.yearMonth,
                    money(m.spentMinor),
                    if (showCompare)
                      m.compareSpentMinor == null
                          ? '—'
                          : money(m.compareSpentMinor!),
                  ],
              ],
            ),
          pw.SizedBox(height: 16),
          _heading('Categories'),
          if (d.categories.isEmpty)
            _empty('No spending in this range.')
          else
            _table(
              const ['Category', 'Spent', 'Share'],
              [
                for (final c in d.categories)
                  [
                    c.name,
                    money(c.spentMinor),
                    '${(c.shareBp / 100).toStringAsFixed(1)}%',
                  ],
              ],
            ),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _heading(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _empty(String text) => pw.Text(
    text,
    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
  );

  /// Bordered table with a shaded header row and right-aligned amounts.
  static pw.Widget _table(List<String> header, List<List<String>> rows) =>
      pw.TableHelper.fromTextArray(
        headers: header,
        data: rows,
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        headerStyle: const pw.TextStyle(fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellAlignments: {
          for (var c = 1; c < header.length; c++) c: pw.Alignment.centerRight,
        },
      );
}
