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

import 'package:data/data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// E5 §7: the passive integrity surface. A boot-time `DbIntegrity.check`
/// problem report gets *one* quiet amber banner in Manage — no dialog, no
/// blocker, no crash path; the app stays usable exactly as it is. Tapping
/// expands the raw problem lines (selectable for support, no telemetry to
/// send them anywhere).
class IntegrityBanner extends StatelessWidget {
  const IntegrityBanner({super.key, required this.listenable});

  final ValueListenable<IntegrityReport?> listenable;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<IntegrityReport?>(
        valueListenable: listenable,
        builder: (context, report, _) {
          if (report == null || report.ok) return const SizedBox.shrink();
          return _Banner(problems: report.problems);
        },
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.problems});

  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
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
                'Database check',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'The app found problems reading its own database at startup. '
                'Everything still works; a backup you trust can be restored '
                'from the Data section if anything behaves oddly.',
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              for (final line in problems)
                SelectableText(
                  line,
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.space4,
            vertical: Tokens.space3,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.report_problem_outlined,
                size: 20,
                color: Tokens.warning,
              ),
              const SizedBox(width: Tokens.space3),
              Expanded(
                child: Text(
                  'Database check found ${problems.length} '
                  '${problems.length == 1 ? 'problem' : 'problems'} — '
                  'details',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
