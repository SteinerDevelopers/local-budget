// On-device smoke for the e2e-android stage: builds the APK, installs it on
// the headless emulator, and drives the placeholder shell. Real user-journeys
// land here as screens arrive (E1+); this proves the emulator tier itself.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_budget/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots and renders the local-first shell', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    expect(find.text('LocalBudget'), findsOneWidget);
    expect(
      find.text('LocalBudget — everything stays on this device'),
      findsOneWidget,
    );
    expect(find.text(r'$1,234.56'), findsOneWidget);

    // Extra frame through the real engine (no widget-tree shortcuts): the
    // point is a green build->install->drive->teardown loop on the emulator.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('LocalBudget'), findsOneWidget);
  });
}
