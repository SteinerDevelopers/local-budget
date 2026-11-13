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
