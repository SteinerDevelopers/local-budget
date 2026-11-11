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

// E11 §6 — statement/bill corpus scorer (gold backend, headless).
//
// Reads a manifest produced by capture's tool/corpus_gen.dart and scores
// the *parsers* against its ground truth: `StatementLines.tryParse` for
// statement frames (row precision budget --row-budget, default 0.90) and
// `BillDraft.draft` for bill frames (amount-due precision budget
// --amount-budget, default 0.85). Exit code 2 when a budget is violated —
// the same contract as capture's benchmark.dart.
//
// Gold backend by construction: the extractor's output is the manifest's
// `lines` verbatim, so this measures the Tier-2 parsers and nothing above
// them. Recall is printed next to precision — precision alone could be
// gamed by refusing to parse, so a run that parses little is visible, not
// silently green.
//
//   dart run tool/document_bench.dart --corpus <dir>   # capture/tool/corpus
//       [--row-budget 0.90] [--amount-budget 0.85]
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:data/data.dart';

class _Tally {
  int predicted = 0;
  int correct = 0;
  int expected = 0;

  double get precision => predicted == 0 ? 1 : correct / predicted;
  double get recall => expected == 0 ? 1 : correct / expected;

  void merge(_Tally o) {
    predicted += o.predicted;
    correct += o.correct;
    expected += o.expected;
  }
}

String _argStr(List<String> a, String n, String f) {
  final i = a.indexOf('--$n');
  return (i == -1 || i + 1 >= a.length) ? f : a[i + 1];
}

double _argD(List<String> a, String n, double f) {
  final i = a.indexOf('--$n');
  return (i == -1 || i + 1 >= a.length) ? f : double.parse(a[i + 1]);
}

int _epochDay(DateTime d) =>
    DateTime(d.year, d.month, d.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

void main(List<String> args) {
  final corpusDir = _argStr(args, 'corpus', 'corpus');
  final rowBudget = _argD(args, 'row-budget', 0.90);
  final amountBudget = _argD(args, 'amount-budget', 0.85);

  final mf = File('$corpusDir/manifest.json');
  if (!mf.existsSync()) {
    stderr.writeln(
      'no manifest at $corpusDir — run capture tool/corpus_gen.dart first',
    );
    exitCode = 1;
    return;
  }
  final manifest = jsonDecode(mf.readAsStringSync()) as Map<String, Object?>;
  final now = DateTime.parse(
    (manifest['benchNow'] as String?) ?? DateTime.now().toIso8601String(),
  );
  final images = (manifest['images'] as List).cast<Map<String, Object?>>();

  final rows = _Tally();
  final perScript = <String, _Tally>{};
  final amounts = _Tally();
  final dueDates = _Tally();
  var statements = 0, bills = 0, unparsable = 0;

  for (final img in images) {
    final kind = img['kind'] as String?;
    if (kind != 'statement' && kind != 'bill') continue;
    final lines = (img['lines'] as List).cast<String>();
    final currency = Currency.resolve(img['currency'] as String);

    if (kind == 'statement') {
      statements++;
      final exp = (img['expected'] as Map)['rows'] as List;
      final expected = [
        for (final r in exp.cast<Map<String, Object?>>())
          (
            _epochDay(DateTime.parse(r['date'] as String)),
            r['minor'] as int,
            r['isIncome'] as bool,
          ),
      ];
      final taken = List.filled(expected.length, false);
      final parse = StatementLines.tryParse(
        lines,
        currency: currency,
        now: now,
      );
      if (parse == null) unparsable++;
      final got = parse?.rows ?? const [];
      final t = perScript.putIfAbsent('${img['script']}', () => _Tally());
      for (final p in got) {
        t.predicted++;
        rows.predicted++;
        final key = (_epochDay(p.date), p.minor, p.isIncome);
        var hit = -1;
        for (var k = 0; k < expected.length; k++) {
          if (!taken[k] && expected[k] == key) {
            hit = k;
            break;
          }
        }
        if (hit >= 0) {
          taken[hit] = true;
          t.correct++;
          rows.correct++;
        }
      }
      t.expected += expected.length;
      rows.expected += expected.length;
    } else {
      bills++;
      final exp = img['expected'] as Map<String, Object?>;
      final draft = BillDraft.draft(lines, currency: currency, now: now);
      amounts.expected++;
      dueDates.expected++;
      final got = draft.amountDue?.minorUnits;
      if (got != null) {
        amounts.predicted++;
        if (got == exp['amountCents']) amounts.correct++;
      }
      final due = draft.dueDate;
      if (due != null) {
        dueDates.predicted++;
        final want = DateTime.parse(exp['dueDate'] as String);
        if (due.year == want.year &&
            due.month == want.month &&
            due.day == want.day) {
          dueDates.correct++;
        }
      }
    }
  }

  void line(String name, _Tally t) => stdout.writeln(
    '${name.padRight(22)} predicted ${t.predicted.toString().padLeft(4)}  '
    'correct ${t.correct.toString().padLeft(4)}  '
    'expected ${t.expected.toString().padLeft(4)}  '
    'precision ${t.precision.toStringAsFixed(3)}  '
    'recall ${t.recall.toStringAsFixed(3)}',
  );

  stdout.writeln(
    'E11 document bench — $statements statements, $bills bills'
    ' (${unparsable} refused outright) from $corpusDir',
  );
  for (final e in perScript.entries) {
    line('rows/${e.key}', e.value);
  }
  line('rows (all)', rows);
  line('bill amount-due', amounts);
  line('bill due-date', dueDates);

  var failed = false;
  if (statements == 0 || bills == 0) {
    stderr.writeln(
      'corpus has no ${statements == 0 ? 'statement' : 'bill'} '
      'frames — regenerate with an E11-aware corpus_gen',
    );
    failed = true;
  }
  if (rows.precision < rowBudget) {
    stderr.writeln(
      'BUDGET: statement row precision ${rows.precision.toStringAsFixed(3)}'
      ' < $rowBudget',
    );
    failed = true;
  }
  if (amounts.precision < amountBudget) {
    stderr.writeln(
      'BUDGET: bill amount-due precision '
      '${amounts.precision.toStringAsFixed(3)} < $amountBudget',
    );
    failed = true;
  }
  exitCode = failed ? 2 : 0;
  if (!failed) {
    stdout.writeln('budgets met (rows ≥ $rowBudget, amounts ≥ $amountBudget)');
  }
}
