import 'package:flutter/material.dart';

/// Design tokens from `docs/design/e1-manual-ledger.md` §3, mapped 1:1.
/// Decision 10 makes the spec binding: amend the doc first, this file second.
abstract final class Tokens {
  /// §3 `seed` — M3 colorSchemeSeed for both brightnesses.
  static const Color seed = Color(0xFF2E7D32);

  /// §3 spacing scale space-1…5. Row horizontal padding = [space4].
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;

  /// §3 layout pins.
  static const double rowHeight = 64;
  static const double touchMin = 48;
  static const double monthLabelSize = 22; // `month-title`
  static const double amountHeroSize = 40; // `amount-hero`
  static const double bodySize = 16; // `body`
  static const double labelCapsSize = 12; // `label-caps`
  static const double labelCapsTracking = 0.4;

  /// §3 `expense-sign`: U+2212 MINUS SIGN, never the ASCII hyphen.
  static const String minus = '\u2212';
  static const String plus = '+';

  /// The `warning` token E2 §6 points at for low-confidence outlines:
  /// Material's standard warning amber (Yellow 800). It paints 1.5 dp
  /// outlines only — never text — so no contrast rule is touched and the
  /// seed-derived scheme stays the app's only other color source.
  static const Color warning = Color(0xFFF9A825);

  /// §3: all amounts and stat values render with tabular figures.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// §3 `label-caps`: 12 pt, +0.4 tracking, onSurfaceVariant. Casing is
  /// applied by the widget (headers/stats are the only consumers).
  static TextStyle labelCaps(BuildContext context) => TextStyle(
    fontSize: labelCapsSize,
    letterSpacing: labelCapsTracking,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  /// §3 `body`: 16 pt onSurface.
  static TextStyle body(BuildContext context) => TextStyle(
    fontSize: bodySize,
    color: Theme.of(context).colorScheme.onSurface,
  );

  /// §3 amounts: `body` + tabular figures. Income adds `primary` at the
  /// call site (spec colors the value, not the style).
  static TextStyle amount(BuildContext context, {double size = bodySize}) =>
      body(context).copyWith(fontSize: size, fontFeatures: tabular);

  /// §3 `month-title`: 22 pt.
  static TextStyle monthTitle(BuildContext context) => TextStyle(
    fontSize: monthLabelSize,
    color: Theme.of(context).colorScheme.onSurface,
  );
}
