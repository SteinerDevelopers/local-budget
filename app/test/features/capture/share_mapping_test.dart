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

import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/capture/capture_intake.dart';

/// Issue #28 — the share/open-with mapping (§5, decision 5). Pure tier on
/// purpose: the plugin adapter itself is never imported by a unit test
/// (§7 hermetic rule), only this contract it obeys.
void main() {
  group('shareChoiceFor', () {
    test('a shared PDF behaves like the PDF row', () {
      expect(shareChoiceFor('application/pdf'), CaptureChoice.pdf);
    });

    test('shared images behave like the screenshot row', () {
      for (final mime in ['image/png', 'image/jpeg', 'image/jpg']) {
        expect(shareChoiceFor(mime), CaptureChoice.screenshot, reason: mime);
      }
    });

    test(
      'text, url and unknown shares are not receipts — ignored, not half-imported',
      () {
        for (final mime in ['text/plain', 'image/gif', 'video/mp4', null]) {
          expect(shareChoiceFor(mime), isNull, reason: '$mime');
        }
      },
    );

    test('the mapped choices carry the review badge + storage extension', () {
      // Shared pdf  → PDF badge, .pdf original.
      expect(shareChoiceFor('application/pdf')!.source.wireName, 'pdf_import');
      expect(shareChoiceFor('application/pdf')!.fileExtension, 'pdf');
      // Shared image → Screenshot badge, .jpg original (png bytes are fine
      // under the image extension the store whitelist knows).
      expect(shareChoiceFor('image/png')!.source.wireName, 'screenshot_import');
    });
  });
}
