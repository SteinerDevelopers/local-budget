// lcov.info -> cobertura.xml, because this Flutter floor prints lcov
// and GitLab's MR coverage widget speaks cobertura. No dependency, no
// plugin, testable on the host: the converter is a program, not a
// prayer. Also prints the house's COVERAGE TOTAL line — the job's
// `coverage:` regex reads exactly that.
import 'dart:io';

void main(List<String> args) {
  final input = File(args.isNotEmpty ? args[0] : 'coverage/lcov.info');
  final output = File(args.length > 1 ? args[1] : 'coverage/cobertura.xml');
  if (!input.existsSync()) {
    stderr.writeln('no lcov at ${input.path}');
    exit(2);
  }
  final files = <String, Map<int, int>>{}; // path -> line -> hits
  final fileTotals = <String, List<int>>{}; // path -> [LF, LH]
  String? cur;
  for (final line in input.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      cur = line.substring(3).replaceFirst('${Directory.current.path}/', '');
      files.putIfAbsent(cur, () => <int, int>{});
      fileTotals.putIfAbsent(cur, () => <int>[0, 0]);
    } else if (line.startsWith('DA:') && cur != null) {
      final parts = line.substring(3).split(',');
      final n = int.tryParse(parts[0]);
      final hits = int.tryParse(parts[1]);
      if (n != null && hits != null) files[cur]![n] = hits;
    } else if (line.startsWith('LF:') && cur != null) {
      fileTotals[cur]![0] = int.tryParse(line.substring(3)) ?? 0;
    } else if (line.startsWith('LH:') && cur != null) {
      fileTotals[cur]![1] = int.tryParse(line.substring(3)) ?? 0;
    }
  }
  var lf = 0, lh = 0;
  for (final t in fileTotals.values) {
    lf += t[0];
    lh += t[1];
  }
  final rate = lf == 0 ? 0.0 : lh / lf;
  final sb = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="no"?>')
    ..writeln(
      '<coverage line-rate="$rate" branch-rate="0" lines-covered="$lh" '
      'lines-valid="$lf" version="0.1">',
    )
    ..writeln('  <packages>')
    ..writeln('    <package name="app" line-rate="$rate">')
    ..writeln('      <classes>');
  for (final entry in files.entries) {
    final t = fileTotals[entry.key]!;
    final frate = t[0] == 0 ? 0.0 : t[1] / t[0];
    sb
      ..writeln(
        '        <class filename="${_esc(entry.key)}" line-rate="$frate">',
      )
      ..writeln('          <lines>');
    final lines = entry.value.keys.toList()..sort();
    for (final n in lines) {
      sb.writeln(
        '            <line number="$n" hits="${entry.value[n]}" branch="false"/>',
      );
    }
    sb
      ..writeln('          </lines>')
      ..writeln('        </class>');
  }
  sb
    ..writeln('      </classes>')
    ..writeln('    </package>')
    ..writeln('  </packages>')
    ..writeln('</coverage>');
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(sb.toString());
  stdout.writeln('COVERAGE TOTAL: ${(rate * 100).toStringAsFixed(1)}%');
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
