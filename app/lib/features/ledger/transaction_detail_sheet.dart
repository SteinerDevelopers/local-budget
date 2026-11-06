import 'dart:io' show File;

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';

import '../../design/money_display.dart';
import '../../design/tokens.dart';
import '../manage/icon_registry.dart';
import 'day_label.dart';

/// E5 §6: the minimal transaction detail — E1 specced it (§2.3) and never
/// shipped it; here it is the one honest home for the manual-rate field a
/// "No rate" row needs. Read-only otherwise (delete is the ledger's Undo
/// path, so this sheet only ever *returns* 'delete'), zero dialogs.
Future<String?> showTransactionDetail(
  BuildContext context, {
  required LedgerRepository repository,
  required LedgerEntryData entry,
  required String baseCode,
  AttachmentStore? attachments,
}) => showModalBottomSheet<String>(
  context: context,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => _Detail(
    repository: repository,
    entry: entry,
    baseCode: baseCode,
    attachments: attachments,
  ),
);

class _Detail extends StatelessWidget {
  const _Detail({
    required this.repository,
    required this.entry,
    required this.baseCode,
    this.attachments,
  });

  final LedgerRepository repository;
  final LedgerEntryData entry;
  final String baseCode;

  /// E2 §4 originals live in this store; null (tests, no-capture builds)
  /// simply renders no thumbnail.
  final AttachmentStore? attachments;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currency = Currency.resolve(entry.currencyCode);
    final isExpense = !entry.isIncome;
    final amount = Money(entry.amountMinor, currency);
    final foreign = currency.code != baseCode;

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Center(
          child: Text(
            MoneyDisplay.signed(amount, isExpense: isExpense),
            style: Tokens.amount(
              context,
            ).copyWith(color: isExpense ? scheme.onSurface : scheme.primary),
          ),
        ),
        if (foreign) ...[
          const SizedBox(height: Tokens.space3),
          if (entry.baseAmountMinor != null && entry.fxRate != null)
            // The snapshot, spelled out — what it became and at what rate.
            Center(
              child: Text(
                '≈ ${Money(entry.baseAmountMinor!, Currency.resolve(baseCode)).format()}'
                '  ·  1 ${currency.code} = ${_rateText(entry.fxRate!)} $baseCode',
                key: const Key('detail-rate-line'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            _ManualRateCard(
              repository: repository,
              entryId: entry.id,
              code: currency.code,
              baseCode: baseCode,
            ),
        ],
        const SizedBox(height: Tokens.space5),
        _Meta(
          icon: ManageIcons.of(entry.categoryIcon, entry.categoryName),
          label: entry.categoryName ?? 'Uncategorized',
        ),
        _Meta(
          icon: Icons.calendar_today_outlined,
          label: DayLabel.of(entry.day),
        ),
        if (entry.note != null && entry.note!.isNotEmpty)
          _Meta(icon: Icons.sticky_note_2_outlined, label: entry.note!),
        // E2 §4: the scanned/photographed original, when the row has one.
        _Attachment(
          store: attachments,
          ref: entry.imageRef,
        ),
        // e12 §5 — itemized lines stored with this row at commit time;
        // the section only exists when the block reconciled.
        _Items(repository: repository, transactionId: entry.id),
        const SizedBox(height: Tokens.space4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('detail-delete'),
            onPressed: () => Navigator.of(context).pop('delete'),
            icon: Icon(Icons.delete_outline, color: scheme.error),
            label: Text(
              'Delete',
              style: TextStyle(color: scheme.error), // undo lives in the row
            ),
          ),
        ),
      ],
    );
  }
}

/// E2 §4: the original receipt saved with this row, rendered from the
/// attachment store; tap opens a full-screen pinch-zoomable viewer.
class _Attachment extends StatelessWidget {
  const _Attachment({required this.store, required this.ref});

  final AttachmentStore? store;
  final String? ref;

  @override
  Widget build(BuildContext context) {
    final s = store, r = ref;
    if (s == null || r == null || !AttachmentStore.isSafeRel(r)) {
      return const SizedBox.shrink();
    }
    final file = s.resolve(r);
    if (!file.existsSync()) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Tokens.space3),
      child: Semantics(
        button: true,
        label: 'Attached receipt photo — tap to view full size',
        child: InkWell(
          key: const Key('detail-attachment'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _PhotoViewer(file: file),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              file,
              key: const Key('detail-attachment-thumb'),
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen viewer for a stored original: black stage, pinch zoom,
/// tap anywhere (or the close button) to leave. The photo never leaves
/// the device — this is a local file read, nothing else.
class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: InteractiveViewer(
                maxScale: 6,
                child: Center(
                  child: Image.file(
                    file,
                    key: const Key('photo-viewer-image'),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  key: const Key('photo-close'),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// e12 §5 — expandable item lines stored under this transaction.
class _Items extends StatelessWidget {
  const _Items({required this.repository, required this.transactionId});

  final LedgerRepository repository;
  final int transactionId;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LineItemRow>>(
    future: repository.lineItemsFor(transactionId),
    builder: (context, snap) {
      final items = snap.data;
      if (items == null || items.isEmpty) return const SizedBox.shrink();
      return ExpansionTile(
        key: const Key('detail-items'),
        tilePadding: EdgeInsets.zero,
        title: Text(
          'Items (${items.length})',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        children: [
          for (final it in items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                (it.quantity ?? 1) > 1
                    ? '${it.name} × ${it.quantity!.toStringAsFixed(0)}'
                    : it.name,
              ),
              trailing: Text(
                MoneyDisplay.signed(
                  Money(
                    it.unitPriceMinor! * (it.quantity ?? 1).toInt(),
                    Currency.resolve(it.currencyCode),
                  ),
                  isExpense: true,
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Tokens.space2),
    child: Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: Tokens.space3),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ],
    ),
  );
}

/// The amber corner of the detail sheet (§6): a row saved while offline has
/// no base snapshot; one honest field fixes it. Save recomputes the snapshot
/// from the stored amount — never from a re-parsed one.
class _ManualRateCard extends StatefulWidget {
  const _ManualRateCard({
    required this.repository,
    required this.entryId,
    required this.code,
    required this.baseCode,
  });

  final LedgerRepository repository;
  final int entryId;
  final String code;
  final String baseCode;

  @override
  State<_ManualRateCard> createState() => _ManualRateCardState();
}

class _ManualRateCardState extends State<_ManualRateCard> {
  final _field = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final rate = double.tryParse(_field.text.trim().replaceAll(',', '.'));
    if (rate == null || !rate.isFinite || rate <= 0) {
      setState(() => _error = 'Enter a positive number');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await widget.repository.setManualRate(id: widget.entryId, fxRate: rate);
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Rate added')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Tokens.warning.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.priority_high_rounded,
                size: 14,
                color: Tokens.warning,
              ),
              const SizedBox(width: Tokens.space1),
              Text(
                'No rate',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: Tokens.warning),
              ),
            ],
          ),
        ),
        const SizedBox(height: Tokens.space2),
        Text(
          'The rate could not be fetched when this was saved, so it has no '
          'base-currency value yet. Add one by hand.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: Tokens.space3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('manual-rate-field'),
                controller: _field,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: '1 ${widget.code} = ? ${widget.baseCode}',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
              ),
            ),
            const SizedBox(width: Tokens.space3),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton(
                key: const Key('manual-rate-save'),
                onPressed: _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 0.920000 → "0.92", 1.0 → "1" — rates are read by humans here.
String _rateText(double rate) {
  var s = rate.toStringAsFixed(6);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}
