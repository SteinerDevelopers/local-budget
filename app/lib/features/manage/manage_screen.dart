import 'dart:convert' show utf8;
import 'dart:io' show Directory;

import 'package:billing/billing.dart' show TipService;
import 'package:data/data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../flavor.dart';
import '../../version.dart';
import '../capture/capture_services.dart';
import 'package:local_budget/features/cloud/cloud_backup_screen.dart';
import 'package:local_budget/features/cloud/cloud_hub.dart';
import '../help/help_screen.dart';
import '../import/import_wizard_screen.dart';

import '../support/coffee_sheet.dart';
import '../support/get_pro_page.dart';
import '../support/transfer.dart';
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
    this.capture,
    this.restore,
    this.tips,
    this.transfer,
    this.cloud,
    this.kdfIterations = backupDefaultKdfIterations,
  });

  final LedgerRepository repository;

  /// E5 §6: hosts the *Live FX rates* toggle (default-off, per-device;
  /// opt-in per owner ruling 2026-11-11).
  final FxService? fx;

  /// E5 §7: boot-time integrity report; null or unset ⇒ no banner, ever.
  final ValueListenable<IntegrityReport?>? integrity;

  /// Data-section flows (export/backup/restore) operate on the live db.
  final AppDatabase? db;

  /// Documents dir: attachment store root + the SQLite file's home (§3).
  final Directory? docsDir;

  /// File boundary (§3): picked/shared bytes. Injectable for tests.
  final Io io;

  /// E11 §5 — capture services for the wizard's document row; null hides
  /// the row (the wizard still imports CSV/OFX exactly as before).
  final CaptureServices? capture;

  /// Cold-restart restore (main.dart owns the db + widget tree; the sheet
  /// may not touch context once this future starts).
  final Future<void> Function(Backup backup)? restore;

  /// E6 §5 tips layer; null (host tests, no store) ⇒ the coffee sheet
  /// explains itself, like [restore] does when its services are missing.
  final TipService? tips;

  /// E6 §3 free→paid transfer channel; null off Android.
  final FreeTransfer? transfer;

  /// E7b paid-pack cloud stack (Pro only — the tile below is built under
  /// FeatureFlags.proTrio; free flavors never see a non-null hub anyway).
  final CloudHub? cloud;

  /// PBKDF2 work for [createBackup] — production default; widget tests
  /// shrink it (§8) so the flow is testable without a 10-second wait.
  final int kdfIterations;

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen> {
  String? _base;
  bool _liveFx = true;

  /// E6 §3 (Pro only): the free app's staged snapshot, read once at open.
  /// Hidden — never disabled — when no provider resolves (§6).
  bool _freeVisible = false;
  ({int size, int mtimeMs})? _freeSnap;

  @override
  void initState() {
    super.initState();
    _loadBase();
    _loadLiveFx();
    if (FeatureFlags.proTrio) _checkFree();
  }

  Future<void> _checkFree() async {
    final t = widget.transfer;
    if (t == null) return;
    if (!await t.freeAvailable()) return;
    final meta = await t.snapshotMeta();
    if (!mounted) return;
    setState(() {
      _freeVisible = true;
      _freeSnap = meta;
    });
  }

  /// §3 "freshness, stated honestly": the snapshot may be older than the
  /// ledger, and Pro must say so rather than imply a live tap-through.
  String get _freeSubtitle {
    final snap = _freeSnap;
    if (snap == null) return 'Nothing staged yet in the free app';
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(snap.mtimeMs),
    );
    if (age.inMinutes < 2) return 'Data staged moments ago';
    if (age.inHours < 12) return 'Data staged about ${age.inHours} h ago';
    final day = DateTime.fromMillisecondsSinceEpoch(snap.mtimeMs);
    return 'Data staged on ${day.month}/${day.day}';
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
          // 'Budgets & bills' used to live here — removed 2026-11-06: the
          // bottom nav (Receipts · Bills · Budgets · Goals) is the primary
          // surface and the Expenses stat / Reports still open the sheet.
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
          // E7b §5: the paid-pack entry, pro-only by build-gate — the
          // free flavor never composes this row at all.
          if (FeatureFlags.proTrio && widget.cloud != null)
            ListTile(
              key: const Key('cloud-backups'),
              leading: const Icon(Icons.cloud_sync_outlined),
              title: const Text('Cloud backups'),
              subtitle: const Text('Paid pack — to storage you own (WebDAV)'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CloudBackupScreen(
                    hub: widget.cloud!,
                    db: widget.db,
                    docsDir: widget.docsDir,
                    restore: widget.restore,
                    kdfIterations: widget.kdfIterations,
                  ),
                ),
              ),
            ),
          // E7c §5: the widget trio is discoverable in Settings too — the
          // launcher's own picker is the real entry point, this row points
          // at it. Pro-gated like every other paid-pack surface.
          if (FeatureFlags.proTrio)
            ListTile(
              key: const Key('paid-pack-widgets'),
              leading: const Icon(Icons.widgets_outlined),
              title: const Text('Home-screen widgets'),
              subtitle: const Text('Paid pack — add them from the launcher'),
              onTap: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  key: const Key('paid-pack-widgets-dialog'),
                  title: const Text('Home-screen widgets'),
                  content: const Text(
                    'Long-press an empty spot on the home screen, open the '
                    'widget picker, and add any of Steiner Budget’s three:\n\n'
                    '• Spend this month — taps open Reports\n'
                    '• Envelope left — taps open the budgets sheet; long-press '
                    'the tile to pin one envelope\n'
                    '• Quick scan — straight to receipt capture\n\n'
                    'Tiles refresh a couple of seconds after each change and '
                    'show “—” once the month rolls over.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Got it'),
                    ),
                  ],
                ),
              ),
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
          // E6 §5: Support — the only monetization surface in the app.
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'Support',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ListTile(
            key: const Key('coffee'),
            leading: const Icon(Icons.local_cafe_outlined),
            title: const Text('Buy me a coffee ☕'),
            subtitle: const Text(
              'Tips unlock nothing — they just keep the lights on',
            ),
            onTap: () => showCoffeeSheet(context, tips: widget.tips),
          ),
          if (!FeatureFlags.proTrio)
            ListTile(
              key: const Key('get-pro'),
              leading: const Icon(Icons.workspace_premium_outlined),
              title: const Text('Get Pro →'),
              subtitle: const Text('The same app, plus the power trio'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GetProPage(
                    transfer: widget.transfer,
                    onCopyData: _copyDataToPro,
                  ),
                ),
              ),
            ),
          if (FeatureFlags.proTrio && _freeVisible)
            ListTile(
              key: const Key('transfer-free'),
              leading: const Icon(Icons.import_export_outlined),
              title: const Text('Transfer from free app'),
              subtitle: Text(_freeSubtitle),
              onTap: _transferFromFree,
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
    // #50 (C4): the destination is the user's, not ours. The OS save
    // dialog hands them the pen; a cancelled dialog means nothing happened
    // and the app must say exactly that — the cache copy the share sheet
    // used to leave behind is gone from this flow.
    final saved = await widget.io.saveFile(
      bytes: bytes,
      fileName: name,
      dialogTitle: 'Save your backup',
    );
    if (!mounted) return;
    if (saved == null) {
      _snack('Backup cancelled — nothing was saved.');
      return;
    }
    _snack(
      'Saved $name to the location you picked — only its passphrase '
      'opens it.',
    );
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
          'That backup is from a newer Steiner Budget — update the app first.',
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
          capture: widget.capture,
        ),
      ),
    );
  }

  // ---- Support flows (E6 §3/§5) ------------------------------------------

  /// Free side of the transfer: stage an encrypted snapshot the Pro app's
  /// provider may read (E6 §3). Same envelope as a normal backup — the
  /// passphrase is the compiled-in constant, so neither app prompts.
  Future<void> _copyDataToPro() => _withStorage('Copying your data', (
    db,
    docs,
  ) async {
    final t = widget.transfer;
    if (t == null) {
      _snack('Copying needs the real app.');
      return;
    }
    _snack('Encrypting… this takes a moment on purpose.');
    final bytes = await createBackup(
      db: db,
      attachments: AttachmentStore(docs),
      passphrase: transferPassphrase,
      appVersion: appVersion,
      kdfIterations: widget.kdfIterations,
    );
    await t.stage(bytes);
    if (!mounted) return;
    _snack('Copied. Open Steiner Budget Pro and tap "Transfer from free app".');
  });

  /// Pro side: pull the staged snapshot and hand it to the *same* restore
  /// path a file restore uses — transfer is not a second, sneakier destructive
  /// flow (E6 §3: the confirm stays, restore stays the only one).
  Future<void> _transferFromFree() async {
    final db = widget.db, restore = widget.restore, t = widget.transfer;
    if (db == null || restore == null || t == null) {
      _snack('Transferring needs the real app.');
      return;
    }
    final Backup backup;
    try {
      final bytes = await t.pull();
      if (bytes == null) {
        if (!mounted) return;
        _snack(
          "Couldn't read from the free app. You can still use an exported "
          'backup file.',
        );
        return;
      }
      backup = openBackup(
        bytes,
        passphrase: transferPassphrase,
        currentSchemaVersion: db.schemaVersion,
      );
    } on BackupSchemaTooNewException {
      if (!mounted) return;
      _snack(
        'The free app is newer than this one — update it first, then '
        'stage the copy again.',
      );
      return;
    } on Object {
      // Provider refused, file vanished, container damaged — one honest
      // message, one fallback (§6); never a stack trace, never a retry loop.
      if (!mounted) return;
      _snack(
        "Couldn't read from the free app. You can still use an exported "
        'backup file.',
      );
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('transfer-confirm'),
        title: const Text('Replace everything?'),
        content: const Text(
          'Transferring replaces your ledger and all attachment images with '
          'the copy from the free app, then restarts the app. This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('transfer-go'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // From here the widget tree may vanish at any moment — no context.
    await restore(backup);
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
      Text(
        'Steiner\u2019s Private Budget',
        style: Theme.of(sheetContext).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text(
        'Everything you enter stays on this device. No account, no '
        'cloud, no analytics — uninstalling removes every byte.',
        style: Theme.of(sheetContext).textTheme.bodyMedium,
      ),
      const SizedBox(height: 4),
      Text(
        'Steiner Developers, L.L.C.',
        style: Theme.of(sheetContext).textTheme.bodySmall,
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
