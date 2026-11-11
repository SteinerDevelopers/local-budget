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

// BillNotifier's plugin-free half: the notification-tap handoff contract.
// Since the boot moved off the first-frame path (device field test), the
// shell no longer polls pendingOpenRuleId after a known-complete bootstrap —
// assigning onOpen *is* the drain, in either arrival order. These tests
// never bootstrap the plugin (same hermetic rule as bills_tab_test).
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/bills/bill_notifier.dart';

void main() {
  tearDown(() {
    BillNotifier.onOpen = null;
    BillNotifier.pendingOpenRuleId = null;
  });

  test('tap before the handler: queued, drained on install', () {
    BillNotifier.pendingOpenRuleId = 42;
    final opened = <int>[];
    BillNotifier.onOpen = opened.add;
    expect(opened, [42]);
    expect(BillNotifier.pendingOpenRuleId, isNull);
  });

  test('tap after the handler: called directly, nothing queued', () {
    final opened = <int>[];
    BillNotifier.onOpen = opened.add;
    // This is what _openPayload does once the handler exists.
    BillNotifier.onOpen!(7);
    expect(opened, [7]);
    expect(BillNotifier.pendingOpenRuleId, isNull);
  });

  test('a cold restart re-installs the handler and drains again', () {
    // First shell never got to drain (process died mid-boot semantics).
    BillNotifier.pendingOpenRuleId = 9;
    BillNotifier.onOpen = null;
    expect(BillNotifier.pendingOpenRuleId, 9);
    final reopened = <int>[];
    BillNotifier.onOpen = reopened.add;
    expect(reopened, [9]);
    expect(BillNotifier.pendingOpenRuleId, isNull);
  });

  test('installing a null handler never fires and never drops the tap', () {
    BillNotifier.pendingOpenRuleId = 3;
    BillNotifier.onOpen = null;
    expect(BillNotifier.pendingOpenRuleId, 3);
  });

  test('bootstrap ladder escalates — a slow boot gets a widening runway', () {
    // The field failure this pins (SL219A, 2026-11-05): a lone 5 s cap
    // surrendered during a slow cold boot and reminders stayed off until
    // the next launch. The ladder must retry with strictly growing
    // budgets totalling enough runway for the slowest tested phone —
    // asserted as data so no test ever bootstraps the real plugin.
    expect(BillNotifier.bootBudgets.length, greaterThanOrEqualTo(3));
    for (var i = 1; i < BillNotifier.bootBudgets.length; i++) {
      expect(
        BillNotifier.bootBudgets[i].inSeconds,
        greaterThan(BillNotifier.bootBudgets[i - 1].inSeconds),
      );
    }
    final total = BillNotifier.bootBudgets.fold<int>(
      0,
      (s, d) => s + d.inSeconds,
    );
    expect(total, greaterThanOrEqualTo(50));
  });
}
