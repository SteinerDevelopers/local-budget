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

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design/tokens.dart';
import 'transfer.dart';

/// E6 §3/§5 — the Get Pro page, free flavor only. No buy button exists
/// here: the paid tier is a separate store product (owner decision 12),
/// so this page explains, deep-links the listing, and stages the data.
class GetProPage extends StatefulWidget {
  const GetProPage({
    super.key,
    required this.transfer,
    required this.onCopyData,
  });

  /// Null ⇒ no transfer channel (non-Android builds/tests); the copy button
  /// still shows and [onCopyData] explains, like every other missing service.
  final FreeTransfer? transfer;

  /// Stages an encrypted snapshot for the installed Pro app to pull
  /// (ManageScreen owns the db + backup pipeline). Snacks its own outcome.
  final Future<void> Function() onCopyData;

  @override
  State<GetProPage> createState() => _GetProPageState();
}

class _GetProPageState extends State<GetProPage> {
  bool _proVisible = false;
  bool _copying = false;

  static const _proId = 'dev.steiner.local_budget.pro';

  @override
  void initState() {
    super.initState();
    _checkPro();
  }

  Future<void> _checkPro() async {
    final visible = await widget.transfer?.proInstalled() ?? false;
    if (mounted) setState(() => _proVisible = visible);
  }

  Future<void> _copy() async {
    setState(() => _copying = true);
    try {
      await widget.onCopyData();
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Future<void> _openStore() async {
    // market: intent first (goes straight into the Play app); https is the
    // honest fallback on devices without Play.
    final market = Uri.parse('market://details?id=$_proId');
    try {
      if (await launchUrl(market, mode: LaunchMode.externalApplication)) {
        return;
      }
    } on Object {
      // fall through to https below
    }
    await launchUrl(
      Uri.parse('https://play.google.com/store/apps/details?id=$_proId'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Steiner Budget Pro')),
      body: ListView(
        padding: const EdgeInsets.all(Tokens.space4),
        children: [
          Text(
            'Steiner Budget Pro — the same app, plus',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            r'$7.99 one-time. A separate app, not an unlock: the free app '
            'stays the complete free app it is today.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Tokens.space3),
          const _TrioCard(
            icon: Icons.cloud_sync_outlined,
            title: 'Personal cloud backup',
            body: 'Your own encrypted bucket, synced on your terms.',
          ),
          const _TrioCard(
            icon: Icons.widgets_outlined,
            title: 'Home-screen widgets',
            body: 'Balance and this month, at a glance.',
          ),
          const _TrioCard(
            icon: Icons.insights_outlined,
            title: 'Advanced analytics',
            body: 'Categories, trends and comparisons over time.',
          ),
          const SizedBox(height: Tokens.space3),
          FilledButton.icon(
            key: const Key('pro-store'),
            onPressed: _openStore,
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Get it on Google Play'),
          ),
          const SizedBox(height: Tokens.space2),
          OutlinedButton.icon(
            key: const Key('pro-copy-data'),
            onPressed: _copying ? null : _copy,
            icon: _copying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.copy_all_outlined),
            label: const Text('Copy my data to Pro'),
          ),
          Text(
            'One tap puts an encrypted copy of your ledger where the Pro '
            'app can read it — on this device only. Open Pro and tap '
            '"Transfer from free app" to finish.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_proVisible)
            Padding(
              key: const Key('pro-installed-note'),
              padding: const EdgeInsets.only(top: Tokens.space2),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: Tokens.space1),
                  const Expanded(
                    child: Text('Pro installed — open it to transfer.'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Tokens.space2),
          Text(
            'Prefer a file? Back up in Steiner Budget and restore that file in '
            'Pro — same data, any path works.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrioCard extends StatelessWidget {
  const _TrioCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: Tokens.space2),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(body),
        trailing: Text(
          'In Pro',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
