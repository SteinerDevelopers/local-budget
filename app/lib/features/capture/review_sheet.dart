import 'dart:typed_data';

import 'package:capture/capture.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../ledger/day_label.dart';
import '../ledger/view_models.dart';
import '../quickadd/amount_display.dart';
import '../quickadd/amount_pad.dart';
import '../quickadd/category_chips.dart';
import '../quickadd/keypad.dart';
import '../quickadd/quick_add_sheet.dart' show CategoryOption, NewEntry;

/// Everything a reviewed capture hands back to the Ledger, which owns the
/// one write (decision 5: this sheet never touches the database).
@immutable
class CapturedEntry {
  const CapturedEntry({
    required this.entry,
    required this.source,
    this.merchant,
    this.imageBytes,
  });

  final NewEntry entry;
  final TransactionSource source;
  final String? merchant;
  final Uint8List? imageBytes;
}

/// E2 §2.3 — opens the Review sheet at 92 % height. Returns the reviewed
/// entry on Save, null on Discard/back-out; nothing is ever saved here.
Future<CapturedEntry?> showCaptureReview(
  BuildContext context, {
  required TransactionSource source,
  required Uint8List? imageBytes,
  required CapturePipeline pipeline,
  required List<CategoryOption> categories,
  int? warmCategoryId,
  VoidCallback? onManageCategories,
}) => showModalBottomSheet<CapturedEntry>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // §2.3: this screen is *used*, not glanced at — 92 %, not 48 %.
  builder: (_) => SizedBox(
    height: MediaQuery.sizeOf(context).height * 0.92,
    child: CaptureReviewSheet(
      source: source,
      imageBytes: imageBytes,
      pipeline: pipeline,
      categories: categories,
      warmCategoryId: warmCategoryId,
      onManageCategories: onManageCategories,
    ),
  ),
);

class CaptureReviewSheet extends StatefulWidget {
  const CaptureReviewSheet({
    super.key,
    required this.source,
    required this.imageBytes,
    required this.pipeline,
    required this.categories,
    this.warmCategoryId,
    this.onManageCategories,
  });

  final TransactionSource source;
  final Uint8List? imageBytes;
  final CapturePipeline pipeline;
  final List<CategoryOption> categories;
  final int? warmCategoryId;
  final VoidCallback? onManageCategories;

  @override
  State<CaptureReviewSheet> createState() => _CaptureReviewSheetState();
}

class _CaptureReviewSheetState extends State<CaptureReviewSheet> {
  late final AmountPad _pad = AmountPad(currency: widget.pipeline.currency);
  EntryKind _kind = EntryKind.expense;
  int? _categoryId;
  DateTime _day = DateTime.now();
  final TextEditingController _merchant = TextEditingController();

  bool _busy = true;
  ReceiptDraft? _draft;

  // "The highlight clears the moment the user edits the field" (§2.3) —
  // three one-way latches, set by the corresponding user gesture.
  bool _amountEdited = false;
  bool _dateEdited = false;
  bool _merchantEdited = false;

  /// Hardening #20 parity: sheet routes stay hit-testable during the pop
  /// animation; first pop wins.
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.warmCategoryId;
    _run();
  }

  Future<void> _run() async {
    final bytes = widget.imageBytes;
    ReceiptDraft? draft;
    if (bytes != null) {
      draft = widget.source == TransactionSource.pdfImport
          ? await widget.pipeline.fromPdf(bytes)
          : await widget.pipeline.fromImage(bytes);
    }
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _busy = false;
      if (draft == null) return;
      if (draft.total != null) _pad.fill(draft.total!);
      if (draft.date != null) _day = draft.date!;
      if (draft.merchant != null) _merchant.text = draft.merchant!;
    });
  }

  @override
  void dispose() {
    _merchant.dispose();
    super.dispose();
  }

  /// Identical gate to QuickAdd (§2.3 item 2): amount > 0 and category.
  bool get _canSave => _pad.money.isPositive && _categoryId != null;

  // ---- uncertainty (§2.3): low → amber + helper, cleared by any edit;
  // medium → nothing visual (never cry wolf).

  bool get _amountAmber =>
      !_busy &&
      !_amountEdited &&
      _draft?.total != null &&
      _draft!.totalConfidence == FieldConfidence.low;

  bool get _dateAmber =>
      !_busy &&
      !_dateEdited &&
      _draft?.date != null &&
      (_draft!.dateIsAmbiguous ||
          _draft!.dateConfidence == FieldConfidence.low);

  String? get _dateHelper => _draft != null && _draft!.dateIsAmbiguous
      ? 'Day and month are unclear — check.'
      : 'Check date.';

  bool get _merchantAmber =>
      !_busy &&
      !_merchantEdited &&
      _draft?.merchant != null &&
      _draft!.merchantConfidence == FieldConfidence.low;

  bool get _noTotal => !_busy && _draft?.total == null;

  void _save() {
    if (_popped) return;
    _popped = true;
    final merchant = _merchant.text.trim();
    Navigator.pop(
      context,
      CapturedEntry(
        entry: NewEntry(
          kind: _kind,
          categoryId: _categoryId!,
          amount: _pad.money,
          day: _day,
        ),
        source: widget.source,
        merchant: merchant.isEmpty ? null : merchant,
        imageBytes: widget.imageBytes,
      ),
    );
  }

  void _discard() {
    if (_popped) return;
    _popped = true;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Tokens.space4,
          Tokens.space2,
          Tokens.space4,
          Tokens.space4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SourceStrip(
              source: widget.source,
              imageBytes: widget.imageBytes,
              busy: _busy,
              noTotal: _noTotal,
            ),
            const SizedBox(height: Tokens.space2),
            // Fields appear as extraction lands (§2.3, §6: 150 ms fade).
            AnimatedOpacity(
              opacity: _busy ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _amberBox(
                    context,
                    amber: _amountAmber,
                    announce: 'Amount',
                    helper: 'Check amount',
                    child: AmountDisplay(pad: _pad, currency: _pad.currency),
                  ),
                  const SizedBox(height: Tokens.space2),
                  _dateRow(context),
                  const SizedBox(height: Tokens.space2),
                  _merchantField(context),
                ],
              ),
            ),
            Expanded(
              child: AnimatedOpacity(
                opacity: _busy ? 0 : 1,
                duration: const Duration(milliseconds: 150),
                child: Keypad(
                  onDigit: (d) => setState(() {
                    _pad.digit(d);
                    _amountEdited = true;
                  }),
                  onDot: () => setState(() {
                    _pad.dot();
                    _amountEdited = true;
                  }),
                  onBackspace: () => setState(() {
                    _pad.back();
                    _amountEdited = true;
                  }),
                  dotEnabled: widget.pipeline.currency.minorUnits > 0,
                ),
              ),
            ),
            CategoryChips(
              categories: widget.categories,
              selectedId: _categoryId,
              onSelect: (id) => setState(() => _categoryId = id),
              onManage: widget.onManageCategories,
            ),
            const SizedBox(height: Tokens.space2),
            SegmentedButton<EntryKind>(
              segments: const [
                ButtonSegment(value: EntryKind.expense, label: Text('Expense')),
                ButtonSegment(value: EntryKind.income, label: Text('Income')),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: Tokens.space2),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: Tokens.touchMin,
                    child: FilledButton(
                      // M3 renders its own disabled state; same gate as QuickAdd.
                      onPressed: _canSave ? _save : null,
                      child: const Text('Save'),
                    ),
                  ),
                ),
                TextButton(onPressed: _discard, child: const Text('Discard')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// §2.3 uncertainty mechanism: 1.5 dp warning outline + one helper line,
  /// and TalkBack appends "needs checking" while the outline is up
  /// (decision 10 bar).
  Widget _amberBox(
    BuildContext context, {
    required bool amber,
    required String announce,
    required String helper,
    required Widget child,
  }) {
    Widget box = Padding(
      padding: const EdgeInsets.all(Tokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          if (amber)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.space1),
              child: Text(
                helper,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
    if (amber) {
      box = DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Tokens.warning, width: 1.5),
          borderRadius: BorderRadius.circular(Tokens.space2),
        ),
        child: box,
      );
      box = Semantics(label: '$announce — needs checking', child: box);
    }
    return box;
  }

  Widget _dateRow(BuildContext context) {
    final now = DateTime.now();
    Widget row = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => setState(() {
              _day = DateTime(now.year, now.month, now.day);
              _dateEdited = true;
            }),
            child: const Text('Today'),
          ),
          TextButton(
            onPressed: () => setState(() {
              _day = DateTime(now.year, now.month, now.day - 1);
              _dateEdited = true;
            }),
            child: const Text('Yesterday'),
          ),
          TextButton.icon(
            // §2.3: prefilled dates land here; the calendar stays the exit.
            key: const Key('date-calendar'),
            onPressed: _openCalendar,
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(DayLabel.of(_day)),
          ),
        ],
      ),
    );
    if (_dateAmber) {
      row = _amberBox(
        context,
        amber: true,
        announce: 'Date',
        helper: _dateHelper!,
        child: row,
      );
    }
    return row;
  }

  Widget _merchantField(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(Tokens.space2),
      borderSide: _merchantAmber
          ? const BorderSide(color: Tokens.warning, width: 1.5)
          : BorderSide(color: scheme.outlineVariant),
    );
    Widget field = TextField(
      controller: _merchant,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        hintText: 'Store name',
        isDense: true,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: _merchantAmber
              ? const BorderSide(color: Tokens.warning, width: 2)
              : BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      onChanged: (_) {
        if (!_merchantEdited) setState(() => _merchantEdited = true);
      },
    );
    if (_merchantAmber) {
      field = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          Padding(
            padding: const EdgeInsets.only(top: Tokens.space1),
            child: Text(
              'Check merchant',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      );
      field = Semantics(label: 'Merchant — needs checking', child: field);
    }
    return field;
  }

  Future<void> _openCalendar() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _day = picked;
        _dateEdited = true;
      });
    }
  }
}

/// §2.3 item 1: 88 dp strip — thumbnail, badge, processing state. Tap opens
/// the fullscreen viewer (pinch-zoom is M2; tap-to-dismiss now).
class _SourceStrip extends StatelessWidget {
  const _SourceStrip({
    required this.source,
    required this.imageBytes,
    required this.busy,
    required this.noTotal,
  });

  final TransactionSource source;
  final Uint8List? imageBytes;
  final bool busy;
  final bool noTotal;

  String get _badge => switch (source) {
    TransactionSource.pdfImport => 'PDF',
    TransactionSource.screenshotImport => 'Screenshot',
    _ => 'Scan',
  };

  bool get _isPdf => source == TransactionSource.pdfImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 88,
      child: Row(
        children: [
          GestureDetector(
            onTap: imageBytes == null ? null : () => _openViewer(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Tokens.space2),
              child: SizedBox(width: 72, height: 72, child: _thumb(context)),
            ),
          ),
          const SizedBox(width: Tokens.space3),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  // §5 TalkBack: the strip announces badge + progress.
                  label: busy ? '$_badge — processing' : _badge,
                  child: Text(
                    _badge,
                    style: Tokens.labelCaps(
                      context,
                    ).copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: Tokens.space1),
                if (busy)
                  const LinearProgressIndicator() // local work, §offline truth
                else if (noTotal)
                  Text(
                    'No total found — type it in.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumb(BuildContext context) {
    final bytes = imageBytes;
    if (bytes == null) {
      return const ColoredBox(color: Color(0x00000000), child: SizedBox());
    }
    if (_isPdf) {
      // PDF bytes are not an image; page-1 rasterizing is the M2 renderer.
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: Icon(Icons.picture_as_pdf_outlined, size: 36),
        ),
      );
    }
    return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
  }

  void _openViewer(BuildContext context) {
    final bytes = imageBytes;
    if (bytes == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // Tap-to-dismiss is the whole viewer for M1 (§2.3).
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Center(
              child: _isPdf
                  ? const Icon(
                      Icons.picture_as_pdf_outlined,
                      size: 96,
                      color: Colors.white70,
                    )
                  : Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}
