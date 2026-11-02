import 'package:core/core.dart';
import 'package:flutter/material.dart';

void main() => runApp(const LocalBudgetApp());

/// Placeholder seed until the Figma design tokens are exported (E0 checklist).
const _seed = Color(0xFF2E7D32);

class LocalBudgetApp extends StatelessWidget {
  const LocalBudgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LocalBudget',
      theme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: _seed,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Smoke of the core wiring: money is integer minor units everywhere,
    // format() is display-only.
    final sample = Money(123456, Currency.resolve('USD'));
    return Scaffold(
      appBar: AppBar(title: const Text('LocalBudget')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('LocalBudget — everything stays on this device'),
            const SizedBox(height: 8),
            Text(
              sample.format(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
      ),
    );
  }
}
