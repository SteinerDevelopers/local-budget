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

import 'package:core/core.dart';

import 'tokens.dart';

/// Display-layer amount assembly (design spec §2.1 + §3).
///
/// Ledger entry amounts are stored **unsigned**; expense/income is the entry's
/// kind, not a negative number — so the sign here is presentation, and it uses
/// U+2212 MINUS SIGN per §3 (`expense-sign`), never the ASCII hyphen that
/// `Money.format()` would emit for a negative value.
abstract final class MoneyDisplay {
  /// Ledger row / hero amount: signed with the entry kind's prefix.
  static String signed(Money amount, {required bool isExpense}) =>
      (isExpense ? Tokens.minus : Tokens.plus) + _abs(amount).format();

  /// Net in the balance strip: no `+` for non-negative, U+2212 when negative.
  static String net(Money net) =>
      net.isNegative ? Tokens.minus + _abs(net).format() : net.format();

  static Money _abs(Money m) => m.isNegative ? -m : m;
}
