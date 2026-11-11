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

import 'package:core/core.dart';

/// The Tier-3 wire contract: what we ask the on-device model for, and how we
/// read its answer back. Kept in the pure `capture` package (not the adapter)
/// so the round-trip is tested hermetically — the device adapter only moves
/// bytes across the channel.
///
/// The reply is treated as untrusted input end to end: a model answer that
/// fails this parse in any way yields `null`, which the pipeline reads as
/// "structured nothing" and the merge rule never applies (decision 5).

const _kMaxLinesChars = 1600;
const _kMaxMerchantChars = 120;

/// Builds the instruction for [parseStructurerJson]. Small models reward a
/// short, absolute spec: one JSON object, three keys, null for unknowns.
String structurerPrompt(List<String> ocrLines) {
  final buf = StringBuffer();
  var used = 0;
  var truncated = false;
  for (final line in ocrLines) {
    if (line.isEmpty) break; // page boundary, same rule as hasTextLayer
    if (used + line.length + 1 > _kMaxLinesChars) {
      truncated = true;
      break;
    }
    buf.writeln(line);
    used += line.length + 1;
  }
  if (truncated) buf.writeln('(truncated)');
  return 'Extract from a payment receipt. Reply with exactly one JSON '
      'object and nothing else:\n'
      '{"merchant": string|null, "date": "YYYY-MM-DD"|null, '
      '"amountCents": integer|null}\n'
      'Rules: date in ISO form; amountCents is the total paid in minor '
      'units (12.49 -> 1249); use null for anything not on the receipt; '
      'no markdown, no commentary.\n'
      'OCR lines:\n$buf';
}

/// Parses a model reply into a draft whose every filled field carries
/// `FieldConfidence.low` — a structurer never claims confidence; the review
/// sheet keeps those fields flagged until the user confirms them (decision
/// 10: no AI branding, honest uncertainty instead).
///
/// Returns `null` when the reply is not a JSON object, names no usable
/// field, or nothing in it parses — never throws.
ReceiptDraft? parseStructurerJson(String raw, {required Currency currency}) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(raw.substring(start, end + 1));
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;

  var merchant = switch (decoded['merchant']) {
    final String s => _clean(s, _kMaxMerchantChars),
    _ => null,
  };
  if (merchant != null && merchant.isEmpty) merchant = null;

  DateTime? date;
  if (decoded['date'] case final String s when s.trim().isNotEmpty) {
    date = DateTime.tryParse(s.trim());
  }

  Money? total;
  switch (decoded['amountCents']) {
    case final int i:
      total = Money(i, currency);
    case final double d when d == d.roundToDouble() && !d.isInfinite:
      total = Money(d.toInt(), currency);
    case final String s:
      if (int.tryParse(s.trim()) case final int i) total = Money(i, currency);
    default:
      break;
  }

  if (merchant == null && date == null && total == null) return null;
  return ReceiptDraft(
    merchant: merchant,
    date: date,
    dateIsAmbiguous: date != null && decoded['dateIsAmbiguous'] == true,
    total: total,
  );
}

String? _clean(String value, int maxLength) {
  var s = value.trim();
  if (s.isEmpty) return null;
  if (s.length > maxLength) s = s.substring(0, maxLength);
  return s;
}
