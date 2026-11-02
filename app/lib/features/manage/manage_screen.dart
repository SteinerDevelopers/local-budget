import 'package:data/data.dart';
import 'package:flutter/material.dart';

import 'base_currency_sheet.dart';
import 'category_list_screen.dart';

/// Spec §2.4: Manage is a plain list — Categories, Base currency, About &
/// help. No cards, no sections; rows are 64pt touch targets (§3).
class ManageScreen extends StatefulWidget {
  const ManageScreen({super.key, required this.repository});

  final LedgerRepository repository;

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen> {
  String? _base;

  @override
  void initState() {
    super.initState();
    _loadBase();
  }

  Future<void> _loadBase() async {
    final code = await widget.repository.baseCurrency();
    if (mounted) setState(() => _base = code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage')),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Categories'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    CategoryListScreen(repository: widget.repository),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.attach_money),
            title: const Text('Base currency'),
            trailing: Text(
              _base ?? 'USD', // unset ⇒ USD is what the ledger renders
              style: Theme.of(context).textTheme.titleSmall,
            ),
            onTap: () => showBaseCurrencyPicker(
              context,
              repository: widget.repository,
              current: _base ?? 'USD',
            ).then((_) => _loadBase()),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('About & help'),
            onTap: () => showManageHelp(context),
          ),
        ],
      ),
    );
  }
}

/// E1's help surface (§2.4 "About & help"): what the app is, where data
/// lives, and the handful of gestures E1 has. The full help section (§7)
/// grows with later epics; the row is wired from day one.
Future<void> showManageHelp(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (sheetContext) => ListView(
    shrinkWrap: true,
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
    children: [
      Text('Local Budget', style: Theme.of(sheetContext).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        'Everything you enter stays on this device. No account, no '
        'cloud, no analytics — uninstalling removes every byte.',
        style: Theme.of(sheetContext).textTheme.bodyMedium,
      ),
      const SizedBox(height: 20),
      for (final (icon, title, body) in _helpRows)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(sheetContext).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  ),
);

const List<(IconData, String, String)> _helpRows = [
  (
    Icons.add_circle_outline,
    'Add an entry',
    'Tap the + button, type the amount, pick expense or income and a '
        'category, then Save — the row is on the list immediately.',
  ),
  (
    Icons.swap_horiz,
    'Browse months',
    'Swipe left or right across the screen, or use the chevrons beside the '
        'month title.',
  ),
  (
    Icons.delete_outline,
    'Delete with undo',
    'Swipe a row sideways to delete it. The message that appears has Undo '
        'for five seconds.',
  ),
  (
    Icons.settings_outlined,
    'Manage',
    'Rename, add and reorder categories, and choose the currency balances '
        'are shown in.',
  ),
];
