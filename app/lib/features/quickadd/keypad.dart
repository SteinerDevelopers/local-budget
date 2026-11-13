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

import '../../design/tokens.dart';

/// 3×4 custom keypad — 1–9, `.`, 0, ⌫ (design §2.2 item 3: the system
/// keyboard never exists on this screen). Keys are borderless and ≥ touch-min
/// so the pad reads as a surface, not a form.
class Keypad extends StatelessWidget {
  const Keypad({
    super.key,
    required this.onDigit,
    required this.onDot,
    required this.onBackspace,
    this.dotEnabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onDot;
  final VoidCallback onBackspace;
  final bool dotEnabled;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in _rows)
          Expanded(
            child: Row(
              children: [
                for (final d in row)
                  Expanded(
                    child: _Key(
                      key: Key('keypad-$d'),
                      label: d,
                      onPressed: () => onDigit(d),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _Key(
                  key: const Key('keypad-dot'),
                  label: '.',
                  enabled: dotEnabled,
                  onPressed: onDot,
                ),
              ),
              Expanded(
                child: _Key(
                  key: const Key('keypad-0'),
                  label: '0',
                  onPressed: () => onDigit('0'),
                ),
              ),
              Expanded(
                child: _Key(
                  key: const Key('keypad-back'),
                  icon: Icons.backspace_outlined,
                  semanticLabel: 'Delete',
                  onPressed: onBackspace,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    super.key,
    this.label,
    this.icon,
    this.semanticLabel,
    required this.onPressed,
    this.enabled = true,
  });

  final String? label;
  final IconData? icon;
  final String? semanticLabel;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Tokens.touchMin),
          child: Center(
            child: icon != null
                ? Icon(icon, color: scheme.onSurfaceVariant)
                : Text(
                    label!,
                    style: Tokens.amount(context).copyWith(
                      color: enabled ? scheme.onSurface : scheme.outline,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
