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
