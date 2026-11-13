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

import 'dart:io';

import 'package:billing/billing.dart';
import 'package:data/data.dart';

import 'iap_gateway.dart';
import 'transfer.dart';

/// Dev/test builds may pin the fake gateway with
/// `--dart-define=FAKE_BILLING=true` (drives widget runs and manual QA
/// without Play listing). Release builds never set it; the flag alone can
/// change nothing else (spec §0).
const bool fakeBillingRequested = bool.fromEnvironment('FAKE_BILLING');

/// Wiring for the tips layer, once, in `main()`. Returns null everywhere
/// there is no store (host tests, goldens): the Manage rows then take the
/// same "needs the real app" escape hatch as every other file/store service.
TipService? buildTipService(LedgerRepository repository) {
  final BillingGateway gateway;
  if (fakeBillingRequested) {
    gateway = FakeBillingGateway();
  } else if (Platform.isAndroid) {
    gateway = InAppPurchaseGateway();
  } else {
    return null;
  }
  return TipService(gateway: gateway, kv: _RepoKv(repository));
}

/// Transfer channel wiring (spec §3); null off Android.
FreeTransfer? buildTransfer() =>
    Platform.isAndroid ? const ChannelFreeTransfer() : null;

/// The billing package's two-method settings seam, backed by the ledger's
/// own settings table — receipts live with the data they describe.
class _RepoKv implements SettingsKv {
  _RepoKv(this._repository);

  final LedgerRepository _repository;

  @override
  Future<String?> get(String key) => _repository.setting(key);

  @override
  Future<void> set(String key, String value) =>
      _repository.setSetting(key, value);
}
