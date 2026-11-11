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

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart' show immutable;

/// One row of the capture source sheet (design §2.1). The row IS the choice:
/// the sheet closes and the platform picker opens (§2.1 "one row per tap").
enum CaptureChoice {
  camera('Camera'),
  photos('Photos'),
  pdf('PDF file'),
  screenshot('Recent screenshot');

  const CaptureChoice(this.label);
  final String label;

  /// Badge shown in the Review sheet's source strip (§2.3 item 1).
  String get badge => switch (this) {
    CaptureChoice.camera || CaptureChoice.photos => 'Scan',
    CaptureChoice.screenshot => 'Screenshot',
    CaptureChoice.pdf => 'PDF',
  };

  /// Wire value for `transactions.source` — stable, never renamed.
  TransactionSource get source => switch (this) {
    CaptureChoice.camera => TransactionSource.cameraScan,
    CaptureChoice.photos => TransactionSource.cameraScan,
    CaptureChoice.pdf => TransactionSource.pdfImport,
    CaptureChoice.screenshot => TransactionSource.screenshotImport,
  };

  /// Extension for AttachmentStore's validated whitelist (§4).
  String get fileExtension => switch (this) {
    CaptureChoice.pdf => 'pdf',
    _ => 'jpg',
  };
}

/// A file the user chose through a platform picker: raw bytes + where they
/// came from. Null from `pick` means the user backed out — no review sheet
/// opens, the ledger stays untouched (decision 5).
@immutable
class CapturePick {
  const CapturePick({required this.bytes, required this.choice});

  final Uint8List bytes;
  final CaptureChoice choice;
}

/// External share / open-with (§5, decision 5): a shared image arrives like
/// the screenshot row, a shared PDF like the PDF row; text and url shares are
/// not receipts and map to null so they are ignored, never half-imported.
/// Pure so the unit tier tests it without the sharing plugin.
CaptureChoice? shareChoiceFor(String? mimeType) => switch (mimeType) {
  'application/pdf' => CaptureChoice.pdf,
  'image/png' || 'image/jpeg' || 'image/jpg' => CaptureChoice.screenshot,
  _ => null,
};

/// Platform intake (design §5): the picker/scanner half of capture, injected
/// into the Ledger. Android implements it over image_picker / ML Kit / SAF
/// (issue #28); tests and goldens drive a fake, which is what makes every
/// review-sheet test hermetic (§7). Returning null = cancelled, always safe.
abstract interface class CaptureIntake {
  /// Android-only convenience row (§2.1); hides the row when false, never a
  /// dead-end tap.
  bool get hasScreenshotRow => false;

  Future<CapturePick?> pick(CaptureChoice choice);
}
