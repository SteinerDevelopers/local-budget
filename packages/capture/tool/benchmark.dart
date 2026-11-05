// #31 — screenshot OCR benchmark harness (device × resolution matrix).
//
// Drives the TextExtractor -> ReceiptHeuristics end of CapturePipeline over
// the generated corpus and reports field-level precision/recall plus p50/p95
// latency per (script, mode, resolution) cell. Regression budget: the
// grand-total field's precision must stay >= --budget (default 0.85),
// checked over ALL images, exit code 2 when violated.
//
// Backends:
//   --backend gold     TextExtractor returns the manifest's ground-truth
//                      lines. Measures the Tier-2 parser and timing floor;
//                      runs anywhere pure Dart runs (sandbox, runner, mini-PC).
//   --backend sidecar  Lines are read from <image>.lines.txt next to the
//                      images (or --sidecars DIR). On the emulator farm /
//                      physical devices the OCR bridge dumps ML Kit output
//                      into those sidecars first — see TOOLING.md.
//
//   dart run tool/benchmark.dart --corpus tool/corpus [--backend gold]
//       [--budget 0.85] [--reps 5] [--log results.jsonl]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:capture/capture.dart';
import 'package:core/core.dart';

/// Deterministic stub: the extractor's identity is the lines it replays.
class _ReplayExtractor implements TextExtractor {
  _ReplayExtractor(this.lines);
  final List<String> lines;

  @override
  Future<List<String>> extractText(Uint8List imageBytes) async => lines;
}

class _FieldTally {
  int predictedCount = 0;
  int correctCount = 0;
  int expectedCount = 0;

  double get precision =>
      predictedCount == 0 ? 1 : correctCount / predictedCount;
  double get recall => expectedCount == 0 ? 1 : correctCount / expectedCount;
  Map<String, Object> toJson() => {
        'predicted': predictedCount,
        'correct': correctCount,
        'expected': expectedCount,
        'precision': double.parse(precision.toStringAsFixed(4)),
        'recall': double.parse(recall.toStringAsFixed(4)),
      };
}

class _Cell {
  final merchant = _FieldTally();
  final date = _FieldTally();
  final total = _FieldTally();
  final latenciesUs = <int>[];
  int images = 0;
}

String _argStr(List<String> args, String name, String fallback) {
  final i = args.indexOf('--$name');
  return (i == -1 || i + 1 >= args.length) ? fallback : args[i + 1];
}

double _argD(List<String> args, String name, double fallback) {
  final i = args.indexOf('--$name');
  return (i == -1 || i + 1 >= args.length)
      ? fallback
      : double.parse(args[i + 1]);
}

int _argI(List<String> args, String name, int fallback) {
  final i = args.indexOf('--$name');
  return (i == -1 || i + 1 >= args.length) ? fallback : int.parse(args[i + 1]);
}

Future<void> main(List<String> args) async {
  final corpusDir = _argStr(args, 'corpus', 'corpus');
  final backend = _argStr(args, 'backend', 'gold');
  final sidecars = _argStr(args, 'sidecars', corpusDir);
  final budget = _argD(args, 'budget', 0.85);
  final reps = _argI(args, 'reps', 5);
  final log = _argStr(args, 'log', '');

  final manifestFile = File('$corpusDir/manifest.json');
  if (!manifestFile.existsSync()) {
    stderr
        .writeln('no manifest at $corpusDir — run tool/corpus_gen.dart first');
    exitCode = 1;
    return;
  }
  if (backend != 'gold' && backend != 'sidecar') {
    stderr.writeln('unknown backend $backend (gold|sidecar)');
    exitCode = 1;
    return;
  }
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
  final images = (manifest['images'] as List).cast<Map<String, Object?>>();

  final cells = <String, _Cell>{};
  final allLatenciesUs = <int>[];
  var missingSidecars = 0;

  for (final img in images) {
    final file = img['file'] as String;
    // E11 statement/bill frames are scored by the data package's
    // document_bench.dart; this harness measures the receipt pipeline only.
    if ((img['kind'] ?? 'receipt') != 'receipt') continue;
    final bytes = File('$corpusDir/$file').readAsBytesSync();
    final List<String> lines;
    if (backend == 'gold') {
      lines = (img['lines'] as List).cast<String>();
    } else {
      final sf = File('$sidecars/${file.replaceAll('.png', '.lines.txt')}');
      if (!sf.existsSync()) {
        missingSidecars++;
        continue; // device run missed this frame; counted in the footer
      }
      lines = const LineSplitter()
          .convert(sf.readAsStringSync())
          .where((l) => l.trim().isNotEmpty)
          .toList();
    }

    final exp = img['expected'] as Map<String, Object?>;
    final expDate = DateTime.parse(exp['date'] as String);
    final cell = cells.putIfAbsent(
        '${img['script']}/${img['mode']}/${img['resolution']}', () => _Cell());
    cell.images++;

    for (var rep = 0; rep < reps; rep++) {
      final pipeline = CapturePipeline(
        currency: Currency.resolve(img['currency'] as String),
        extractor: _ReplayExtractor(lines),
        // No structurer: Tier 3 is device-gated and not part of this matrix.
      );
      final sw = Stopwatch()..start();
      final draft = await pipeline.fromImage(bytes);
      sw.stop();
      cell.latenciesUs.add(sw.elapsedMicroseconds);
      allLatenciesUs.add(sw.elapsedMicroseconds);
      if (rep > 0) continue; // score fields once per image

      for (final field in const ['merchant', 'date', 'total']) {
        final tally = switch (field) {
          'merchant' => cell.merchant,
          'date' => cell.date,
          _ => cell.total,
        };
        final bool predicted;
        final bool correct;
        switch (field) {
          case 'merchant':
            final p = draft.merchant?.trim().toUpperCase();
            predicted = p != null && p.isNotEmpty;
            correct =
                predicted && p == (exp['merchant'] as String).toUpperCase();
          case 'date':
            final d = draft.date;
            predicted = d != null;
            correct = predicted &&
                d.year == expDate.year &&
                d.month == expDate.month &&
                d.day == expDate.day;
          default:
            final t = draft.total;
            predicted = t != null;
            correct = predicted && t.minorUnits == exp['totalCents'] as int;
        }
        if (predicted) tally.predictedCount++;
        if (correct) tally.correctCount++;
        tally.expectedCount++;
      }
    }
  }

  _report(cells, allLatenciesUs, backend, budget, missingSidecars);
  await _maybeLog(log, backend, manifest, cells, allLatenciesUs, budget);
}

void _report(Map<String, _Cell> cells, List<int> lats, String backend,
    double budget, int missing) {
  stdout.writeln(
      'benchmark backend=$backend  images=${cells.values.fold<int>(0, (a, c) => a + c.images)}'
      '${missing > 0 ? "  missing-sidecars=$missing" : ""}');
  stdout.writeln(
      'script/mode/res        n    merchant P/R   date P/R    total P/R    p50ms  p95ms');
  final keys = cells.keys.toList()..sort();
  var totalPred = 0, totalCorrect = 0;
  for (final k in keys) {
    final c = cells[k]!;
    totalPred += c.total.predictedCount;
    totalCorrect += c.total.correctCount;
    stdout.writeln('${k.padRight(24)} ${c.images.toString().padLeft(2)}  '
        '${_pr(c.merchant)}  ${_pr(c.date)}  ${_pr(c.total)}  '
        '${(_pct(c.latenciesUs, 0.50) / 1000).toStringAsFixed(1).padLeft(6)}'
        '${(_pct(c.latenciesUs, 0.95) / 1000).toStringAsFixed(1).padLeft(6)}');
  }
  final totalPrecision = totalPred == 0 ? 0.0 : totalCorrect / totalPred;
  stdout.writeln(
      'grand-total precision = ${(totalPrecision * 100).toStringAsFixed(1)}% '
      '($totalCorrect/$totalPred predicted)  budget = ${(budget * 100).toStringAsFixed(0)}%');
  stdout.writeln(
      'overall latency p50=${(_pct(lats, 0.50) / 1000).toStringAsFixed(1)}ms '
      'p95=${(_pct(lats, 0.95) / 1000).toStringAsFixed(1)}ms (n=${lats.length})');
  if (totalPrecision < budget) {
    stdout.writeln('BUDGET VIOLATED');
    exitCode = 2;
  }
}

String _pr(_FieldTally t) =>
    '${(t.precision * 100).toStringAsFixed(0).padLeft(3)}/${(t.recall * 100).toStringAsFixed(0).padLeft(3)}';

double _pct(List<int> sortedLike, double q) {
  if (sortedLike.isEmpty) return 0;
  final s = [...sortedLike]..sort();
  final i = ((s.length - 1) * q).round();
  return s[i].toDouble();
}

Future<void> _maybeLog(
    String logPath,
    String backend,
    Map<String, Object?> manifest,
    Map<String, _Cell> cells,
    List<int> lats,
    double budget) async {
  if (logPath.isEmpty) return;
  String sha;
  try {
    sha = Process.runSync('git', ['rev-parse', '--short', 'HEAD'])
        .stdout
        .toString()
        .trim();
  } on ProcessException {
    sha = 'unknown';
  }
  final entry = {
    'ts': DateTime.now().toUtc().toIso8601String(),
    'sha': sha,
    'backend': backend,
    'seed': manifest['seed'],
    'budget': budget,
    'cells': {
      for (final e in cells.entries)
        e.key: {
          'images': e.value.images,
          'merchant': e.value.merchant.toJson(),
          'date': e.value.date.toJson(),
          'total': e.value.total.toJson(),
          'p50ms': _pct(e.value.latenciesUs, 0.5) / 1000,
          'p95ms': _pct(e.value.latenciesUs, 0.95) / 1000,
        },
    },
    'overall': {
      'p50ms': _pct(lats, 0.5) / 1000,
      'p95ms': _pct(lats, 0.95) / 1000,
      'n': lats.length,
    },
    'exitCode': exitCode,
  };
  File(logPath)
      .writeAsStringSync('${jsonEncode(entry)}\n', mode: FileMode.append);
  stdout.writeln('run logged -> $logPath');
}
