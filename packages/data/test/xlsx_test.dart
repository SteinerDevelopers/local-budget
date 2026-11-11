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
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:data/data.dart';
import 'package:test/test.dart';

/// Unzip an encoded workbook into entry name → text so assertions can read
/// the OOXML parts directly (spec §2.3: the file must be a real zip).
Map<String, String> unzip(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  return {
    for (final f in zip.files)
      if (f.isFile) f.name: utf8.decode(f.content),
  };
}

void main() {
  group('encodeXlsx', () {
    test('writes every required OOXML part', () {
      final parts = unzip(
        encodeXlsx([
          XlsxSheet(
            'Summary',
            rows: [
              ['a', 1],
            ],
          ),
        ]),
      );
      expect(
        parts.keys,
        containsAll(<String>[
          '[Content_Types].xml',
          '_rels/.rels',
          'xl/workbook.xml',
          'xl/_rels/workbook.xml.rels',
          'xl/styles.xml',
          'xl/worksheets/sheet1.xml',
        ]),
      );
      expect(parts['[Content_Types].xml'], contains('sheet1.xml'));
      expect(parts['_rels/.rels'], contains('Target="xl/workbook.xml"'));
    });

    test('sheet order and names survive the round trip', () {
      final parts = unzip(
        encodeXlsx([
          XlsxSheet('Summary'),
          XlsxSheet('Months'),
          XlsxSheet('Categories'),
          XlsxSheet('Transactions'),
        ]),
      );
      expect(
        parts['xl/workbook.xml'],
        contains(
          '<sheet name="Summary" sheetId="1" r:id="rId1"/>'
          '<sheet name="Months" sheetId="2" r:id="rId2"/>'
          '<sheet name="Categories" sheetId="3" r:id="rId3"/>'
          '<sheet name="Transactions" sheetId="4" r:id="rId4"/>',
        ),
      );
      expect(parts['xl/_rels/workbook.xml.rels'], contains('sheet4.xml'));
      expect(parts.containsKey('xl/worksheets/sheet4.xml'), isTrue);
    });

    test('inline strings, numbers and skipped nulls keep A1 references', () {
      final sheet = unzip(
        encodeXlsx([
          XlsxSheet(
            'S',
            rows: [
              ['Café & "Sons" <x>', 12, null],
              [null, -3, 0.07],
            ],
          ),
        ]),
      )['xl/worksheets/sheet1.xml']!;
      expect(
        sheet,
        contains(
          '<c r="A1" t="inlineStr"><is><t xml:space="preserve">'
          'Café &amp; &quot;Sons&quot; &lt;x&gt;</t></is></c>',
        ),
      );
      expect(sheet, contains('<c r="B1"><v>12</v></c>'));
      expect(sheet, isNot(contains('r="C1"'))); // null cells are skipped
      expect(sheet, contains('<c r="B2"><v>-3</v></c>'));
      expect(sheet, contains('<c r="C2"><v>0.07</v></c>'));
      expect(sheet, contains('<row r="1">'));
      expect(sheet, contains('<row r="2">'));
    });

    test('column names roll past Z', () {
      final sheet = unzip(
        encodeXlsx([
          XlsxSheet(
            'S',
            rows: [
              [for (var i = 0; i < 28; i++) 'x$i'],
            ],
          ),
        ]),
      )['xl/worksheets/sheet1.xml']!;
      expect(sheet, contains('r="Z1"'));
      expect(sheet, contains('r="AA1"'));
      expect(sheet, contains('r="AB1"'));
    });

    test('an empty ledger still produces a readable workbook', () {
      final parts = unzip(encodeXlsx([XlsxSheet('Summary')]));
      expect(parts['xl/worksheets/sheet1.xml'], contains('<sheetData>'));
      expect(parts['xl/workbook.xml'], contains('name="Summary"'));
    });

    test('illegal workbooks are rejected', () {
      expect(() => encodeXlsx(const []), throwsArgumentError);
      expect(() => encodeXlsx([XlsxSheet('Bad [name]')]), throwsArgumentError);
      expect(() => encodeXlsx([XlsxSheet('')]), throwsArgumentError);
      expect(() => encodeXlsx([XlsxSheet('a' * 32)]), throwsArgumentError);
      expect(
        () => encodeXlsx([XlsxSheet('Dup'), XlsxSheet('Dup')]),
        throwsArgumentError,
      );
    });

    test('unsupported cell types are rejected', () {
      expect(
        () => encodeXlsx([
          XlsxSheet(
            'S',
            rows: [
              [Object()],
            ],
          ),
        ]),
        throwsArgumentError,
      );
    });
  });
}
