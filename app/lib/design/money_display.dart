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
