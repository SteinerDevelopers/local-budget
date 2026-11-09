// package:test JSON stream -> JUnit XML, because GitLab's test report widget
// speaks JUnit and neither `dart test` nor `flutter test` prints it. No
// dependency, no plugin, testable on the host — the converter is a program,
// not a prayer (same rule as lcov_to_cobertura.dart, its coverage sibling).
//
//   dart ../ci/dart_json_to_junit.dart test-report.json junit.xml
//
// It is a REPORTER, not a gate: it exits 0 even when tests failed, because
// the job's verdict is the exit code of the test command itself. It exits 2
// only when it could not do its own job (missing or unparseable input).
//
// The house's `--reporter compact` output is human, and JSON is not. To keep
// the trace readable the converter prints the JUNIT: verdict line and the
// name plus first error line of every failed test.
import 'dart:convert';
import 'dart:io';

class Case {
  Case(this.name, this.suite);
  String name;
  String suite;
  double seconds = 0;
  String result = 'success'; // success | failure | error
  bool skipped = false;
  bool hidden = false;
  String error = '';
  String stack = '';
}

String esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // Control characters are illegal in XML 1.0; ANSI strips and bell among
    // them sneak in through stack traces.
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

void main(List<String> args) {
  final input = File(args.isNotEmpty ? args[0] : 'test-report.json');
  final output = File(args.length > 1 ? args[1] : 'junit.xml');
  if (!input.existsSync()) {
    stderr.writeln('no test report at ${input.path}');
    exit(2);
  }

  final suites = <int, String>{}; // suiteID -> suite path
  final cases = <int, Case>{}; // testID -> case
  final order = <int>[]; // testIDs in first-seen order, for stable output
  final started = <int, double>{}; // testID -> stream clock at testStart, ms
  var totalSeconds = 0.0;
  var sawEvent = false;

  for (final raw in input.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || !line.startsWith('{')) continue;
    Map<String, dynamic> ev;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) continue;
      ev = decoded;
    } on FormatException {
      continue; // preamble or a wrapped line; the stream is line-delimited
    }
    sawEvent = true;
    switch (ev['type']) {
      case 'suite':
        final s = ev['suite'] as Map<String, dynamic>?;
        if (s != null) suites[s['id'] as int] = '${s['path']}';
        break;
      case 'testStart':
        final t = ev['test'] as Map<String, dynamic>?;
        if (t == null) break;
        final id = t['id'] as int;
        final suiteId = t['suiteID'] as int?;
        final c = Case('${t['name']}', suites[suiteId] ?? 'unknown');
        cases[id] = c;
        order.add(id);
        started[id] = (ev['time'] as num? ?? 0).toDouble();
        break;
      case 'error':
        final c = cases[ev['testID'] as int?];
        if (c == null) break;
        c.error = '${ev['error'] ?? ''}';
        c.stack = '${ev['stackTrace'] ?? ''}';
        break;
      case 'testDone':
        final id = ev['testID'] as int;
        final c = cases[id];
        if (c == null) break;
        c.result = '${ev['result'] ?? 'success'}';
        c.skipped = ev['skipped'] == true;
        // Group containers arrive as hidden tests that own no assertion;
        // counting them would inflate every suite.
        c.hidden = ev['hidden'] == true;
        final t0 = started[id];
        if (t0 != null) {
          // Duration comes from the stream's own clock, not from reading the
          // file: replaying a saved report would otherwise time every case at
          // 0.000s and the test widget would have nothing to sort by.
          final t1 = (ev['time'] as num? ?? t0).toDouble();
          c.seconds = (t1 - t0) / 1000.0;
        }
        break;
      case 'done':
        totalSeconds = (ev['time'] as num? ?? 0).toDouble() / 1000.0;
        break;
    }
  }

  if (!sawEvent) {
    stderr.writeln('no JSON events found in ${input.path} — wrong reporter?');
    exit(2);
  }

  final real = order.map((i) => cases[i]!).where((c) => !c.hidden).toList();
  final bySuite = <String, List<Case>>{};
  for (final c in real) {
    bySuite.putIfAbsent(c.suite, () => <Case>[]).add(c);
  }

  final failures = real.where((c) => c.result == 'failure').length;
  final errors = real.where((c) => c.result == 'error').length;
  final skipped = real.where((c) => c.skipped).length;
  final elapsed = totalSeconds > 0
      ? totalSeconds
      : real.fold<double>(0, (a, c) => a + c.seconds);

  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<testsuites name="dart test" tests="${real.length}" '
      'failures="$failures" errors="$errors" skipped="$skipped" '
      'time="${elapsed.toStringAsFixed(3)}">',
    );
  bySuite.forEach((suite, list) {
    final f = list.where((c) => c.result == 'failure').length;
    final e = list.where((c) => c.result == 'error').length;
    final s = list.where((c) => c.skipped).length;
    final t = list.fold<double>(0, (a, c) => a + c.seconds);
    b.writeln(
      '  <testsuite name="${esc(suite)}" tests="${list.length}" '
      'failures="$f" errors="$e" skipped="$s" time="${t.toStringAsFixed(3)}" '
      'timestamp="${DateTime.now().toUtc().toIso8601String()}">',
    );
    for (final c in list) {
      final attrs =
          'name="${esc(c.name)}" classname="${esc(suite)}" '
          'time="${c.seconds.toStringAsFixed(3)}"';
      if (c.skipped) {
        b.writeln('    <testcase $attrs>\n      <skipped/>\n    </testcase>');
      } else if (c.result == 'failure' || c.result == 'error') {
        final tag = c.result == 'error' ? 'error' : 'failure';
        final first = c.error
            .split('\n')
            .firstWhere((l) => l.trim().isNotEmpty, orElse: () => c.name);
        b.writeln('    <testcase $attrs>');
        b.writeln(
          '      <$tag message="${esc(first.trim())}">${esc('${c.error}\n${c.stack}').trim()}</$tag>',
        );
        b.writeln('    </testcase>');
      } else {
        b.writeln('    <testcase $attrs/>');
      }
    }
    b.writeln('  </testsuite>');
  });
  b.writeln('</testsuites>');

  output.parent.createSync(recursive: true);
  output.writeAsStringSync(b.toString());

  // Report-only verdict line, and the detail a reader of the trace needs.
  stdout.writeln(
    'JUNIT: ${real.length} tests, $failures failed, $errors errors, '
    '$skipped skipped -> ${output.path}',
  );
  for (final c in real.where((c) => c.result != 'success' && !c.skipped)) {
    final first = c.error
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    stdout.writeln(
      'JUNIT-FAIL [${c.suite}] ${c.name}${first.isEmpty ? '' : ' :: ${first.trim()}'}',
    );
  }
}
