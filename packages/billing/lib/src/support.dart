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

/// Supporter goodwill surface — spec §5 item 5, §7.
library;

/// Region gate for external link-outs. U.S. link-outs are the permitted
/// status-quo (feasibility §3); every other or unknown region hides the
/// affordance in release builds. Broadening this (EU/DMA) is a spec edit
/// first — deliberately not preemptive.
abstract final class SupportPolicy {
  static const _allow = {'US'};

  static bool visible(String? countryCode, {bool debug = false}) =>
      countryCode != null ? _allow.contains(countryCode) : debug;
}

/// Outbound links that grant nothing in-app (store-rule compliance).
abstract final class SupportLinks {
  /// TODO(store): final handle lands with E8 store content (open question 3).
  static const bmc = 'https://buymeacoffee.com/localbudget';
}
