import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/main.dart';

void main() {
  testWidgets('shell builds and core money formatting is wired',
      (tester) async {
    await tester.pumpWidget(const LocalBudgetApp());
    expect(find.text('LocalBudget'), findsOneWidget); // AppBar title
    expect(find.text(r'$1,234.56'), findsOneWidget); // from package:core
  });
}
