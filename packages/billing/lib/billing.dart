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

/// E6 monetization v2 (docs/design/e6-monetization.md).
///
/// Pure Dart (testing tier 1). Tips only — the store can never unlock a
/// feature here (§0); the paid tier is a separate SKU gated by
/// `app/lib/flavor.dart`. A test pins the catalog against `unlock` (§8).
library;

export 'src/fake_gateway.dart';
export 'src/gateway.dart';
export 'src/models.dart';
export 'src/support.dart';
export 'src/tip_service.dart';
