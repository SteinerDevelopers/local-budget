import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import 'database.dart';
import 'ledger_repository.dart';

/// E5 §6 — the one network touch in the app, and its offline twin.
///
/// Live FX rates are a per-device toggle (default **off** — installs inert
/// until the user opts in, owner ruling 2026-11-11); turning it off
/// collapses the app to pure offline behaviour without touching the
/// ledger. Rates come from frankfurter.dev (ECB reference rates, no key);
/// the request carries nothing but the two ISO codes. Responses are
/// cached in `settings` under `fx.USD-EUR.2026-11-02` and expire the
/// next day — no historical series is ever kept (zero-telemetry posture).
///
/// [lookup] never throws for operational reasons: any failure (toggle
/// off, offline, timeout, garbage response) yields `null` and the caller
/// saves the row without an FX snapshot + an amber chip. Entry never
/// blocks (global rule).
class FxService {
  FxService(
    this._db, {
    http.Client? client,
    Duration budget = const Duration(seconds: 2),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _budget = budget;

  /// Manage-screen toggle (E5 §6); absent row means OFF — the opt-in
  /// default (owner ruling 2026-11-11: nothing reaches the network that
  /// the user has not explicitly switched on).
  /// Named without the `fx.` cache prefix so the daily purge can't eat it.
  static const settingLiveFxRates = 'live_fx_rates';

  /// The older `.app` host 301s and must not be used (verified 2026-11-02).
  static const endpoint = 'https://api.frankfurter.dev/v1/latest';

  static final RegExp _code = RegExp(r'^[A-Z]{3}$');

  final AppDatabase _db;
  final http.Client _client;
  final bool _ownsClient;
  final Duration _budget;
  late final LedgerRepository _repo = LedgerRepository(_db);

  /// Cache key with the day embedded, which *is* the expiry mechanism:
  /// yesterday's key simply never gets read again (then gets purged).
  static String cacheKey(String base, String quote, DateTime day) =>
      'fx.$base-$quote.${dayKey(day)}';

  static String dayKey(DateTime day) {
    final d = dateFromEpochDay(epochDayOf(day));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-'
        '${two(d.day)}';
  }

  Future<bool> liveRatesEnabled() async =>
      await _repo.setting(settingLiveFxRates) == 'on';

  Future<void> setLiveRatesEnabled(bool enabled) =>
      _repo.setSetting(settingLiveFxRates, enabled ? 'on' : 'off');

  /// Rate converting [base] → [quote] (1 unit of [base] = rate [quote]s),
  /// or `null` when unavailable. Same-day cache first; one fetch with a
  /// hard [budget] otherwise. This is the provider's own direction — the
  /// multiplier a ledger row stamps is its reciprocal; see
  /// [rateForDeviceBase].
  Future<double?> lookup(String base, String quote, {DateTime? day}) async {
    if (!_code.hasMatch(base) || !_code.hasMatch(quote)) return null;
    if (base == quote) return 1.0;
    final now = day ?? DateTime.now();
    final key = cacheKey(base, quote, now);

    final cached = double.tryParse(await _repo.setting(key) ?? '');
    if (cached != null && cached > 0) return cached;
    if (!await liveRatesEnabled()) return null;

    final rate = await _fetch(base, quote);
    if (rate == null) return null;

    await _repo.setSetting(key, rate.toString());
    await _purgeStaleRates(now);
    // Rows are stamped with the reciprocal (base units per 1 quote unit) —
    // what `Money.convertTo` multiplies and the detail sheet reads back as
    // `1 EUR = 1.08 USD` (spec §6, direction pinned).
    await _sweepPending(base, quote, now, 1 / rate);
    return rate;
  }

  /// Convenience for the entry sheet: **base units per 1 unit of [quote]**
  /// — the multiplier for the row's fxRate/baseAmountMinor snapshot
  /// (detail sheet: `1 EUR = 1.08 USD`). The reciprocal of [lookup]'s
  /// provider quote; the cache itself stays in the provider's direction
  /// (`fx.USD-EUR → 0.93`, spec §6). Device base comes from settings
  /// (default USD — same resolution as totals).
  Future<double?> rateForDeviceBase(String quote) async {
    final base = await _repo.baseCurrency() ?? 'USD';
    final perBase = await lookup(base, quote);
    return perBase == null ? null : 1 / perBase;
  }

  Future<double?> _fetch(String base, String quote) async {
    try {
      // Plain GET; the URI carries only the two ISO codes (already
      // regex-validated) — nothing else leaves the device.
      final res = await _client
          .get(Uri.parse('$endpoint?base=$base&symbols=$quote'))
          .timeout(_budget);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map) return null;
      final rates = body['rates'];
      if (rates is! Map) return null;
      final rate = (rates[quote] as num?)?.toDouble();
      return (rate != null && rate > 0 && !rate.isNaN) ? rate : null;
    } on TimeoutException {
      return null;
    } on Exception {
      // Socket errors, bad JSON, unexpected shapes — all the same answer:
      // no rate today; the row still saves without a snapshot.
      return null;
    }
  }

  /// Settings rows older than today are dropped after a successful fetch
  /// so the store never accumulates a rate series. (`LIKE 'fx.%'` only
  /// matches cache keys; the toggle is deliberately named differently.
  /// The day suffix is generated, never user input.)
  Future<void> _purgeStaleRates(DateTime day) => _db.customUpdate(
    "DELETE FROM settings WHERE key LIKE 'fx.%' AND key NOT LIKE ?",
    variables: [Variable<String>('%' + '.${dayKey(day)}')],
    updateKind: UpdateKind.delete,
  );

  /// A successful fetch relabels today's rows that were saved without a
  /// rate (pending-conversion sweep, one statement, opportunistic —
  /// never a spinner, never a timer, spec §6). Only rows in [quote] on a
  /// device whose base is [base]; [rowRate] is the stamping multiplier
  /// (base units per 1 [quote] unit), and the ROUND-half-away matches
  /// `Money.convertTo` for unsigned ledger amounts.
  Future<void> _sweepPending(
    String base,
    String quote,
    DateTime day,
    double rowRate,
  ) async {
    if ((await _repo.baseCurrency() ?? 'USD') != base) return;
    await _db.customUpdate(
      'UPDATE transactions '
      'SET fx_rate = ?, base_amount_minor = CAST(ROUND(amount_minor * ?) AS INTEGER) '
      'WHERE date_days = ? AND fx_rate IS NULL AND base_amount_minor IS NULL '
      'AND currency_code = ?',
      variables: [
        Variable<double>(rowRate),
        Variable<double>(rowRate),
        Variable<int>(epochDayOf(day)),
        Variable<String>(quote),
      ],
      updateKind: UpdateKind.update,
    );
  }

  void close() {
    // Only clients we created ourselves; injected clients belong to the
    // caller (tests hand in a MockClient they may reuse).
    if (_ownsClient) _client.close();
  }
}
