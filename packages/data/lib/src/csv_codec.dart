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

/// RFC 4180 CSV codec shared by export and import (E5 spec §2/§4).
///
/// Deliberately hand-rolled: the grammar is small, and a dependency would
/// have to be re-audited against every quirky bank dump anyway. Round-trip
/// guarantee: `decodeCsv(encodeCsv(rows)) == rows` for every row list that
/// contains no all-empty placeholder rows — a lone blank *line* decodes as
/// end-of-file, not as a row, which is what real statement dumps need (the
/// import wizard skips stray blank lines the same way).
library;

/// One field character (comma, quote, CR, LF) forces quoting.
String _esc(String field) {
  final needsQuotes =
      field.contains('"') ||
      field.contains(',') ||
      field.contains('\n') ||
      field.contains('\r');
  return needsQuotes ? '"${field.replaceAll('"', '""')}"' : field;
}

/// Serialize rows as RFC 4180 with CRLF endings.
String encodeCsv(List<List<String>> rows) {
  final sb = StringBuffer();
  for (final row in rows) {
    for (var i = 0; i < row.length; i++) {
      if (i > 0) sb.write(',');
      sb.write(_esc(row[i]));
    }
    sb.write('\r\n');
  }
  return sb.toString();
}

/// Pick the delimiter of a header/first line: `,` `;` or tab, whichever
/// occurs most outside quotes; `,` when it's a tie (bank default).
String sniffDelimiter(String firstLine) {
  var comma = 0, semi = 0, tab = 0;
  var inQuotes = false;
  for (var i = 0; i < firstLine.length; i++) {
    final c = firstLine[i];
    if (c == '"') {
      if (inQuotes && i + 1 < firstLine.length && firstLine[i + 1] == '"') {
        i++;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }
    if (inQuotes) continue;
    switch (c) {
      case ',':
        comma++;
      case ';':
        semi++;
      case '\t':
        tab++;
    }
  }
  if (semi > comma && semi >= tab) return ';';
  if (tab > comma && tab > semi) return '\t';
  return ',';
}

/// Full parser: quoted fields, doubled quotes, embedded delimiters and
/// newlines, LF/CRLF/CR endings. A trailing terminator does not produce a
/// phantom row. Blank lines are dropped — import callers must not see them.
List<List<String>> decodeCsv(String text, {String delimiter = ','}) {
  final rows = <List<String>>[];
  var field = StringBuffer();
  var row = <String>[];
  var inQuotes = false;
  var rowHasContent = false;

  void endField() {
    row.add(field.toString());
    field = StringBuffer();
  }

  void endRow() {
    endField();
    final blank = row.every((f) => f.isEmpty);
    if (!blank) rows.add(row);
    row = <String>[];
    rowHasContent = false;
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
      continue;
    }
    switch (c) {
      case '"':
        inQuotes = true;
        rowHasContent = true;
      case ';':
      case ',':
      case '\t':
        if (c == delimiter) {
          endField();
          rowHasContent = true;
        } else {
          field.write(c);
          rowHasContent = true;
        }
      case '\r':
        if (i + 1 < text.length && text[i + 1] == '\n') i++;
        if (rowHasContent || field.isNotEmpty || row.isNotEmpty) endRow();
      case '\n':
        if (rowHasContent || field.isNotEmpty || row.isNotEmpty) endRow();
      default:
        field.write(c);
        rowHasContent = true;
    }
  }
  if (rowHasContent || field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}
