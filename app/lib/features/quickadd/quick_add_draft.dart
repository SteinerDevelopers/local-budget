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

import 'dart:convert';

import '../ledger/view_models.dart';

/// Ruling 2 (owner decision sheet, 2026-11-11): "auto-saved drafts"
/// extends to QuickAdd — a half-typed entry must survive process death.
/// This is the wire shape persisted under the `quickadd_draft` settings
/// key; the sheet emits it on every change, the Ledger owns the storage
/// (same division as the warm state — the sheet stays pure UI).
///
/// [amount] is the keypad buffer verbatim ("12.3", "0.") — restore is
/// literal, not via Money, so a mid-typed state comes back exactly as
/// left ("nothing ever lost" taken literally).
class QuickAddDraft {
  const QuickAddDraft({
    required this.amount,
    required this.currencyCode,
    required this.kind,
    required this.day,
    this.categoryId,
    this.note = '',
  });

  final String amount;
  final String currencyCode;
  final EntryKind kind;
  final int? categoryId;
  final DateTime day;
  final String note;

  /// A draft worth restoring: something was typed or written. An empty
  /// one is what a cleared keypad persists — restoring it would be a
  /// cold open with extra steps.
  bool get hasContent => amount.isNotEmpty || note.trim().isNotEmpty;

  String encode() => jsonEncode({
    'amount': amount,
    'currency': currencyCode,
    'kind': kind.name,
    if (categoryId != null) 'category': categoryId,
    'day': '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}',
    if (note.isNotEmpty) 'note': note,
  });

  /// Null on any damage — a draft is convenience state, never precious
  /// state, so a bad read degrades to a cold open instead of throwing
  /// at sheet build.
  static QuickAddDraft? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final amount = j['amount'];
      final currency = j['currency'];
      final day = j['day'];
      if (amount is! String || currency is! String || day is! String) {
        return null;
      }
      final kind = j['kind'];
      final categoryId = j['category'];
      final note = j['note'];
      return QuickAddDraft(
        amount: amount,
        currencyCode: currency,
        kind: kind == 'income' ? EntryKind.income : EntryKind.expense,
        categoryId: categoryId is int ? categoryId : null,
        day: DateTime.parse(day),
        note: note is String ? note : '',
      );
    } on Object {
      return null;
    }
  }
}
