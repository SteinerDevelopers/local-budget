import 'dart:async';
import 'dart:ffi';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:test/test.dart';

/// §6 — the one network touch: mocked client only, tests never dial out.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );

  final usd = Currency.resolve('USD');
  final eur = Currency.resolve('EUR');

  late AppDatabase db;
  late LedgerRepository repo;
  late int accountId;
  final now = DateTime.now();
  final today = FxService.dayKey(now);

  /// A [FxService] over a scripted HTTP layer; returns (service, calls).
  (FxService, List<http.Request>) fx(
    Future<http.Response> Function(http.Request) handler, {
    Duration budget = const Duration(seconds: 2),
  }) {
    final calls = <http.Request>[];
    final service = FxService(
      db,
      client: MockClient((req) async {
        calls.add(req);
        return handler(req);
      }),
      budget: budget,
    );
    return (service, calls);
  }

  http.Response ok(String quote, double rate) => http.Response(
    '{"base":"USD","date":"$today","rates":{"$quote":$rate}}',
    200,
  );

  setUp(() async {
    db = AppDatabase.inMemory();
    repo = LedgerRepository(db);
    accountId = await repo.createAccount(name: 'Checking', currencyCode: 'USD');
  });
  tearDown(() => db.close());

  group('keys', () {
    test('cache key embeds the day (which is the expiry)', () {
      final key = FxService.cacheKey('USD', 'EUR', DateTime.utc(2026, 11, 2));
      expect(key, 'fx.USD-EUR.2026-11-02');
      expect(FxService.dayKey(DateTime.utc(2026, 1, 7)), '2026-01-07');
    });
  });

  group('lookup', () {
    test('fetches, caches, and asks the exact spec URL', () async {
      final (service, calls) = fx((_) async => ok('EUR', 0.93));
      addTearDown(service.close);
      // Opt-in arms the network (owner ruling 2026-11-11: default off).
      await service.setLiveRatesEnabled(true);

      expect(await service.lookup('USD', 'EUR'), 0.93);
      expect(calls, hasLength(1));
      expect(
        calls.single.url.toString(),
        'https://api.frankfurter.dev/v1/latest?base=USD&symbols=EUR',
      );
      // Cached under the day-embedded key.
      expect(await repo.setting(FxService.cacheKey('USD', 'EUR', now)), '0.93');
    });

    test('fresh same-day cache answers without any network', () async {
      final (first, _) = fx((_) async => ok('EUR', 0.93));
      addTearDown(first.close);
      await first.setLiveRatesEnabled(true);
      await first.lookup('USD', 'EUR');

      final (second, calls) = fx((_) async => ok('EUR', 9.99));
      addTearDown(second.close);
      expect(await second.lookup('USD', 'EUR'), 0.93); // cached, not refetched
      expect(calls, isEmpty);
    });

    test('toggle off blocks the fetch but keeps the local cache', () async {
      final (warmed, _) = fx((_) async => ok('EUR', 0.93));
      addTearDown(warmed.close);
      await warmed.setLiveRatesEnabled(true);
      await warmed.lookup('USD', 'EUR');
      await warmed.setLiveRatesEnabled(false);

      // Explicit off is stored as such (default when absent is also off).
      expect(await repo.setting(FxService.settingLiveFxRates), 'off');

      final (service, calls) = fx((_) async => ok('EUR', 9.99));
      addTearDown(service.close);
      expect(await service.liveRatesEnabled(), isFalse);
      expect(await service.lookup('USD', 'EUR'), 0.93); // cache is offline-safe
      expect(calls, isEmpty);
    });

    test(
      'default is off with no stored row (opt-in, owner 2026-11-11)',
      () async {
        final (service, calls) = fx((_) async => ok('EUR', 0.9));
        addTearDown(service.close);
        expect(await service.liveRatesEnabled(), isFalse);
        expect(await service.lookup('USD', 'EUR'), isNull);
        expect(calls, isEmpty);
        // Opting in is what arms the network path.
        await service.setLiveRatesEnabled(true);
        expect(await service.liveRatesEnabled(), isTrue);
        expect(await service.lookup('USD', 'EUR'), 0.9);
        expect(calls, hasLength(1));
      },
    );

    test('same currency is 1.0 without touching settings or network', () async {
      final (service, calls) = fx((_) async => ok('EUR', 0.9));
      addTearDown(service.close);
      expect(await service.lookup('USD', 'USD'), 1.0);
      expect(calls, isEmpty);
    });

    test('rateForDeviceBase is the reciprocal the row layer stamps', () async {
      final (service, calls) = fx((_) async => ok('EUR', 0.93));
      addTearDown(service.close);
      await service.setLiveRatesEnabled(true);
      // 1 unit of EUR in USD: the inverse of the provider's own quote.
      expect(await service.rateForDeviceBase('EUR'), closeTo(1 / 0.93, 1e-9));
      // The cache keeps the provider's direction (spec §6).
      expect(await repo.setting(FxService.cacheKey('USD', 'EUR', now)), '0.93');
      // Cached same-day path: reciprocal again, no second fetch.
      expect(await service.rateForDeviceBase('EUR'), closeTo(1 / 0.93, 1e-9));
      expect(calls, hasLength(1));
      // Device base == quote is still an exact 1.0.
      expect(await service.rateForDeviceBase('USD'), 1.0);
    });

    test('malformed codes never leave the device', () async {
      final (service, calls) = fx((_) async => ok('EUR', 0.9));
      addTearDown(service.close);
      expect(await service.lookup('usd', 'EUR'), isNull);
      expect(await service.lookup('USD', 'EURO'), isNull);
      expect(await service.lookup('USD', 'E1R'), isNull);
      expect(calls, isEmpty);
    });

    test('every failure mode answers null and saves nothing', () async {
      final (a, _) = fx((_) async => throw http.ClientException('offline'));
      addTearDown(a.close);
      // Opt-in once: the setting row is shared, b/c/d inherit it.
      await a.setLiveRatesEnabled(true);
      expect(await a.lookup('USD', 'EUR'), isNull);

      final (b, _) = fx((_) async => http.Response('nope', 503));
      addTearDown(b.close);
      expect(await b.lookup('USD', 'EUR'), isNull);

      final (c, _) = fx((_) async => http.Response('{bad json', 200));
      addTearDown(c.close);
      expect(await c.lookup('USD', 'EUR'), isNull);

      final (d, _) = fx((_) async => http.Response('{"rates":{}}', 200));
      addTearDown(d.close);
      expect(await d.lookup('USD', 'EUR'), isNull);

      // Never cached ⇒ nothing to read back.
      expect(await repo.setting(FxService.cacheKey('USD', 'EUR', now)), isNull);
    });

    test('the 2 s budget is real: a slow provider yields null', () async {
      final (service, _) = fx((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return ok('EUR', 0.93);
      }, budget: const Duration(milliseconds: 15));
      addTearDown(service.close);
      await service.setLiveRatesEnabled(true);
      expect(await service.lookup('USD', 'EUR'), isNull);
    });
  });

  group('pending-conversion sweep', () {
    Future<void> seedRow({
      required DateTime date,
      required Money amount,
      double? fxRate,
      String? baseCurrencyCode,
    }) => repo.addTransaction(
      accountId: accountId,
      date: date,
      amount: amount,
      source: TransactionSource.manual,
      baseCurrencyCode: baseCurrencyCode,
      fxRate: fxRate,
    );

    test('a successful fetch relabels today’s null-rate rows only', () async {
      await seedRow(date: now, amount: Money(1000, eur));
      await seedRow(date: now, amount: Money(500, eur)); // also relabelled
      await seedRow(
        date: now.subtract(const Duration(days: 3)),
        amount: Money(700, eur),
      ); // yesterday-territory: stays null
      await seedRow(
        date: now,
        amount: Money(990, eur),
        baseCurrencyCode: 'USD',
        fxRate: 0.80,
      ); // snapshot kept
      await seedRow(date: now, amount: Money(250, usd)); // domestic: untouched

      final (service, _) = fx((_) async => ok('EUR', 0.93));
      addTearDown(service.close);
      await service.setLiveRatesEnabled(true);
      expect(await service.lookup('USD', 'EUR'), 0.93);

      final rows = await db.select(db.transactions).get();
      final byMinor = {
        for (final r in rows) (r.currencyCode, r.amountMinor): r,
      };
      // Rows are stamped with the reciprocal — base units per 1 quote unit
      // (spec §6): 1000 * 1/0.93 → 1075 (half-away matches Money.convertTo).
      final rowRate = 1 / 0.93;
      expect(byMinor[('EUR', 1000)]!.fxRate, closeTo(rowRate, 1e-9));
      expect(byMinor[('EUR', 1000)]!.baseAmountMinor, 1075);
      expect(byMinor[('EUR', 500)]!.baseAmountMinor, 538);
      expect(byMinor[('EUR', 700)]!.fxRate, isNull); // other day untouched
      expect(byMinor[('EUR', 990)]!.fxRate, 0.80); // existing snapshot wins
      expect(byMinor[('USD', 250)]!.fxRate, isNull);
    });

    test('a foreign-rate fetch never rewrites another base’s rows', () async {
      await repo.setBaseCurrency('GBP');
      await seedRow(date: now, amount: Money(1000, eur));

      final (service, _) = fx((_) async => ok('EUR', 0.93));
      addTearDown(service.close);
      await service.setLiveRatesEnabled(true);
      // A USD→EUR fetch succeeds while this device lives in GBP.
      expect(await service.lookup('USD', 'EUR'), 0.93);

      final row = (await db.select(db.transactions).get()).single;
      expect(row.fxRate, isNull); // sweep skipped — wrong base for the device
    });
  });

  group('no historical series', () {
    test('a successful fetch purges yesterday’s cache keys only', () async {
      await repo.setSetting('fx.USD-GBP.$today', '0.77'); // other pair, today
      await repo.setSetting('fx.USD-EUR.2026-11-01', '0.92'); // stale
      await repo.setSetting(FxService.settingLiveFxRates, 'on'); // not fx.*

      final (service, _) = fx((_) async => ok('EUR', 0.93));
      addTearDown(service.close);
      await service.setLiveRatesEnabled(true);
      await service.lookup('USD', 'EUR');

      expect(await repo.setting('fx.USD-GBP.$today'), '0.77');
      expect(await repo.setting('fx.USD-EUR.2026-11-01'), isNull);
      expect(await repo.setting(FxService.settingLiveFxRates), 'on');
      expect(await repo.setting(FxService.cacheKey('USD', 'EUR', now)), '0.93');
    });
  });
}
