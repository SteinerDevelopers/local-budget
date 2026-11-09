// E7b §3.1/§3.2/§3.4 — Paid pack → Cloud backups. Destinations (masked
// password), "Back up now" straight into the E5 container pipeline, and a
// version list whose restore hands off to the exact E5 confirm + swap.
// Reached only behind FeatureFlags.proTrio (ManageScreen builds the tile
// under the gate; CI grep-checks every import of this directory).
import 'dart:io' show Directory;
import 'dart:typed_data';

import 'package:data/data.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../version.dart';
import '../manage/passphrase_sheet.dart';
import 'auto_backup.dart' show kAutoFailBadgeAfter;
import 'cloud_config.dart';
import 'cloud_hub.dart';

class CloudBackupScreen extends StatefulWidget {
  const CloudBackupScreen({
    super.key,
    required this.hub,
    this.db,
    this.docsDir,
    this.restore,
    this.kdfIterations = backupDefaultKdfIterations,
    this.buildBackup,
  });

  final CloudHub hub;
  final AppDatabase? db;
  final Directory? docsDir;
  final Future<void> Function(Backup backup)? restore;
  final int kdfIterations;

  /// Test seam for the encrypt step (real one is the E5 createBackup).
  final Future<Uint8List> Function(String passphrase)? buildBackup;

  @override
  State<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

class _CloudBackupScreenState extends State<CloudBackupScreen> {
  late List<CloudDestination> _dests = widget.hub.destinations();

  void _reload() => setState(() => _dests = widget.hub.destinations());

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('cloud-backup-screen'),
      appBar: AppBar(title: const Text('Cloud backups')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('cloud-add'),
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Destination'),
      ),
      body: _dests.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Back up to storage you own — any WebDAV box: a NAS, '
                'Nextcloud, your own server.\n\nFiles are encrypted before '
                'they leave this device; the server only ever stores opaque '
                'containers.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final d in _dests)
                  Column(
                    key: Key('dest-${d.id}'),
                    children: [
                      ListTile(
                        leading: const Icon(Icons.cloud_outlined),
                        title: Text(d.label),
                        // §3.3: the auto line doubles as the quiet badge —
                        // no notifications, ever; this is the only signal.
                        subtitle: Text(
                          '${d.url}\nuser ${d.user} · folder ${d.folder}'
                          '${d.autoBackup ? '\nauto: daily' : ''}'
                          '${d.autoBackup && d.autoFails >= kAutoFailBadgeAfter ? ' — failing (${d.autoFails}×)' : ''}',
                        ),
                        trailing:
                            d.autoBackup && d.autoFails >= kAutoFailBadgeAfter
                            ? Icon(
                                Icons.error_outline,
                                key: Key('auto-fail-${d.id}'),
                                color: Theme.of(context).colorScheme.error,
                              )
                            : (d.autoBackup
                                  ? Icon(
                                      Icons.schedule,
                                      key: Key('auto-on-${d.id}'),
                                    )
                                  : null),
                        onTap: () => _actions(d),
                      ),
                      if (checkWebdavUrl(d.url).needsBanner)
                        Container(
                          key: Key('lan-banner-${d.id}'),
                          color: Theme.of(context).colorScheme.errorContainer,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Plain HTTP on your LAN — reachable only '
                                  'from your own network, but anything on it '
                                  'can see traffic. HTTPS is better.',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Divider(height: 1),
                    ],
                  ),
              ],
            ),
    );
  }

  // ---- actions sheet -------------------------------------------------

  Future<void> _actions(CloudDestination d) =>
      showModalBottomSheet<Future<void> Function(CloudDestination)?>(
        context: context,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (sheetContext) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ListTile(
              key: const Key('cloud-test'),
              leading: const Icon(Icons.network_check),
              title: const Text('Test connection'),
              onTap: () => Navigator.of(sheetContext).pop(_test),
            ),
            ListTile(
              key: const Key('cloud-backup-now'),
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('Back up now'),
              onTap: () => Navigator.of(sheetContext).pop(_backupNow),
            ),
            ListTile(
              // §3.3 — per-destination auto-backup toggle.
              key: const Key('cloud-auto'),
              leading: Icon(
                d.autoBackup ? Icons.event_repeat : Icons.event_repeat_outlined,
              ),
              title: Text(
                d.autoBackup
                    ? 'Automatic backups: on'
                    : 'Back up automatically',
              ),
              subtitle: const Text(
                'Once a day when connected, encrypted with its own key',
              ),
              onTap: () => Navigator.of(sheetContext).pop(_auto),
            ),
            ListTile(
              key: const Key('cloud-versions'),
              leading: const Icon(Icons.history),
              title: const Text('Versions'),
              onTap: () => Navigator.of(sheetContext).pop(_versions),
            ),
            ListTile(
              key: const Key('cloud-edit'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.of(sheetContext).pop(_editAction),
            ),
            ListTile(
              key: const Key('cloud-delete-dest'),
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove destination'),
              onTap: () => Navigator.of(sheetContext).pop(_remove),
            ),
          ],
        ),
      ).then((action) => action?.call(d));

  Future<void> _editAction(CloudDestination d) => _edit(d);

  Future<void> _test(CloudDestination d) async {
    try {
      final t = await widget.hub.targetWith(d);
      await t.ensureCollection(d.folder);
      await t.list(d.folder);
      _snack('Connected — ${d.folder} reachable.');
    } on Object catch (e) {
      _snack(_friendly(e));
    }
  }

  Future<void> _remove(CloudDestination d) async {
    await widget.hub.remove(d);
    _reload();
    _snack(
      'Removed. Your files on the server stay there — they are yours '
      'to delete.',
    );
  }

  String _friendly(Object e) {
    if (e is WebdavException) {
      return '${e.method} failed (${e.statusCode}) — ${e.detail}';
    }
    if (e is WebdavTransportException) {
      return 'Could not reach the server — ${e.cause}';
    }
    return 'That did not work: $e';
  }

  // ---- editor ----------------------------------------------------------

  Future<void> _edit(CloudDestination? existing) async {
    final d = await showModalBottomSheet<CloudDestination>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) =>
          _DestinationEditor(hub: widget.hub, existing: existing),
    );
    if (d != null) {
      await widget.hub.upsert(d);
      _reload();
    }
  }

  // ---- back up now -------------------------------------------------------

  Future<void> _backupNow(CloudDestination d) async {
    final build = widget.buildBackup ?? _realBackup;
    if (widget.buildBackup == null &&
        (widget.db == null || widget.docsDir == null)) {
      _snack('Backing up needs the real app.');
      return;
    }
    // §3.5: say the recovery math out loud before anything is sealed.
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('cloud-backup-confirm'),
        title: Text('Back up to ${d.label}?'),
        content: const Text(
          'The backup is encrypted on this device before upload. If you '
          'lose the passphrase, the backup is unreadable — forever. Same '
          'rule as local backups.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('cloud-backup-go'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Choose passphrase'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final passphrase = await showPassphraseSheet(
      context,
      title: 'Choose a passphrase for this backup',
      withConfirm: true,
    );
    if (passphrase == null) return;
    _snack('Encrypting… this takes a moment on purpose.');
    try {
      final bytes = await build(passphrase);
      final name = widget.hub.nextObjectName();
      final target = await widget.hub.targetWith(d);
      final kept = await putAndPruneVia(
        target,
        folder: d.folder,
        name: name,
        bytes: bytes,
      );
      _snack('Uploaded $name — keeping newest ${kept.length}.');
    } on Object catch (e) {
      _snack(_friendly(e));
    }
  }

  Future<Uint8List> _realBackup(String passphrase) => createBackup(
    db: widget.db!,
    attachments: AttachmentStore(widget.docsDir!),
    passphrase: passphrase,
    appVersion: appVersion,
    kdfIterations: widget.kdfIterations,
  );

  // ---- §3.3 automatic backups ----------------------------------------

  Future<void> _auto(CloudDestination d) async {
    final hub = widget.hub;
    if (d.autoBackup) {
      // Off means *off*: the key is scrubbed BEFORE the intent flips, so no
      // observer can ever see a destination that is off yet still holds its
      // backup key (#51). The half-failure direction this chooses is
      // on-without-a-key — schedules fail quietly through the badge path and
      // re-enrolment fixes it; the reverse (secret alive after 'off') has no
      // such honest recovery.
      await hub.clearBackupKey(d);
      await hub.upsert(d.copyWith(autoBackup: false, autoFails: 0));
      await hub.auto?.sync(
        destinations: hub.destinations(),
        docsDir: widget.docsDir?.path,
      );
      _reload();
      _snack('Automatic backups off — the backup key is deleted here.');
      return;
    }
    // Enrolment is once per destination (§3.3): the same "lose it =
    // unreadable" honesty as a manual backup, with the confirm repeat.
    final key = await showPassphraseSheet(
      context,
      title: 'Passphrase for automatic backups',
      withConfirm: true,
    );
    if (key == null) return;
    await hub.setBackupKey(d, key);
    await hub.upsert(d.copyWith(autoBackup: true, autoFails: 0));
    await hub.auto?.sync(
      destinations: hub.destinations(),
      docsDir: widget.docsDir?.path,
    );
    _reload();
    _snack('Automatic backups on — daily, encrypted on this device.');
  }

  // ---- versions (§3.2 list, §3.4 restore) --------------------------------

  Future<void> _versions(CloudDestination d) async {
    final List<CloudObject> objs;
    try {
      final target = await widget.hub.targetWith(d);
      objs = (await target.list(
        d.folder,
      )).where((o) => isBackupObject(o.name)).toList();
    } on Object catch (e) {
      _snack(_friendly(e));
      return;
    }
    if (!mounted) return;
    final action = await showModalBottomSheet<_VersionAction>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Newest 12 are kept automatically; older days collapse to '
              'their newest backup.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (objs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No backups on this destination yet.'),
            ),
          for (final o in objs)
            ListTile(
              key: Key('version-${o.name}'),
              leading: const Icon(Icons.description_outlined),
              title: Text(_stampLabel(o)),
              subtitle: Text('${(o.size / 1024).ceil()} kB'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('restore-${o.name}'),
                    icon: const Icon(Icons.settings_backup_restore),
                    tooltip: 'Restore',
                    onPressed: () => Navigator.of(
                      sheetContext,
                    ).pop(_VersionAction(o, _VersionChoice.restore)),
                  ),
                  IconButton(
                    key: Key('drop-${o.name}'),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete',
                    onPressed: () => Navigator.of(
                      sheetContext,
                    ).pop(_VersionAction(o, _VersionChoice.delete)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (action == null) return;
    switch (action.choice) {
      case _VersionChoice.delete:
        try {
          final target = await widget.hub.targetWith(d);
          await target.delete(action.object.path);
          _snack('Deleted ${action.object.name}.');
        } on Object catch (e) {
          _snack(_friendly(e));
        }
      case _VersionChoice.restore:
        await _restore(d, action.object);
    }
  }

  String _stampLabel(CloudObject o) {
    final t = parseBackupObjectTime(o.name);
    if (t == null) return o.name;
    final u = t.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)} '
        '${two(u.hour)}:${two(u.minute)} UTC';
  }

  Future<void> _restore(CloudDestination d, CloudObject o) async {
    final db = widget.db, restore = widget.restore;
    if (db == null || restore == null) {
      _snack('Restoring needs the real app.');
      return;
    }
    try {
      final target = await widget.hub.targetWith(d);
      final bytes = await target.get(o.path);
      if (!mounted) return;
      final passphrase = await showPassphraseSheet(
        context,
        title: 'Enter this backup’s passphrase',
      );
      if (passphrase == null || !mounted) return;
      final Backup backup;
      try {
        backup = openBackup(
          bytes,
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
        _snack(
          'Could not open that file — wrong passphrase, or it is damaged.',
        );
        return;
      }
      if (!mounted) return;
      // E5's one destructive confirm, plus the §3.4 "from <destination>"
      // header — cloud restores replace everything, never merge.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const Key('cloud-restore-confirm'),
          title: const Text('Replace everything?'),
          content: Text(
            'From ${d.label}, ${_stampLabel(o)}.\n\n'
            'Restoring replaces your ledger and all attachment images with '
            'the backup, then restarts the app. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('cloud-restore-go'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      // The tree may vanish at any moment from here — no context.
      await restore(backup);
    } on Object catch (e) {
      _snack(_friendly(e));
    }
  }
}

class _VersionAction {
  const _VersionAction(this.object, this.choice);
  final CloudObject object;
  final _VersionChoice choice;
}

enum _VersionChoice { restore, delete }

// ---- editor sheet -----------------------------------------------------

class _DestinationEditor extends StatefulWidget {
  const _DestinationEditor({required this.hub, this.existing});

  final CloudHub hub;
  final CloudDestination? existing;

  @override
  State<_DestinationEditor> createState() => _DestinationEditorState();
}

class _DestinationEditorState extends State<_DestinationEditor> {
  late final TextEditingController _label = TextEditingController(
    text: widget.existing?.label ?? '',
  );
  late final TextEditingController _url = TextEditingController(
    text: widget.existing?.url ?? '',
  );
  late final TextEditingController _user = TextEditingController(
    text: widget.existing?.user ?? '',
  );
  late final TextEditingController _folder = TextEditingController(
    text: widget.existing?.folder ?? 'localbudget',
  );
  final TextEditingController _password = TextEditingController();
  bool _reveal = false;
  String? _urlError;

  @override
  void dispose() {
    _label.dispose();
    _url.dispose();
    _user.dispose();
    _folder.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final check = checkWebdavUrl(_url.text.trim());
    final label = _label.text.trim();
    final user = _user.text.trim();
    final folder = _folder.text.trim().replaceAll('/', '');
    setState(() {
      _urlError = switch (check.status) {
        WebdavUrlStatus.ok => null,
        // §3.1: LAN HTTP is allowed — the list shows its red banner instead.
        WebdavUrlStatus.insecureLan => null,
        WebdavUrlStatus.rejected => check.reason ?? 'Not a usable WebDAV URL',
      };
    });
    if (_urlError != null || label.isEmpty || user.isEmpty) return;
    final hub = widget.hub;
    final dest =
        widget.existing?.copyWith(
          label: label,
          url: _url.text.trim(),
          user: user,
          folder: folder.isEmpty ? 'localbudget' : folder,
        ) ??
        CloudDestination(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
          label: label,
          url: _url.text.trim(),
          user: user,
          folder: folder.isEmpty ? 'localbudget' : folder,
        );
    if (_password.text.isNotEmpty) {
      await hub.setPassword(dest, _password.text);
    }
    if (mounted) Navigator.of(context).pop(dest);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Keyboard OR nav bar, whichever is taller: with no keyboard up,
      // the Save row sat in the 3-button strip (2026-11-04 pm second
      // wave; Tokens.sheetBottomInset).
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: Tokens.sheetBottomInset(context) + 16,
      ),
      // Bounded + scrollable: with the keyboard up, the Save button must
      // stay reachable (and off-screen semantics must not leak into a11y).
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height * 0.9 -
              MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null
                    ? 'New destination'
                    : 'Edit destination',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('dest-label'),
                controller: _label,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              TextField(
                key: const Key('dest-url'),
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'WebDAV URL',
                  helperText: 'https://… or http://192.168.x.x (LAN)',
                  errorText: _urlError,
                ),
              ),
              TextField(
                key: const Key('dest-user'),
                controller: _user,
                decoration: const InputDecoration(labelText: 'User'),
              ),
              TextField(
                key: const Key('dest-password'),
                controller: _password,
                obscureText: !_reveal,
                decoration: InputDecoration(
                  labelText: widget.existing == null
                      ? 'Password or app-password'
                      : 'Stored — leave empty to keep',
                  suffix: IconButton(
                    key: const Key('dest-reveal'),
                    icon: Icon(
                      _reveal ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _reveal = !_reveal),
                  ),
                ),
              ),
              TextField(
                key: const Key('dest-folder'),
                controller: _folder,
                decoration: const InputDecoration(labelText: 'Folder'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('cloud-save'),
                onPressed: _save,
                child: const Text('Save destination'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
