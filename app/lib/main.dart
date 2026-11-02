import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'design/theme.dart';
import 'features/capture/capture_services.dart';
import 'features/ledger/ledger_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // One SQLite file in the app's private directory — nothing leaves the
  // device (decision 8: zero collection).
  final dir = await getApplicationDocumentsDirectory();
  final repository = LedgerRepository(
    AppDatabase.openFile('${dir.path}/localbudget.sqlite'),
  );
  // First launch seeds the Cash account + default categories; idempotent.
  await repository.ensureDefaults();
  runApp(LocalBudgetApp(repository: repository));
}

class LocalBudgetApp extends StatelessWidget {
  /// [theme]/[darkTheme]/[themeMode] exist for the §6 golden harness (CI
  /// injects a font-pinned text theme); the app itself runs on AppTheme.
  /// [capture] is injected by tests/goldens with fakes; the real Android
  /// services arrive with issue #28 (null → the capture FAB explains).
  const LocalBudgetApp({
    super.key,
    required this.repository,
    this.capture,
    this.theme,
    this.darkTheme,
    this.themeMode,
  });

  final LedgerRepository repository;
  final CaptureServices? capture;
  final ThemeData? theme;
  final ThemeData? darkTheme;
  final ThemeMode? themeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LocalBudget',
      theme: theme ?? AppTheme.light(),
      darkTheme: darkTheme ?? AppTheme.dark(),
      themeMode: themeMode,
      home: LedgerScreen(repository: repository, capture: capture),
    );
  }
}
