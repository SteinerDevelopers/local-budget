import 'dart:convert' show utf8;
import 'dart:io' show Directory;

import 'package:data/data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../version.dart';
import '../budgets/budgets_sheet.dart';
import '../help/help_screen.dart';
import '../import/import_wizard_screen.dart';
import '../ledger/ledger_screen.dart' show monthIndexOf;
import 'base_currency_sheet.dart';
import 'category_list_screen.dart';
import 'integrity_banner.dart';
import 'io.dart';
import 'passphrase_sheet.dart';

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
    this.io = const RealIo(),
    this.restore,
    this.kdfIterations = backupDefaultKdfIterations,
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

  /// File boundary (§3): picked/shared bytes. Injectable for tests.
  final Io io;

  /// Cold-restart restore (main.dart owns the db + widget tree; the sheet
  /// may not touch context once this future starts).
  final Future<void> Function(Backup backup)? restore;

  /// PBKDF2 work for [createBackup] — production default; widget tests
  /// shrink it (§8) so the flow is testable without a 10-second wait.
  final int kdfIterations;

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
            key: const Key('export-csv'),
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Export CSV'),
            subtitle: const Text('Spreadsheet-friendly copy of the ledger'),
            onTap: _exportCsv,
          ),
          ListTile(
            key: const Key('back-up'),
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('Back up now'),
            subtitle: const Text('Passphrase-protected file you own'),
            onTap: _backUpNow,
          ),
          ListTile(
            key: const Key('restore'),
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Restore from backup'),
            onTap: _restoreFromBackup,
          ),
          ListTile(
            key: const Key('import-statement'),
            leading: const Icon(Icons.table_view_outlined),
            title: const Text('Import statement'),
            subtitle: const Text('CSV or OFX from your bank'),
            onTap: _importStatement,
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

  // ---- Data flows (E5 §3) ------------------------------------------------
  //
  // Every flow funnels through the [Io] seam, so widget tests drive the
  // whole path with a fake and no OS dialog is ever on screen. A null
  // db/docsDir/restore (test pumps without a file db) keeps the tile alive
  // with an honest snackbar instead of a dead end.

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs [flow] with the live db + docs dir, or explains why it cannot.
  Future<void> _withStorage(
    String what,
    Future<void> Function(AppDatabase db, Directory docs) flow,
  ) async {
    final db = widget.db, docs = widget.docsDir;
    if (db == null || docs == null) {
      _snack('$what needs the real app.');
      return;
    }
    try {
      await flow(db, docs);
    } on Object catch (e) {
      if (!mounted) return;
      _snack(e is String ? e : 'That did not work: $e');
    }
  }

  Future<void> _exportCsv() => _withStorage('Export', (db, docs) async {
    final accountId = await _pickExportAccount();
    if (accountId == null) return; // cancelled
    final csv = await CsvExport(
      db,
    ).build(accountId: accountId == _allAccounts ? null : accountId);
    final name = CsvExport.fileName(DateTime.now());
    await widget.io.shareFile(bytes: utf8.encode(csv), fileName: name);
    if (!mounted) return;
    _snack('Export ready to share as $name');
  });

  static const _allAccounts = -1;

  /// Bottom sheet, not a dropdown: the ledger already taught this gesture
  /// and the list of accounts can grow past a dropdown's comfort.
  /// Returns an account id, [_allAccounts], or null for cancelled.
  Future<int?> _pickExportAccount() async {
    final accounts = await widget.repository.accounts();
    if (!mounted) return null;
    return showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: Tokens.space2),
        children: [
          for (final a in accounts)
            ListTile(
              key: Key('export-account-${a.id}'),
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(a.name),
              onTap: () => Navigator.of(sheetContext).pop(a.id),
            ),
          ListTile(
            key: const Key('export-account-all'),
            leading: const Icon(Icons.select_all),
            title: const Text('All accounts'),
            onTap: () => Navigator.of(sheetContext).pop(_allAccounts),
          ),
        ],
      ),
    );
  }

  Future<void> _backUpNow() => _withStorage('Backing up', (db, docs) async {
    final passphrase = await showPassphraseSheet(
      context,
      title: 'Choose a passphrase for this backup',
      withConfirm: true,
    );
    if (passphrase == null) return;
    _snack('Encrypting… this takes a moment on purpose.');
    final bytes = await createBackup(
      db: db,
      attachments: AttachmentStore(docs),
      passphrase: passphrase,
      appVersion: appVersion,
      kdfIterations: widget.kdfIterations,
    );
    if (!mounted) return;
    final name =
        'localbudget-backup-${DateTime.now().toIso8601String().substring(0, 10)}.lzb';
    await widget.io.shareFile(bytes: bytes, fileName: name);
    if (!mounted) return;
    _snack('Backup ready to share as $name — store it somewhere you trust.');
  });

  Future<void> _restoreFromBackup() async {
    final db = widget.db, restore = widget.restore;
    if (db == null || restore == null) {
      _snack('Restoring needs the real app.');
      return;
    }
    try {
      final picked = await widget.io.pickFile(extensions: const ['lzb']);
      if (picked == null) return;
      if (!mounted) return;
      final passphrase = await showPassphraseSheet(
        context,
        title: 'Enter this backup’s passphrase',
      );
      if (passphrase == null || !mounted) return;
      final Backup backup;
      try {
        backup = openBackup(
          picked.bytes,
          passphrase: passphrase,
          currentSchemaVersion: db.schemaVersion,
        );
      } on BackupSchemaTooNewException {
        _snack(
          'That backup is from a newer Local Budget — update the app first.',
        );
        return;
      } on BackupFormatException {
        _snack(
          'Could not open that file — wrong passphrase, or it is damaged.',
        );
        return;
      } on BackupPassphraseException {
        // One message for wrong passphrase and damage alike — never hint
        // which, and never offer "try again" against a broken file.
        _snack(
          'Could not open that file — wrong passphrase, or it is damaged.',
        );
        return;
      }
      if (!mounted) return;
      // The one destructive confirm in the app (E5 §1): it must name both
      // things a restore replaces.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const Key('restore-confirm'),
          title: const Text('Replace everything?'),
          content: const Text(
            'Restoring replaces your ledger and all attachment images with '
            'the backup, then restarts the app. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('restore-go'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      // From here the widget tree may vanish at any moment — no context.
      await restore(backup);
    } on Object catch (e) {
      if (!mounted) return;
      _snack('That did not work: $e');
    }
  }

  void _importStatement() {
    final db = widget.db;
    if (db == null) {
      _snack('Importing needs the real app.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImportWizardScreen(
          repository: widget.repository,
          db: db,
          io: widget.io,
        ),
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
