// Steiner Budget — local-first budgeting, https://steinerdevelopers.dev
// Copyright (C) 2026 Steiner Developers, L.L.C.
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import 'dart:async';
import 'dart:math' as math;
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
  TextRenderer? renderer,
  Future<List<String>> Function(String prefix)? merchantLookup,
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
      renderer: renderer,
      merchantLookup: merchantLookup,
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
    this.renderer,
    this.merchantLookup,
  });

  final TransactionSource source;
  final Uint8List? imageBytes;
  final CapturePipeline pipeline;
  final List<CategoryOption> categories;
  final int? warmCategoryId;
  final VoidCallback? onManageCategories;

  /// Page-1 rasterizer for PDFs (§2.3 thumbnail / §3 scanned fallback).
  /// Null keeps the PDF icon placeholder — goldens never load pdfium.
  final TextRenderer? renderer;

  /// E4 §4 merchant autocomplete: local prefix → ranked names (max 3 by
  /// default). Null disables the suggestion chips entirely.
  final Future<List<String>> Function(String prefix)? merchantLookup;

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

  /// Rendered page 1 of a PDF (§2.3 "PDF page 1" thumbnail); null while
  /// pending or when there is no renderer / the rasterizer failed — the
  /// icon placeholder then stands, never a blank box.
  Uint8List? _page1;

  // "The highlight clears the moment the user edits the field" (§2.3) —
  // three one-way latches, set by the corresponding user gesture.
  bool _amountEdited = false;
  bool _dateEdited = false;
  bool _merchantEdited = false;

  // E4 §4: ≤3 chips under the merchant field while the user types. The
  // sequence guard drops out-of-order answers from the local query.
  List<String> _merchantHints = const [];
  int _hintSeq = 0;

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
      final isPdf = widget.source == TransactionSource.pdfImport;
      if (isPdf && widget.renderer != null) {
        // Kick the thumbnail render off first; the strip shows it as soon
        // as it lands, independent of how the OCR draft is doing.
        unawaited(_loadPage1(bytes));
      }
      draft = isPdf
          ? await widget.pipeline.fromPdf(bytes, renderer: widget.renderer)
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
    if (draft?.merchant != null) _fixTailDup(draft!.merchant!);
  }

  /// #44 — a rasterized logo trail can lend the merchant an extra final
  /// character (`Walmart` scanned as `Walmartk`, tester 2026-11-06) and
  /// mint a near-duplicate merchant row. When the ledger already holds the
  /// merchant under the clean spelling, the prefill shows the stored
  /// name instead. The query is the stem (tail dropped); hits run through
  /// the exact one-trailing-character rule, and a field the user already
  /// typed over is never touched.
  void _fixTailDup(String scanned) {
    final lookup = widget.merchantLookup;
    if (lookup == null || scanned.trim().length < 4) return;
    unawaited(
      lookup(scanned.trim().substring(0, scanned.trim().length - 1)).then((
        found,
      ) {
        if (!mounted || _merchantEdited || found.isEmpty) return;
        final fix = correctTailDuplication(scanned, found);
        if (fix == null) return;
        if (_merchant.text.trim().toLowerCase() !=
            scanned.trim().toLowerCase()) {
          return; // the user (or a hint chip) got there first
        }
        setState(() => _merchant.text = fix);
      }),
    );
  }

  @override
  void dispose() {
    _pad.dispose();
    _merchant.dispose();
    super.dispose();
  }

  /// Page-1 raster for the source strip / viewer (§2.3). Failures leave the
  /// icon placeholder in place — never a blank box, never an error dialog.
  Future<void> _loadPage1(Uint8List bytes) async {
    final renderer = widget.renderer;
    if (renderer == null) return;
    try {
      final png = await renderer.renderPage1(bytes);
      if (!mounted) return;
      setState(() => _page1 = png);
    } catch (_) {
      // Icon placeholder stands.
    }
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

  /// E4 §4: refresh the suggestion chips for the typed prefix. Exact
  /// (case-insensitive) matches are dropped — nothing left to complete.
  void _suggest(String prefix) {
    final lookup = widget.merchantLookup;
    final trimmed = prefix.trim();
    final seq = ++_hintSeq;
    if (lookup == null || trimmed.isEmpty) {
      if (_merchantHints.isNotEmpty) setState(() => _merchantHints = const []);
      return;
    }
    unawaited(
      lookup(trimmed).then((found) {
        if (!mounted || seq != _hintSeq) return;
        final lower = trimmed.toLowerCase();
        setState(() {
          _merchantHints = [
            for (final name in found)
              if (name.toLowerCase() != lower) name,
          ];
        });
      }),
    );
  }

  void _useSuggestion(String name) {
    _merchant.text = name;
    _merchantEdited = true;
    setState(() {
      _merchantHints = const [];
      ++_hintSeq; // retire any query still in flight
    });
  }

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
    // Same insets lesson as QuickAdd (device feedback 2026-11-04 pm): a
    // scroll-controlled modal never gets a bottom SafeArea, so this sheet
    // clears the system nav bar itself; landscape moves the pad to its
    // own pane instead of clipping rows against the short axis.
    final size = MediaQuery.sizeOf(context);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Tokens.space4,
          Tokens.space2,
          Tokens.space4,
          Tokens.space4 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: size.width > size.height ? _landscape() : _portrait(),
      ),
    );
  }

  Widget _portrait() {
    // Font-scale escape, QuickAdd pattern (device feedback 2026-11-04):
    // at 2.0× the strip + fields grew past the 92 % sheet and the fixed
    // stack spilled 104 px (CI guard, review_manual_path_test). The
    // growing region scrolls only once text outgrows what the fixed
    // stack was designed for — below that the tree is pixel-for-pixel
    // the goldens' tree (an always-on Flexible shifted the 1.0× keypad
    // and the goldens caught exactly that, pipeline 500). 1.35 sits
    // between the highest scale the fixed stack is proven to hold (1.3,
    // overflow suite) and the first scale measured to spill it (2.0,
    // CI guard): the escape never fires where the old tree already fits.
    final grow = MediaQuery.textScalerOf(context).scale(1) > 1.35;
    final growing = <Widget>[
      _strip(),
      const SizedBox(height: Tokens.space2),
      // Fields appear as extraction lands (§2.3, §6: 150 ms fade).
      _fields(),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (grow)
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: growing,
              ),
            ),
          )
        else
          ...growing,
        Expanded(
          // Same font-scale escape as QuickAdd (2026-11-04): below
          // 4×touch-min the pad scrolls instead of crushing the sheet.
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              child: SizedBox(
                height: math.max(box.maxHeight, 4 * Tokens.touchMin),
                child: _keypad(),
              ),
            ),
          ),
        ),
        _chips(),
        const SizedBox(height: Tokens.space2),
        _kindToggle(),
        const SizedBox(height: Tokens.space2),
        _saveRow(),
      ],
    );
  }

  Widget _landscape() => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        flex: 3,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _strip(),
              const SizedBox(height: Tokens.space2),
              _fields(),
              const SizedBox(height: Tokens.space2),
              _chips(),
              const SizedBox(height: Tokens.space2),
              _kindToggle(),
              const SizedBox(height: Tokens.space2),
              _saveRow(),
            ],
          ),
        ),
      ),
      const SizedBox(width: Tokens.space2),
      Expanded(flex: 2, child: _keypad()),
    ],
  );

  Widget _strip() => _SourceStrip(
    source: widget.source,
    imageBytes: widget.imageBytes,
    busy: _busy,
    noTotal: _noTotal,
    page1: _page1,
  );

  /// Fields appear as extraction lands (§2.3, §6: 150 ms fade).
  Widget _fields() => AnimatedOpacity(
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
  );

  Widget _chips() => CategoryChips(
    categories: widget.categories,
    selectedId: _categoryId,
    onSelect: (id) => setState(() => _categoryId = id),
    onManage: widget.onManageCategories,
  );

  Widget _kindToggle() => SegmentedButton<EntryKind>(
    segments: const [
      ButtonSegment(value: EntryKind.expense, label: Text('Expense')),
      ButtonSegment(value: EntryKind.income, label: Text('Income')),
    ],
    selected: {_kind},
    showSelectedIcon: false,
    onSelectionChanged: (s) => setState(() => _kind = s.first),
  );

  Widget _saveRow() => Row(
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
  );

  Widget _keypad() => AnimatedOpacity(
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
  );

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
      onChanged: (value) {
        if (!_merchantEdited) setState(() => _merchantEdited = true);
        _suggest(value);
      },
    );
    if (_merchantHints.isNotEmpty) {
      // E4 §4: tap fills the exact stored name — no half-typed variants.
      field = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          Padding(
            padding: const EdgeInsets.only(top: Tokens.space1),
            child: Wrap(
              key: const Key('merchant-suggest'),
              spacing: Tokens.space1,
              runSpacing: Tokens.space1,
              children: [
                for (final name in _merchantHints)
                  ActionChip(
                    key: Key('merchant-suggest-$name'),
                    label: Text(name),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _useSuggestion(name),
                  ),
              ],
            ),
          ),
        ],
      );
    }
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
    this.page1,
  });

  final TransactionSource source;
  final Uint8List? imageBytes;
  final bool busy;
  final bool noTotal;

  /// Rasterized PDF page 1 (§2.3); null until the renderer lands — the
  /// icon placeholder then stands.
  final Uint8List? page1;

  String get _badge => switch (source) {
    TransactionSource.pdfImport => 'PDF',
    TransactionSource.screenshotImport => 'Screenshot',
    _ => 'Scan',
  };

  bool get _isPdf => source == TransactionSource.pdfImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      // Grows with the font instead of cutting it off at large scales
      // (device feedback 2026-11-04).
      constraints: const BoxConstraints(minHeight: 88),
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
      // PDF bytes are not an image; the renderer (C5) rasterizes page 1 and
      // it lands here asynchronously. The icon is the placeholder until —
      // and unless — that render succeeds (§2.3, never a blank box).
      final page = page1;
      if (page != null) {
        return Image.memory(page, fit: BoxFit.cover, gaplessPlayback: true);
      }
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
              child: _isPdf && page1 == null
                  ? const Icon(
                      Icons.picture_as_pdf_outlined,
                      size: 96,
                      color: Colors.white70,
                    )
                  : Image.memory(_isPdf ? page1! : bytes, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}
