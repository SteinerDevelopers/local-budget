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

// Plain integration-test driver, kept for the one job `flutter test`
// cannot do on this SDK: running a probe at a chosen build mode
// (`flutter test` has no --profile here, while `flutter drive` does —
// measured 2026-11-10). The jank probe is only meaningful as a profile
// build, so it runs through drive:
//
//   flutter drive --profile --flavor free -d <bench-tablet> \
//     --driver integration_test/driver.dart \
//     --target integration_test/jank_probe_test.dart
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
