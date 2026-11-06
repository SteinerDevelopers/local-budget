// #35 — Bills tab (design e3 §2.3). Rules are the truth; the notification
// is only a hint (§5). Rows sorted overdue → soonest (the repository's
// nextDue order), overdue date in `error`, due-within-3-days bold.
import 'package:capture/capture.dart';
// Full import: the repository API lives in `extension … on LedgerRepository`
// declarations, which a `show` clause would hide.
import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';

import '../../design/panel_add_bar.dart';
import '../../design/tokens.dart';
import '../capture/capture_intake.dart';
import '../capture/capture_services.dart';
import '../capture/capture_source_sheet.dart';
import '../manage/icon_registry.dart';
import 'bill_detail_sheet.dart';
import 'bill_editor_sheet.dart';
import 'bills_service.dart';

/// The Bills slot inside the budgets sheet (§2.1). Dumb: the parent owns
/// loading; every mutation returns and the parent reloads.
class BillsTab extends StatelessWidget {
  const BillsTab({
    super.key,
    required this.repository,
    required this.bills,
    required this.currency,
    required this.categories,
    required this.onChanged,
    this.capture,
  });

  final LedgerRepository repository;
  final List<BillLine> bills;
  final Currency currency;
  final List<Category> categories;
  final Future<void> Function() onChanged;

  /// E11 follow-up (tester note, 2026-11-05): bills arrive as photos and
  /// PDFs, but the document entry lived only in the import wizard — a
  /// scanned card statement went to the *receipt* scanner instead and came
  /// back as an expense. Where capture exists the Bills tab offers
  /// "Add from a document" directly; where it doesn't the button is
  /// *hidden*, never a dead end.
  final CaptureServices? capture;

  @override
  Widget build(BuildContext context) {
    if (bills.isEmpty) {
      // Owner consistency pass, 2026-11-06: the 2026-11-05 standardization
      // moved the *list* state onto PanelAddBar but left this branch with
      // the old centered CTA stack — so an empty Bills tab no longer
      // matched Receipts (or even a filled Bills tab). Empty now wears the
      // same grammar: centered body, shared add bar pinned at the bottom.
      // The button keeps the `bill-add-empty` key: the affordance moved,
      // the tests and muscle memory did not.
      final scheme = Theme.of(context).colorScheme;
      return Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.event_repeat_outlined,
                      size: 48,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: Tokens.space3),
                    Text('No bills yet', style: Tokens.body(context)),
                    const SizedBox(height: Tokens.space1),
                    Text(
                      'Recurring payments you add here remind you '
                      'the morning they fall due.',
                      style: Tokens.labelCaps(context),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          PanelAddBar(
            primary: TextButton.icon(
              key: const Key('bill-add-empty'),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add bill'),
              onPressed: () => _add(context),
            ),
            secondary: capture == null ? null : _documentButton(compact: true),
          ),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
            itemCount: bills.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, thickness: 0.5),
            itemBuilder: (context, i) =>
                _BillRow(line: bills[i], onTap: () => _open(context, bills[i])),
          ),
        ),
        // Owner standardization, 2026-11-05: the bar moved into the shared
        // PanelAddBar widget — Receipts now wears the exact same affordance.
        PanelAddBar(
          primary: TextButton.icon(
            key: const Key('bill-add'),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Add bill'),
            onPressed: () => _add(context),
          ),
          secondary: capture == null ? null : _documentButton(compact: true),
        ),
      ],
    );
  }

  Widget _documentButton({required bool compact}) => _AddFromDocumentButton(
    key: const Key('bill-add-document'),
    capture: capture!,
    repository: repository,
    currency: currency,
    categories: categories,
    onChanged: onChanged,
    compact: compact,
  );

  Future<void> _add(BuildContext context) async {
    final changed = await showBillEditor(
      context,
      repository: repository,
      currency: currency,
      categories: categories,
    );
    if (changed == true) await onChanged();
  }

  Future<void> _open(BuildContext context, BillLine line) async {
    final result = await showBillDetail(
      context,
      repository: repository,
      line: line,
      categories: categories,
    );
    if (result == _openEditor) {
      if (!context.mounted) return;
      await _edit(context, line);
    } else if (result != null) {
      await onChanged();
    }
  }

  Future<void> _edit(BuildContext context, BillLine line) async {
    final changed = await showBillEditor(
      context,
      repository: repository,
      currency: currency,
      categories: categories,
      line: line,
    );
    if (changed == true) await onChanged();
  }
}

/// Sentinel result telling the parent "detail closed on Edit rule".
const String _openEditor = 'edit';

/// Photo or PDF → [DocumentExtractor] → [BillDraft] → the E4 editor,
/// prefilled and reviewable — the same pipeline the import wizard runs
/// (E11 §5), shortened to the bill route: this tab's whole subject is
/// bills, and a scanned statement is *routed to* the wizard, not
/// silently mis-added. The bill is never written by the document alone.
class _AddFromDocumentButton extends StatefulWidget {
  const _AddFromDocumentButton({
    super.key,
    required this.capture,
    required this.repository,
    required this.currency,
    required this.categories,
    required this.onChanged,
    required this.compact,
  });

  final CaptureServices capture;
  final LedgerRepository repository;
  final Currency currency;
  final List<Category> categories;
  final Future<void> Function() onChanged;
  final bool compact;

  @override
  State<_AddFromDocumentButton> createState() => _AddFromDocumentButtonState();
}

class _AddFromDocumentButtonState extends State<_AddFromDocumentButton> {
  bool _reading = false;

  Future<void> _run() async {
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
      pick = await widget.capture.intake.pick(choice);
    } on Object {
      return; // picker failures are silent-and-retryable (§2.1)
    }
    if (pick == null || !mounted) return;
    setState(() => _reading = true);
    DocumentRead? read;
    try {
      final reader = DocumentExtractor(
        extractor: widget.capture.extractor,
        renderer: widget.capture.renderer,
        scannedPdfPages: widget.capture.scannedPdfPages,
      );
      read = pick.choice == CaptureChoice.pdf
          ? await reader.fromPdf(pick.bytes)
          : await reader.fromImage(pick.bytes);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
    if (!mounted) return;
    void snack(String msg) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
    if (read == null || read.isEmpty) {
      snack('We couldn’t read any text from it — try a closer photo.');
      return;
    }
    switch (DocumentRouter.route(read.lines, currency: widget.currency)) {
      case DocRoute.bill:
        final draft = BillDraft.draft(read.lines, currency: widget.currency);
        final saved = await showBillEditor(
          context,
          repository: widget.repository,
          currency: widget.currency,
          categories: widget.categories,
          prefill: BillPrefill(
            name: draft.payee ?? '',
            amountMinor: draft.amountDue?.minorUnits ?? 0,
            dueDate: draft.dueDate,
            fromDocument: true,
          ),
        );
        if (saved == true) await widget.onChanged();
      case DocRoute.statement:
        snack(
          'That reads like a statement — import it from Manage → Import '
          'statement so you can review every transaction.',
        );
      case DocRoute.other:
        snack('We couldn’t read a bill from it — try a closer photo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      icon: _reading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.document_scanner_outlined, size: 20),
      label: Text(_reading ? 'Reading your document…' : 'Add from a document'),
      onPressed: _reading ? null : _run,
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.line, required this.onTap});

  final BillLine line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color dueColor, FontWeight dueWeight) = switch (line.state) {
      BillDueState.overdue => (scheme.error, FontWeight.w400),
      BillDueState.dueSoon => (scheme.onSurface, FontWeight.w600),
      BillDueState.later => (scheme.onSurfaceVariant, FontWeight.w400),
    };
    return InkWell(
      key: Key('bill-row-${line.rule.id}'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            Icon(
              ManageIcons.of(
                line.category?.icon,
                line.category?.name ?? line.rule.name,
              ),
              size: 24,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: Tokens.space3),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.rule.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body(context),
                  ),
                  Text.rich(
                    TextSpan(
                      children: line.isStale
                          ? [
                              // §3.4: over a year without materializing —
                              // the row asks the question the pass asks.
                              const TextSpan(text: 'Paused? · '),
                              TextSpan(text: line.dueText),
                            ]
                          : [
                              const TextSpan(text: 'Due '),
                              TextSpan(text: line.dueText),
                            ],
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      color: dueColor,
                      fontWeight: dueWeight,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Tokens.space2),
            Text(
              line.amount.format(),
              style: TextStyle(
                fontSize: Tokens.bodySize,
                fontWeight: FontWeight.w500,
                color: line.isOverdue ? scheme.error : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
