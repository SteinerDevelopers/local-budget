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

/// Pure-Dart domain core for the budgeting app.
///
/// Everything here is platform-independent and 100 % unit-testable (testing
/// tier 1, feasibility §6.1). No Flutter, no I/O.
library;

export 'src/bill_heuristics.dart';
export 'src/category_hints.dart';
export 'src/currency.dart';
export 'src/dedupe.dart';
export 'src/heuristics.dart';
export 'src/merchant_names.dart';
export 'src/money.dart';
export 'src/ocr_lines.dart';
export 'src/payee_sanity.dart';
export 'src/receipt.dart';
export 'src/widget_state.dart';
