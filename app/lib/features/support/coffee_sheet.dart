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

import 'package:billing/billing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design/tokens.dart';

/// E6 §5 coffee sheet: three chips, one button, one thank-you. The copy is
/// load-bearing — it says out loud that tips unlock nothing (§0 invariant),
/// so nothing here may vary with purchase state beyond the receipt line.
Future<void> showCoffeeSheet(
  BuildContext context, {
  required TipService? tips,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => CoffeeSheet(tips: tips),
  );
}

class CoffeeSheet extends StatefulWidget {
  const CoffeeSheet({super.key, required this.tips});

  /// Null (host tests, goldens, stores without billing) ⇒ the honest
  /// explanation instead of a dead end — the Manage-screen idiom.
  final TipService? tips;

  @override
  State<CoffeeSheet> createState() => _CoffeeSheetState();
}

enum _Phase { loading, unavailable, needsApp, ready, tipping, thanks }

class _CoffeeSheetState extends State<CoffeeSheet> {
  _Phase _phase = _Phase.loading;
  List<BillingProduct> _products = const [];
  String? _selected;
  String _unavailableCopy = '';
  List<String> _receipts = const [];
  bool _bmcVisible = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tips = widget.tips;
    if (tips == null) {
      setState(() => _phase = _Phase.needsApp);
      return;
    }
    try {
      await tips.gateway.connect();
      final products = await tips.catalog();
      final receipts = await tips.tipsAcked();
      // §7: the browser-out row only; the IAP chips are never gated.
      var bmc = false;
      try {
        bmc = SupportPolicy.visible(
          await tips.gateway.accountCountry(),
          debug: kDebugMode,
        );
      } on Object {
        bmc = false;
      }
      if (!mounted) return;
      if (products.isEmpty) {
        setState(() {
          _unavailableCopy = "Tipping isn't available in your store yet.";
          _phase = _Phase.unavailable;
        });
        return;
      }
      setState(() {
        _products = products;
        _selected = products[products.length ~/ 2].id; // the middle coffee
        _receipts = receipts;
        _bmcVisible = bmc;
        _phase = _Phase.ready;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _unavailableCopy = "Can't reach the store right now — try again later.";
        _phase = _Phase.unavailable;
      });
    }
  }

  Future<void> _buy() async {
    final tips = widget.tips;
    final id = _selected;
    if (tips == null || id == null) return;
    setState(() => _phase = _Phase.tipping);
    final result = await tips.tip(id);
    if (!mounted) return;
    switch (result.outcome) {
      case PurchaseOutcome.purchased:
        setState(() {
          _receipts = [..._receipts, id];
          _phase = _Phase.thanks;
        });
      case PurchaseOutcome.pending:
        setState(() => _phase = _Phase.ready);
        _snack('Tip is processing — thank you either way.');
      case PurchaseOutcome.canceled:
        setState(() => _phase = _Phase.ready); // §6: silent
      case PurchaseOutcome.error:
        setState(() => _phase = _Phase.ready);
        _snack("Can't reach the store right now — try again later.");
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openBmc() async {
    // External browser only; the app itself never loads remote content.
    await launchUrl(
      Uri.parse(SupportLinks.bmc),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // The tip/Close row is the last thing this sheet paints — the
      // scroll-controlled modal never insets the nav-bar strip itself
      // (Tokens.sheetBottomInset; 2026-11-04 pm second wave).
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        32 + Tokens.sheetBottomInset(context),
      ),
      child: switch (_phase) {
        _Phase.loading => const Center(
          child: Padding(
            padding: EdgeInsets.all(Tokens.space3),
            child: CircularProgressIndicator(),
          ),
        ),
        _Phase.needsApp => _headline(
          'Tips need the real app.',
          sub: 'The store billing layer is not part of this build.',
        ),
        _Phase.unavailable => _headline(
          "Can't take a tip right now.",
          sub: _unavailableCopy,
        ),
        _Phase.thanks => _headline(
          'Thank you! ☕',
          key: const Key('coffee-thanks'),
          sub:
              'Tips unlock nothing — they just keep the lights on. '
              'Everything you use today stays free.',
          trailing: FilledButton(
            key: const Key('coffee-close'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ),
        _Phase.ready || _Phase.tipping => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titleText('Enjoying Steiner Budget? Buy me a coffee ☕'),
            const SizedBox(height: 4),
            Text(
              'Everything you use today stays free. Tips keep the lights '
              'on — they don\'t unlock anything.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Tokens.space2),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _products)
                  ChoiceChip(
                    key: Key('coffee-chip-${p.id}'),
                    label: Text(p.price),
                    tooltip: p.title,
                    selected: _selected == p.id,
                    onSelected: _phase == _Phase.ready
                        ? (_) => setState(() => _selected = p.id)
                        : null,
                  ),
              ],
            ),
            if (_receipts.isNotEmpty) ...[
              const SizedBox(height: Tokens.space2),
              Text(
                _receipts.length == 1
                    ? 'You bought me a coffee once. Thank you.'
                    : 'You\'ve bought me ${_receipts.length} coffees. '
                          'Thank you.',
                key: const Key('coffee-receipts'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: Tokens.space2),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('coffee-buy'),
                onPressed: _phase == _Phase.ready ? _buy : null,
                icon: _phase == _Phase.tipping
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.local_cafe_outlined),
                label: Text(
                  _phase == _Phase.tipping ? 'Sending…' : 'Buy the coffee',
                ),
              ),
            ),
            if (_bmcVisible)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('coffee-bmc'),
                  onPressed: _openBmc,
                  child: const Text('Or buy me one at buymeacoffee.com'),
                ),
              ),
          ],
        ),
      },
    );
  }

  Widget _headline(
    String title, {
    required String sub,
    Key? key,
    Widget? trailing,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titleText(title, key: key),
        const SizedBox(height: 8),
        Text(sub),
        if (trailing != null) ...[
          const SizedBox(height: Tokens.space2),
          trailing,
        ],
      ],
    );
  }

  Widget _titleText(String title, {Key? key}) {
    return Text(title, key: key, style: Theme.of(context).textTheme.titleLarge);
  }
}
