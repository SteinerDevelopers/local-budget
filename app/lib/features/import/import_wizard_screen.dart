import 'dart:convert';

import 'package:capture/capture.dart';
import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';

import '../../design/money_display.dart';
import '../../design/tokens.dart';
import '../bills/bill_editor_sheet.dart';
import '../capture/capture_intake.dart';
import '../capture/capture_services.dart';
import '../capture/capture_source_sheet.dart';
import '../manage/io.dart';

/// What the wizard is importing (E5 §4; E11 §5 adds documents). The three
/// formats share one Preview and one Done — only how lines get *in* differs.
enum ImportFormat { csv, ofx, document }

/// E5 §4/§5 — the full-screen import wizard (spec: "no new tab"). One route,
/// four visual steps that are really three states + a done panel:
/// Source → Map (CSV only; OFX and documents carry their own mapping) →
/// Preview → Done. Preview is the single shared screen for all formats,
/// which is why the data layer reuses [CsvPreview] for OFX — and, since
/// E11, for statement-routed documents, whose rows commit through
/// [CsvImport.commit] unchanged so the duplicate tuple stays one thing.
class ImportWizardScreen extends StatefulWidget {
  const ImportWizardScreen({
    super.key,
    required this.repository,
    required this.db,
    required this.io,
    this.capture,
  });

  final LedgerRepository repository;
  final AppDatabase db;
  final Io io;

  /// E11 §5 — camera/photo/PDF intake + OCR for the document row. Null on
  /// hosts without capture services: the row is *hidden*, never a dead end.
  final CaptureServices? capture;

  @override
  State<ImportWizardScreen> createState() => _ImportWizardScreenState();
}

class _ImportWizardScreenState extends State<ImportWizardScreen> {
  List<Account> _accounts = const [];
  int? _accountId;

  CsvFileData? _file;
  List<ImportRole> _roles = const [];
  String _dateFormat = csvDateFormats.first;
  bool _debitExpense = true;
  List<String> _profiles = const [];

  CsvPreview? _preview;
  Set<int> _checked = {};
  ImportFormat _format = ImportFormat.csv;
  int? _done;
  String? _doneLabel;
  bool _busy = false;
  // E11 — the document route reads OCR off the main thread while the
  // source panel wears a spinner; a scanned-PDF page-cap is disclosed in
  // the preview via [_docNote].
  bool _reading = false;
  String? _docNote;
  final _profileName = TextEditingController();
  bool _profileSaved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await widget.repository.accounts();
    final fallback = await widget.repository.defaultAccount();
    final profiles = await CsvImport(widget.db).profileNames();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _accountId ??= fallback.id;
      _profiles = profiles;
    });
  }

  @override
  void dispose() {
    _profileName.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Account get _account => _accounts.firstWhere(
    (a) => a.id == _accountId,
    orElse: () => _accounts.first,
  );

  CsvMapping get _mapping => CsvMapping(
    roles: _roles,
    dateFormat: _dateFormat,
    debitMeansExpense: _debitExpense,
  );

  // ---- source ---------------------------------------------------------------

  Future<void> _pick({required bool ofx}) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final picked = await widget.io.pickFile(
      extensions: ofx ? const ['ofx'] : const ['csv', 'txt'],
    );
    if (picked == null || !mounted) return;
    final String text;
    try {
      text = utf8.decode(picked.bytes);
    } on FormatException {
      _snack('That file is not plain text.');
      return;
    }
    if (ofx) {
      await _openOfx(text, accountId);
      return;
    }
    final file = CsvFileData(text);
    if (file.dataRows.isEmpty) {
      _snack('That CSV has no data rows.');
      return;
    }
    final csv = CsvImport(widget.db);
    // Exact header match ⇒ one tap less (spec §4: profiles apply instantly).
    final profile = await csv.profileMatching(file.headerRow);
    if (!mounted) return;
    final mapping = profile?.mapping ?? csv.autoMap(file);
    setState(() {
      _file = file;
      _format = ImportFormat.csv;
      _preview = null;
      _done = null;
      _doneLabel = null;
      _docNote = null;
      _roles = mapping.roles;
      _dateFormat = mapping.dateFormat ?? csvDateFormats.first;
      _debitExpense = mapping.debitMeansExpense;
    });
    if (profile != null) _snack('Profile "${profile.name}" applied');
  }

  Future<void> _openOfx(String text, int accountId) async {
    try {
      final preview = await OfxImport(
        widget.db,
      ).buildPreview(xmlText: text, accountId: accountId);
      if (!mounted) return;
      setState(() {
        _format = ImportFormat.ofx;
        _file = null;
        _preview = preview;
        _done = null;
        _doneLabel = null;
        _docNote = null;
        _checked = {
          for (final r in preview.rows)
            if (!r.duplicate) r.rowIndex,
        };
      });
    } on OfxFormatException catch (e) {
      _snack(e.message);
    }
  }

  // ---- document route (E11 §5) ------------------------------------------------

  /// Photo or PDF → [DocumentExtractor] → [DocumentRouter] → statement
  /// preview, bill editor, or the honest "couldn't read" pointer. Routing
  /// happens here in the app layer — capture stays independent of data,
  /// so the router's verdict is glued to the parsers by whoever owns both.
  Future<void> _pickDocument() async {
    final capture = widget.capture;
    if (capture == null) return;
    final choice = await showCaptureSourceSheet(
      context,
      showScreenshotRow: false,
      title: 'Add from a document',
      subtitle:
          'A bill or a bank statement — you review before anything is saved.',
    );
    if (choice == null || choice == CaptureChoice.screenshot || !mounted) {
      return;
    }
    CapturePick? pick;
    try {
      pick = await capture.intake.pick(choice);
    } on Object {
      // The picker's own failure states are silent-and-retryable, same
      // contract as the receipt flow (§2.1): back at the source panel.
      return;
    }
    if (pick == null || !mounted) return;
    setState(() => _reading = true);
    DocumentRead? read;
    try {
      final reader = DocumentExtractor(
        extractor: capture.extractor,
        renderer: capture.renderer,
        scannedPdfPages: capture.scannedPdfPages,
      );
      read = pick.choice == CaptureChoice.pdf
          ? await reader.fromPdf(pick.bytes)
          : await reader.fromImage(pick.bytes);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
    if (!mounted) return;
    if (read == null || read.isEmpty) {
      _snack('We couldn’t read any text from it — try CSV or OFX instead.');
      return;
    }
    switch (DocumentRouter.route(read.lines, currency: _currency)) {
      case DocRoute.statement:
        await _previewDocument(read);
      case DocRoute.bill:
        await _billFromDocument(read);
      case DocRoute.other:
        _snack(
          'We couldn’t read a bill or a statement from it — '
          'try CSV or OFX instead.',
        );
    }
  }

  /// Statement-routed lines become [StatementRow]s and ride the *same*
  /// Preview and commit path as CSV/OFX (E11 §5) — the duplicate tuple
  /// is shared, nothing about this route bypasses review.
  Future<void> _previewDocument(DocumentRead read) async {
    final accountId = _accountId;
    if (accountId == null || _busy) return;
    final parsed = StatementLines.tryParse(read.lines, currency: _currency);
    final rows = parsed?.rows ?? const <StatementRow>[];
    if (rows.isEmpty) {
      _snack(
        'We couldn’t read reliable dates and amounts from it — '
        'try CSV or OFX instead.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final preview = await CsvImport(
        widget.db,
      ).previewStatement(accountId: accountId, currency: _currency, rows: rows);
      if (!mounted) return;
      setState(() {
        _format = ImportFormat.document;
        _file = null;
        _preview = preview;
        _done = null;
        _doneLabel = null;
        _docNote = read.truncated
            ? 'We read the first ${read.pagesRead} pages of the PDF — '
                  'later pages are not included.'
            : null;
        _checked = {
          for (final r in preview.rows)
            if (!r.duplicate) r.rowIndex,
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Bill-routed lines seed the E4 editor head start (E11 §4): payee,
  /// amount and due date arrive filled, the owner taps Save or backs out —
  /// the bill is never written by the document alone.
  Future<void> _billFromDocument(DocumentRead read) async {
    final draft = BillDraft.draft(read.lines, currency: _currency);
    final cats = await widget.repository.categories();
    if (!mounted) return;
    final saved = await showBillEditor(
      context,
      repository: widget.repository,
      currency: _currency,
      categories: cats,
      prefill: BillPrefill(
        name: draft.payee ?? '',
        amountMinor: draft.amountDue?.minorUnits ?? 0,
        dueDate: draft.dueDate,
        // e12 §1: only an explicit cadence reading preselects the chip —
        // the statistical monthly default (low) must not masquerade as one.
        frequency: draft.frequencyConfidence == FieldConfidence.high
            ? draft.frequency
            : null,
        fromDocument: true,
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      setState(() {
        _file = null;
        _preview = null;
        _done = 1;
        _doneLabel = 'Bill saved.';
      });
    }
    // Backing out leaves the source panel exactly as it was — a document
    // that was refused is not half-imported anything.
  }

  /// Documents carry no currency declaration (§3): they take the target
  /// account's, same as the CSV route.
  Currency get _currency => Currency.resolve(_account.currencyCode);

  // ---- map → preview ----------------------------------------------------------

  Future<void> _buildPreview() async {
    final file = _file, accountId = _accountId;
    if (file == null || accountId == null) return;
    setState(() => _busy = true);
    try {
      final preview = await CsvImport(
        widget.db,
      ).buildPreview(file: file, mapping: _mapping, accountId: accountId);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _checked = {
          for (final r in preview.rows)
            if (!r.duplicate) r.rowIndex,
        };
      });
    } on ArgumentError {
      _snack('Pick a date column and an amount column first.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyProfile(String name) async {
    final profile = await CsvImport(widget.db).loadProfile(name);
    if (profile == null || !mounted) return;
    setState(() {
      _roles = profile.mapping.roles;
      _dateFormat = profile.mapping.dateFormat ?? csvDateFormats.first;
      _debitExpense = profile.mapping.debitMeansExpense;
    });
  }

  // ---- commit -----------------------------------------------------------------

  Future<void> _commit() async {
    final preview = _preview, accountId = _accountId;
    if (preview == null || accountId == null || _busy) return;
    final rows = [
      for (final r in preview.rows)
        if (_checked.contains(r.rowIndex)) r,
    ];
    if (rows.isEmpty) {
      _snack('Select at least one row to import.');
      return;
    }
    setState(() => _busy = true);
    try {
      // Statement-routed documents commit through the CSV branch — same
      // rows, same dedupe tuple, same source stamp (E11 §5).
      final n = _format == ImportFormat.ofx
          ? await OfxImport(widget.db).commit(
              accountId: accountId,
              currency: preview.currency,
              rows: rows,
            )
          : await CsvImport(widget.db).commit(
              accountId: accountId,
              currency: preview.currency,
              rows: rows,
            );
      if (!mounted) return;
      setState(() => _done = n);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveProfile() async {
    final file = _file;
    if (file == null) return;
    final name = _profileName.text.trim();
    if (name.isEmpty) return;
    await CsvImport(
      widget.db,
    ).saveProfile(name: name, file: file, mapping: _mapping);
    if (!mounted) return;
    setState(() => _profileSaved = true);
    _snack('Profile "$name" saved');
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_done != null ? 'Done' : 'Import statement')),
      body: SafeArea(
        child: switch ((_file, _preview, _done)) {
          (_, _, final int n) => _donePanel(n),
          (_, final CsvPreview preview, null) => _previewPanel(preview),
          (final CsvFileData file?, _, null) => _mapPanel(file),
          // The document route reaches Preview only after the read is
          // done; until then the source panel wears the spinner (E2's
          // busy grammar, spec §5 "existing wizard frame").
          (null, null, null) =>
            _reading || _busy ? _readingPanel() : _sourcePanel(),
        },
      ),
    );
  }

  Widget _accountDropdown() {
    if (_accounts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(Tokens.space4),
        child: Text('No accounts yet.'),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: DropdownButtonFormField<int>(
        key: const Key('import-account'),
        initialValue: _accountId,
        decoration: const InputDecoration(labelText: 'Import into account'),
        items: [
          for (final a in _accounts)
            DropdownMenuItem(value: a.id, child: Text(a.name)),
        ],
        onChanged: (id) => setState(() => _accountId = id),
      ),
    );
  }

  Widget _sourcePanel() => ListView(
    padding: const EdgeInsets.only(bottom: Tokens.space5),
    children: [
      _accountDropdown(),
      const SizedBox(height: Tokens.space4),
      ListTile(
        key: const Key('import-pick-csv'),
        leading: const Icon(Icons.table_view_outlined, size: 32),
        title: const Text('CSV file'),
        subtitle: const Text('Spreadsheet export from your bank'),
        onTap: () => _pick(ofx: false),
      ),
      ListTile(
        key: const Key('import-pick-ofx'),
        leading: const Icon(Icons.description_outlined, size: 32),
        title: const Text('OFX statement'),
        subtitle: const Text('Bank-format statement (1.x, XML)'),
        onTap: () => _pick(ofx: true),
      ),
      // E11 §5 — the third source row, hidden (never dead-ended) when
      // this build has no capture services at all.
      if (widget.capture != null)
        ListTile(
          key: const Key('import-pick-document'),
          leading: const Icon(Icons.document_scanner_outlined, size: 32),
          title: const Text('Photo or PDF'),
          subtitle: const Text('Bill or bank statement — read on device'),
          onTap: _pickDocument,
        ),
    ],
  );

  Widget _readingPanel() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(key: Key('import-reading')),
        const SizedBox(height: Tokens.space4),
        Text(
          'Reading your document…',
          key: const Key('import-reading-label'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );

  Widget _mapPanel(CsvFileData file) {
    final headers = file.headerRow;
    if (_roles.length != headers.length) {
      _roles = List.filled(headers.length, ImportRole.ignore);
    }
    return Column(
      children: [
        _accountDropdown(),
        if (_profiles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: Tokens.space2,
              runSpacing: Tokens.space1,
              children: [
                for (final name in _profiles)
                  ActionChip(
                    key: Key('profile-chip-$name'),
                    avatar: const Icon(Icons.bookmark_border, size: 16),
                    label: Text(name),
                    onPressed: () => _applyProfile(name),
                  ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(top: Tokens.space2),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'What is each column?',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (var i = 0; i < headers.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          headers[i],
                          overflow: TextOverflow.ellipsis,
                          style: Tokens.body(context),
                        ),
                      ),
                      const SizedBox(width: Tokens.space3),
                      DropdownButton<ImportRole>(
                        key: Key('role-$i'),
                        value: _roles[i],
                        isDense: true,
                        items: [
                          for (final r in ImportRole.values)
                            DropdownMenuItem(
                              value: r,
                              child: Text(_roleLabel(r)),
                            ),
                        ],
                        onChanged: (role) => setState(() {
                          if (role == null) return;
                          // Roles belong to exactly one column — picking a
                          // used one moves it, never duplicates it.
                          final previous = _roles.indexOf(role);
                          if (previous >= 0 && role != ImportRole.ignore) {
                            _roles[previous] = _roles[i];
                          }
                          _roles[i] = role;
                        }),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: DropdownButtonFormField<String>(
                  key: const Key('import-date-format'),
                  initialValue: _dateFormat,
                  decoration: const InputDecoration(
                    labelText: 'Date format — never guessed',
                  ),
                  items: [
                    for (final f in csvDateFormats)
                      DropdownMenuItem(value: f, child: Text(f)),
                  ],
                  onChanged: (f) =>
                      setState(() => _dateFormat = f ?? csvDateFormats.first),
                ),
              ),
              SwitchListTile(
                key: const Key('import-debit-polarity'),
                title: const Text('Debit means expense'),
                subtitle: const Text('Turn off for cards that flip the sign'),
                value: _debitExpense,
                onChanged: (v) => setState(() => _debitExpense = v),
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Tokens.space4),
            child: FilledButton(
              key: const Key('import-preview-button'),
              onPressed: _busy ? null : _buildPreview,
              child: Text(_busy ? 'Working…' : 'Preview'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewPanel(CsvPreview preview) {
    final mismatch =
        _format == ImportFormat.ofx &&
        preview.currency.code != _account.currencyCode;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${preview.newCount} new'
                  '${preview.duplicateCount > 0 ? ' · ${preview.duplicateCount} already in ledger' : ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (preview.accountRef case final ref?)
                Text('acct $ref', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        if (preview.errors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              '${preview.errors.length} rows skipped — '
              '${(preview.errors.take(2).map((e) => e.reason).toList()).join('; ')}'
              '${preview.errors.length > 2 ? '…' : ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (mismatch)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'This statement is in ${preview.currency.code} but the account '
              'is ${_account.currencyCode} — rows keep the statement currency.',
              key: const Key('import-currency-note'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Tokens.warning),
            ),
          ),
        // E11 §5 — a scanned preview says what was read and how it is
        // matched; truncation is disclosed here, not hidden in a log.
        if (_format == ImportFormat.document)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Scanned rows are checked against what is already in '
              'the account.'
              '${_docNote == null ? '' : ' $_docNote'}',
              key: const Key('import-document-note'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Expanded(
          child: ListView(
            children: [
              for (final row in preview.rows)
                CheckboxListTile(
                  key: Key('import-row-${row.rowIndex}'),
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _checked.contains(row.rowIndex),
                  onChanged: (on) => setState(() {
                    if (on == true) {
                      _checked.add(row.rowIndex);
                    } else {
                      _checked.remove(row.rowIndex);
                    }
                  }),
                  title: Text(
                    row.description ?? row.categoryName ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              '${_iso(row.date)} · '
                              '${MoneyDisplay.signed(Money(row.minor, preview.currency), isExpense: !row.isIncome)}'
                              '${row.duplicate ? ' · already imported' : ''}',
                        ),
                        // e12 §2: an inferred category is said, not smuggled
                        // in — a medium guess keeps its visible "?".
                        if (row.categoryName != null &&
                            row.categoryConfidence != null)
                          TextSpan(
                            text:
                                ' · ${row.categoryName}'
                                '${row.categoryConfidence == FieldConfidence.medium ? '?' : ''}',
                            style: TextStyle(
                              color: row.categoryConfidence ==
                                      FieldConfidence.medium
                                  ? Theme.of(context).colorScheme.tertiary
                                  : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Tokens.space4),
            child: FilledButton(
              key: const Key('import-commit'),
              onPressed: _busy ? null : _commit,
              child: Text('Import ${_checked.length}'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _donePanel(int n) => Center(
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(Tokens.space4),
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: Tokens.space3),
        Text(
          _doneLabel ??
              'Imported $n ${n == 1 ? 'transaction' : 'transactions'}',
          key: const Key('import-done'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (_format == ImportFormat.csv && !_profileSaved && _file != null) ...[
          const SizedBox(height: Tokens.space5),
          TextField(
            key: const Key('profile-name-field'),
            controller: _profileName,
            decoration: const InputDecoration(
              labelText: 'Remember this mapping — name it (e.g. My bank)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: Tokens.space3),
          FilledButton.tonal(
            key: const Key('profile-save'),
            onPressed: _saveProfile,
            child: const Text('Save profile'),
          ),
        ],
        const SizedBox(height: Tokens.space5),
        FilledButton(
          key: const Key('import-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _roleLabel(ImportRole role) => switch (role) {
    ImportRole.date => 'Date',
    ImportRole.description => 'Description',
    ImportRole.amount => 'Amount',
    ImportRole.debit => 'Debit',
    ImportRole.credit => 'Credit',
    ImportRole.category => 'Category',
    ImportRole.note => 'Note',
    ImportRole.ignore => 'Ignore',
  };
}
