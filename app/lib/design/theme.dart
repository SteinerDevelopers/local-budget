import 'package:flutter/material.dart';

import 'tokens.dart';

/// M3 themes from the single spec seed (design doc §3: "Dark mode: same spec,
/// no alternate palette; M3 dark scheme from the seed").
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) => ThemeData(
    colorSchemeSeed: Tokens.seed,
    useMaterial3: true,
    brightness: brightness,
  );
}
