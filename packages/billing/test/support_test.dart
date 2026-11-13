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

import 'package:billing/billing.dart';
import 'package:test/test.dart';

void main() {
  group('SupportPolicy (§7)', () {
    test('US sees the link-out', () {
      expect(SupportPolicy.visible('US'), isTrue);
    });
    test('other countries do not', () {
      expect(SupportPolicy.visible('DE'), isFalse);
      expect(SupportPolicy.visible('US'.toLowerCase()), isFalse);
    });
    test('unknown region: hidden in release, visible in debug', () {
      expect(SupportPolicy.visible(null), isFalse);
      expect(SupportPolicy.visible(null, debug: true), isTrue);
    });
  });

  test('BMC link is https and grants nothing new', () {
    expect(SupportLinks.bmc, startsWith('https://'));
  });
}
