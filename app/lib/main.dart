import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'design/theme.dart';
import 'design/tokens.dart';

void main() => runApp(const LocalBudgetApp());

class LocalBudgetApp extends StatelessWidget {
  const LocalBudgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LocalBudget',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Smoke of the core wiring: money is integer minor units everywhere,
    // format() is display-only. Replaced by the real Ledger screen in #17.
    final sample = Money(123456, Currency.resolve('USD'));
    return Scaffold(
      appBar: AppBar(title: const Text('LocalBudget')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('LocalBudget — everything stays on this device'),
            const SizedBox(height: Tokens.space2),
            Text(sample.format(), style: Tokens.amount(context)),
          ],
        ),
      ),
    );
  }
}
