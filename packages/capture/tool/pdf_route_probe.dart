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

// Scratch probe: run the born-digital PDF path + DocumentRouter on a file
// and print the lines and the verdict — the field-diagnosis twin of
// benchmark.dart for real-world PDFs (no device needed).
import 'dart:io';
import 'dart:typed_data';

import 'package:capture/capture.dart';
import 'package:core/core.dart';

Future<void> main(List<String> args) async {
  final bytes = Uint8List.fromList(File(args.first).readAsBytesSync());
  final reader = DocumentExtractor(extractor: null);
  final read = await reader.fromPdf(bytes);
  if (read == null || read.isEmpty) {
    stdout.writeln('NO TEXT (extractor returned nothing)');
    return;
  }
  stdout.writeln('LINES (${read.lines.length}):');
  for (final l in read.lines) {
    stdout.writeln('  |$l|');
  }
  final verdict = DocumentRouter.route(
    read.lines,
    currency: const Currency('USD', r'$', 2, 'US Dollar'),
  );
  stdout.writeln('VERDICT: $verdict');
}
