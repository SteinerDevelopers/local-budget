// Advisory: run sidecar line dumps (import-samples/*.lines.txt) through
// BillDraft and print the drafted fields. Diagnosis, not a gate.
import 'dart:io';
import 'package:core/core.dart';

void main(List<String> args) {
  final now = DateTime.utc(2026, 11, 5);
  for (final path in args) {
    final lines = File(path)
        .readAsLinesSync()
        .where((l) => !l.startsWith('#') && l.trim().isNotEmpty)
        .map((l) => l.replaceFirst('R|', '').trim())
        .where((l) => l != '[?]')
        .toList();
    final code = path.contains('tallinn') ||
            path.contains('vienna') ||
            path.contains('petersburg') ||
            path.contains('russia') ||
            path.contains('lego') ||
            path.contains('201702')
        ? 'EUR'
        : 'USD';
    final d =
        BillDraft.draft(lines, currency: Currency.resolve(code), now: now);
    print('== ${path.split('/').last}');
    print('   payee=${d.payee} (${d.payeeConfidence.name})'
        ' amount=${d.amountDue?.format()} (${d.amountConfidence.name})'
        ' due=${d.dueDate?.toIso8601String().substring(0, 10)}'
        ' freq=${d.frequency.name}');
  }
}
