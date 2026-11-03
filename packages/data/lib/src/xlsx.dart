/// E7 spec §2.3 — a minimal XLSX writer, the pro Excel export's one and only
/// spreadsheet dependency. The pub `excel` package is incompatible with this
/// project's archive major version, so the workbook parts are emitted
/// directly: a zip of the six OOXML parts a spreadsheet reader needs. Cells
/// are inline strings or plain numbers — no sharedStrings, no styles beyond
/// one valid default, which keeps every part small enough to build by hand.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One worksheet: a name (Excel's own 31-char/illegal-char rules apply) and
/// typed cell rows — [String] (inline string), [int]/[double] (number), or
/// null (cell skipped). Row and column order is kept as given.
class XlsxSheet {
  const XlsxSheet(this.name, {this.rows = const []});

  final String name;
  final List<List<Object?>> rows;
}

/// Assembles [sheets] into an .xlsx file body. At least one sheet is
/// required (the format is meaningless without), and order is preserved —
/// the report's Summary/Months/Categories/Transactions order is part of the
/// §2.3 contract.
Uint8List encodeXlsx(List<XlsxSheet> sheets) {
  if (sheets.isEmpty) {
    throw ArgumentError('an xlsx workbook needs at least one sheet');
  }
  final seen = <String>{};
  for (final s in sheets) {
    if (!_legalSheetName(s.name)) {
      throw ArgumentError.value(s.name, 'sheet', 'illegal sheet name');
    }
    if (!seen.add(s.name)) {
      throw ArgumentError.value(s.name, 'sheet', 'duplicate sheet name');
    }
  }

  final zip = Archive();
  void add(String name, String content) {
    final data = utf8.encode(content);
    zip.addFile(ArchiveFile(name, data.length, data));
  }

  final overrides = sheets.asMap().entries.map(
    (e) =>
        '<Override PartName="/xl/worksheets/sheet${e.key + 1}.xml" '
        'ContentType="application/vnd.openxmlformats-'
        'officedocument.spreadsheetml.worksheet+xml"/>',
  );
  add('[Content_Types].xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
$overrides
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>
''');

  add('_rels/.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
''');

  final sheetTags = sheets.asMap().entries.map(
    (e) =>
        '<sheet name="${_xmlEscape(e.value.name)}" sheetId="${e.key + 1}" '
        'r:id="rId${e.key + 1}"/>',
  );
  add('xl/workbook.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets>${sheetTags.join()}</sheets>
</workbook>
''');

  // Worksheets are rId1..N (order = tab order); styles hang off the end.
  final relTags = sheets.asMap().entries.map(
    (e) =>
        '<Relationship Id="rId${e.key + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
        'relationships/worksheet" Target="worksheets/sheet${e.key + 1}.xml"/>',
  );
  add('xl/_rels/workbook.xml.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
$relTags
<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
''');

  add('xl/styles.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
<borders count="1"><border/></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
</styleSheet>
''');

  for (var i = 0; i < sheets.length; i++) {
    add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(sheets[i]));
  }

  return Uint8List.fromList(ZipEncoder().encode(zip));
}

String _sheetXml(XlsxSheet sheet) {
  final sb = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n')
    ..write(
      '<worksheet xmlns="http://schemas.openxmlformats.org/'
      'spreadsheetml/2006/main"><sheetData>',
    );
  for (var r = 0; r < sheet.rows.length; r++) {
    final row = sheet.rows[r];
    sb.write('<row r="${r + 1}">');
    for (var c = 0; c < row.length; c++) {
      final cell = row[c];
      if (cell == null) continue;
      final ref = '${_columnName(c)}${r + 1}';
      if (cell is String) {
        sb.write(
          '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">'
          '${_xmlEscape(cell)}</t></is></c>',
        );
      } else if (cell is int) {
        sb.write('<c r="$ref"><v>$cell</v></c>');
      } else if (cell is double) {
        if (!cell.isFinite) {
          throw ArgumentError.value(cell, 'cell', 'non-finite number');
        }
        // Dart's shortest round-trip form: exact for money magnitudes.
        sb.write('<c r="$ref"><v>$cell</v></c>');
      } else {
        throw ArgumentError.value(cell, 'cell', 'unsupported cell type');
      }
    }
    sb.write('</row>');
  }
  return (sb..write('</sheetData></worksheet>\n')).toString();
}

/// 0-based index → A1 column letters (A..Z, AA..; the sheet width never
/// approaches the XFD limit, but the math is trivial).
String _columnName(int index) {
  var n = index + 1;
  final name = <String>[];
  while (n > 0) {
    final rem = (n - 1) % 26;
    name.insert(0, String.fromCharCode(65 + rem));
    n = (n - 1) ~/ 26;
  }
  return name.join();
}

bool _legalSheetName(String name) =>
    name.isNotEmpty &&
    name.length <= 31 &&
    !name.contains(RegExp(r'[[\]:*?/\\]'));

/// Text for XML character data and attributes; control characters that XML
/// 1.0 does not allow are dropped rather than producing a corrupt file.
String _xmlEscape(String value) {
  final sb = StringBuffer();
  for (final unit in value.codeUnits) {
    switch (unit) {
      case 0x26:
        sb.write('&amp;');
      case 0x3C:
        sb.write('&lt;');
      case 0x3E:
        sb.write('&gt;');
      case 0x22:
        sb.write('&quot;');
      case 0x09 || 0x0A || 0x0D:
        sb.writeCharCode(unit);
      default:
        if (unit >= 0x20) sb.writeCharCode(unit);
    }
  }
  return sb.toString();
}
