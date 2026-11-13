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

/// E3 budget engine (docs/design/e3-budget-engine.md §3).
///
/// Pure Dart (testing tier 1): integer minor-unit arithmetic, injected
/// `now`, no Flutter, no I/O, no clocks. Repositories map drift rows into
/// these plain inputs and render the statuses back into widgets.
library;

export 'src/engine.dart';
export 'src/materialize.dart';
export 'src/period.dart';
export 'src/recurring.dart';
export 'src/reports.dart';
export 'src/rules.dart';
