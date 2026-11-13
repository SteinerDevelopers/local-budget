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

/// E6 §1: the store tier is an Android product flavor, and this file is the
/// *only* way Dart learns about it (`--dart-define=APP_FLAVOR=pro`, paired
/// with `--flavor pro` by the build). No billing state ever unlocks anything
/// (spec §0 invariant) — E7 features read [FeatureFlags.proTrio], never the
/// purchase layer.
library;

enum AppFlavor { free, pro }

/// Build-time name, `free` unless a build says otherwise. A typo can only
/// ever land the app on `free` — the safe direction.
const String appFlavorName = String.fromEnvironment(
  'APP_FLAVOR',
  defaultValue: 'free',
);

const AppFlavor appFlavor = appFlavorName == 'pro'
    ? AppFlavor.pro
    : AppFlavor.free;

abstract final class FeatureFlags {
  /// The decision-9 trio (cloud sync / widgets / insights): these features
  /// ship *inside the Pro SKU* — this flag is a build fact, not an
  /// entitlement. Const so flavor-gated widgets can use it as a default
  /// argument (E5 §6 live-FX tile, owner ruling 2026-11-13).
  static const bool proTrio = appFlavor == AppFlavor.pro;
}
