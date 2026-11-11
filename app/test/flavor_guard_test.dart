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
import 'package:local_budget/flavor.dart';

/// The 2026-11-05 field bounce: CI built `--flavor pro` without
/// `--dart-define=APP_FLAVOR=pro`, and every shipped "pro" kit booted the
/// free tier — invisible to any test that ran without the define. This file
/// is the paired guard. It runs twice in CI:
///   * app-test lane (no define) → asserts the default is free, and
///   * inside package-apk-pro (with the define) → asserts the pro kit the
///     very next line builds would actually carry the paid tier.
void main() {
  test('tier comes from APP_FLAVOR only, and pro means the trio', () {
    if (const String.fromEnvironment('APP_FLAVOR') == 'pro') {
      expect(appFlavorName, 'pro');
      expect(appFlavor, AppFlavor.pro);
      expect(FeatureFlags.proTrio, isTrue);
    } else {
      // Absent or typo'd define → free, always (the safe direction).
      expect(appFlavorName, isNot('pro'));
      expect(FeatureFlags.proTrio, isFalse);
    }
  });
}
