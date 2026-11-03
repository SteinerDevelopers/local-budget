import 'dart:io' show Directory;

import 'package:data/data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../budgets/budgets_sheet.dart';
import '../help/help_screen.dart';
import '../ledger/ledger_screen.dart' show monthIndexOf;
import 'base_currency_sheet.dart';
import 'category_list_screen.dart';
import 'integrity_banner.dart';

/// Spec §2.4: Manage is a plain list — Categories, Base currency, About &
/// help. No cards, no sections; rows are 64pt touch targets (§3). E5 §1
/// adds the Data section under one header — the app's only file-boundary.
class ManageScreen extends StatefulWidget {
  const ManageScreen({
    super.key,
    required this.repository,
    this.fx,
    this.integrity,
    this.db,
    this.docsDir,
  });

  final LedgerRepository repository;

  /// E5 §6: hosts the *Live FX rates* toggle (default-on, per-device).
  final FxService? fx;

  /// E5 §7: boot-time integrity report; null or unset ⇒ no banner, ever.
  final ValueListenable<IntegrityReport?>? integrity;

  /// Data-section flows (export/backup/restore) operate on the live db.
  final AppDatabase? db;

  /// Documents dir: attachment store root + the SQLite file's home (§3).
  final Directory? docsDir;

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen> {
  String? _base;
  bool _liveFx = true;

  @override
  void initState() {
    super.initState();
    _loadBase();
    _loadLiveFx();
  }

  Future<void> _loadBase() async {
    final code = await widget.repository.baseCurrency();
    if (mounted) setState(() => _base = code);
  }

  Future<void> _loadLiveFx() async {
    final fx = widget.fx;
    if (fx == null) return;
    final on = await fx.liveRatesEnabled();
    if (mounted) setState(() => _liveFx = on);
  }

  Future<void> _setLiveFx(bool on) async {
    setState(() => _liveFx = on); // immediate flip — settings catch up
    await widget.fx?.setLiveRatesEnabled(on);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage')),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // §7: the only surface a report ever gets — passive, above the
          // list, never a dialog, gone when there is nothing to say.
          if (widget.integrity case final listenable?)
            IntegrityBanner(listenable: listenable),
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
            leading: const Icon(Icons.savings_outlined),
            title: const Text('Budgets & bills'),
            onTap: () => showBudgetsSheet(
              context,
              repository: widget.repository,
              monthIndex: monthIndexOf(DateTime.now()),
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
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'Data',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Export CSV'),
            subtitle: const Text('Spreadsheet-friendly copy of the ledger'),
            onTap: _todoFlow,
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('Back up now'),
            subtitle: const Text('Passphrase-protected file you own'),
            onTap: _todoFlow,
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Restore from backup'),
            onTap: _todoFlow,
          ),
          ListTile(
            leading: const Icon(Icons.table_view_outlined),
            title: const Text('Import statement'),
            subtitle: const Text('CSV or OFX from your bank'),
            onTap: _todoFlow,
          ),
          if (widget.fx != null)
            SwitchListTile(
              key: const Key('live-fx'),
              secondary: const Icon(Icons.currency_exchange),
              title: const Text('Live FX rates'),
              subtitle: const Text('Fetch a rate once, when it is needed'),
              value: _liveFx,
              onChanged: _setLiveFx,
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

  /// Placeholder until the flows land this same issue — wired tiles beat
  /// dead ends (§2.1); replaced one-for-one as each flow ships.
  void _todoFlow() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('This flow is landing right now.')),
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
      const Divider(height: 24),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.search),
        title: const Text('All help topics'),
        subtitle: const Text('Searchable articles: scanning, highlights, PDFs'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(sheetContext).pop();
          Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const HelpScreen()));
        },
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
