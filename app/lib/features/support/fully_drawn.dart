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

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The honest cold-start signal (bench §4.5 follow-up, 2026-11-10).
///
/// The platform's `Displayed` timing stops at the first *frame* — for this
/// app that frame is the ledger's zero-strip, while the month's rows land
/// one stream event later. Android's `Activity.reportFullyDrawn()` exists
/// precisely for that gap: the app says "the content the user came for is
/// on screen" and the system logs a *Fully drawn* line measured from the
/// activity launch. The nightly smoke reads that line; without this call
/// the number would flatter itself.
///
/// One-shot per process by design: the platform honors only the first call
/// per activity anyway (repeat calls are documented no-ops), and a restore
/// re-run must not manufacture a second cold start. On hosts with no
/// Android half — widget tests, any future non-Android build — the
/// MissingPluginException is the documented "nothing to report to".
const MethodChannel _lifecycle = MethodChannel('localbudget/lifecycle');

bool _reported = false;

/// Reports fully-drawn at most once per process. Safe to call from every
/// month page; the guard and the platform's own idempotence do the rest.
Future<void> reportFullyDrawnOnce() async {
  if (_reported) return;
  _reported = true;
  try {
    await _lifecycle.invokeMethod<void>('reportFullyDrawn');
  } on MissingPluginException {
    // No Android half here (tests / other hosts): nothing to report to.
  }
}

/// Test seam only — widget tests share one process, and the one-shot is
/// exactly what a test must prove.
@visibleForTesting
void resetFullyDrawnForTest() => _reported = false;
