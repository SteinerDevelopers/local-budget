import 'currency.dart';
import 'money.dart';
import 'receipt.dart';

/// Paper kind driving the totals vocabulary (e2-capture.md §3 v1.1).
enum DocType { receipt, cardStatement, utilityBill }

/// Tier-2 extraction: deterministic heuristics over raw OCR lines.
///
/// Pipeline (feasibility §2): tier 1 = ML Kit OCR text, tier 2 = *this*,
/// tier 3 = optional on-device LLM. Heuristics must never be clever enough to
/// be wrong silently — anything uncertain is emitted at low confidence for
/// the review sheet instead of guessed.
class ReceiptHeuristics {
  ReceiptHeuristics({required this.currency, DateTime? now})
      : now = now ?? DateTime.now();

  final Currency currency;
  final DateTime now;

  /// Lines containing any of these are *never* the grand total. Note `DUE`
  /// is deliberately absent — `TOTAL DUE` is the strongest positive anchor.
  static final RegExp _totalBlacklist = RegExp(
    r'SUB[\s\-]?TOTAL|TOTAL[\s\-]?(TAX|VAT|DISCOUNT|SAVINGS|ITEMS|COUNT|'
    r'CARD|CASH|CHANGE|TENDERED|AUTH|APPROVED|BALANCE)|GRATUITY|TIP[\s\-]?LINE'
    r'|AMOUNT[\s\-]?(TENDERED|PAID|CHANGE|CREDIT|CASH)',
    caseSensitive: false,
  );

  /// Grand-total anchors with their confidence, most specific first — the
  /// first anchor matching a line wins, so `NET TOTAL` must precede the bare
  /// `TOTAL` that is a substring of it (e2-capture.md §3 priority). `TOTAL
  /// DUE`/`AMOUNT DUE` (utility bills) and the `*TOTAL` compounds rank above
  /// bare `TOTAL`; bare `AMOUNT` is a last resort at low confidence.
  static final List<({RegExp re, FieldConfidence confidence})> _totalAnchors = [
    (
      re: RegExp(r'\bGRAND\s+TOTAL\b', caseSensitive: false),
      confidence: FieldConfidence.high
    ),
    (
      re: RegExp(r'\bTOTAL\s+DUE\b', caseSensitive: false),
      confidence: FieldConfidence.high
    ),
    (
      re: RegExp(r'\bAMOUNT\s+DUE\b', caseSensitive: false),
      confidence: FieldConfidence.high
    ),
    (
      re: RegExp(r'\bNET\s+TOTAL\b', caseSensitive: false),
      confidence: FieldConfidence.high
    ),
    (
      re: RegExp(r'\bBALANCE\s+DUE\b', caseSensitive: false),
      confidence: FieldConfidence.medium
    ),
    (
      re: RegExp(r'\bTOTAL\b', caseSensitive: false),
      confidence: FieldConfidence.medium
    ),
    (
      re: RegExp(r'\bAMOUNT\b', caseSensitive: false),
      confidence: FieldConfidence.low
    ),
  ];

  static final RegExp _amountRe = RegExp(
    r'(?<amount>[-−(]?\s*(?:[$€£¥₹]|US\$|CA\$|AU\$|NZ\$|EUR|USD|GBP)?\s*\d{1,3}(?:[.,\s\u00A0]\d{3})*(?:[.,]\d{1,2})?\s*[-−)]?)',
  );

  /// Document kind the totals vocabulary should follow (e2-capture.md §3 v1.1).
  /// Classification never *requires* a type: everything defaults to the
  /// retail `receipt` anchor list — the safest guess for an unknown paper.
  DocType classify(List<String> lines) => DocType.values.firstWhere(
        (t) => t != DocType.receipt && _signatureCount(t, lines) >= 2,
        orElse: () => DocType.receipt,
      );

  /// Distinct signature patterns of [type] present anywhere in [lines].
  int _signatureCount(DocType type, List<String> lines) {
    final pats = switch (type) {
      DocType.receipt => const <RegExp>[],
      DocType.cardStatement => _cardSignatures,
      DocType.utilityBill => _utilitySignatures,
    };
    final text = lines.join('\n').toUpperCase();
    return pats.where((p) => p.hasMatch(text)).length;
  }

  static final List<RegExp> _cardSignatures = [
    RegExp(r'STATEMENT BALANCE'),
    RegExp(r'(NEW|PREVIOUS|OPENING|PRESENT|CURRENT) BALANCE'),
    RegExp(r'MINIMUM (PAYMENT|PYMT|DUE)|MIN(?!U)\.? ?(PAYMENT|PYMT)'),
    RegExp(r'CREDIT LIMIT'),
    RegExp(r'FINANCE CHARGE'),
    RegExp(r'PAYMENT CREDIT'),
    RegExp(r'ANNUAL FEE'),
    RegExp(r'\bAPR\b|ANNUAL PERCENTAGE RATE'),
    RegExp(r'CASH ADVANCE'),
    RegExp(r'ACCOUNT SUMMARY'),
  ];

  static final List<RegExp> _utilitySignatures = [
    RegExp(r'SERVICE PERIOD|BILLING PERIOD|BILLING DATES'),
    RegExp(r'METER READ'),
    RegExp(r'KILOWATT|\bKWH\b|THERMS?|CU FT|GALLONS'),
    RegExp(r'DUE BY|PAY BY|DUE DATE'),
    // Account number *plus* the word BILL somewhere — utilities print both;
    // a lone "account number" line is too generic to count (spec §3 v1.1).
    RegExp(r'ACCOUNT\s*(NUMBER|NO\.?|#)'),
    RegExp(r'\bBILL\b'),
  ];

  /// Anchors per document type — classification only *replaces* the list;
  /// scanning stays bottom-up (e2-capture.md §3 v1.1). On a card statement
  /// `STATEMENT/NEW/CURRENT BALANCE` is the amount a budgeting app should
  /// pre-fill; a minimum-payment line is never it, whatever it is labeled.
  static List<({RegExp re, FieldConfidence confidence})> _anchorsFor(
          DocType type) =>
      switch (type) {
        DocType.receipt => _totalAnchors,
        DocType.cardStatement => _cardAnchors,
        DocType.utilityBill => _utilityAnchors,
      };

  static final List<({RegExp re, FieldConfidence confidence})> _cardAnchors = [
    (
      re: RegExp(r'\bSTATEMENT BALANCE\b', caseSensitive: false),
      confidence: FieldConfidence.high
    ),
    (
      re: RegExp(r'\b(NEW|CURRENT|PRESENT) BALANCE\b', caseSensitive: false),
      confidence: FieldConfidence.high
    ),
    (
      re: RegExp(r'\bBALANCE DUE\b', caseSensitive: false),
      confidence: FieldConfidence.medium
    ),
    (
      re: RegExp(r'\bTOTAL\s+(AMOUNT\s+)?DUE\b', caseSensitive: false),
      confidence: FieldConfidence.low
    ), // on statements this is usually the minimum
    (
      re: RegExp(r'\bTOTAL\b', caseSensitive: false),
      confidence: FieldConfidence.low
    ),
  ];

  static final List<({RegExp re, FieldConfidence confidence})> _utilityAnchors =
      [
    (
      re: RegExp(r'\bTOTAL\s+AMOUNT\s+DUE\b', caseSensitive: false),
      confidence: FieldConfidence.high
    ),
    (
      re: RegExp(r'\bAMOUNT\s+DUE\b|\bDUE\s+AMOUNT\b', caseSensitive: false),
      confidence: FieldConfidence.high
    ),
    (
      re: RegExp(r'\bTOTAL\s+DUE\b', caseSensitive: false),
      confidence: FieldConfidence.high
    ),
    (
      re: RegExp(r'\bBALANCE\s+DUE\b', caseSensitive: false),
      confidence: FieldConfidence.medium
    ),
    (
      re: RegExp(r'\bTOTAL\b', caseSensitive: false),
      confidence: FieldConfidence.medium
    ),
    (
      re: RegExp(r'\bAMOUNT\b', caseSensitive: false),
      confidence: FieldConfidence.low
    ),
  ];

  static RegExp _blacklistFor(DocType type) => switch (type) {
        DocType.receipt => _totalBlacklist,
        DocType.cardStatement => RegExp(
            '${_totalBlacklist.pattern}|$_cardBlacklistSrc',
            caseSensitive: false,
          ),
        DocType.utilityBill => RegExp(
            '${_totalBlacklist.pattern}|$_utilityBlacklistSrc',
            caseSensitive: false,
          ),
      };

  /// The payment you must NOT mistake for the bill: minimums, past payments,
  /// credit lines, limits and finance charges (spec §3 v1.1).
  static const String _cardBlacklistSrc =
      r'MINIMUM (PAYMENT|PYMT|DUE)|MIN(?!U)\.? ?(PAYMENT|PYMT)'
      r'|LAST PAYMENT|PARTIAL PAYMENT|CREDIT PAYMENT|PAYMENT RECEIVED'
      r'|PREVIOUS BALANCE|OPENING BALANCE|NEW CHARGES|CREDIT LIMIT'
      r'|AVAILABLE CREDIT|FINANCE CHARGE|CASH ADVANCE|ANNUAL FEE';

  /// Components of a utility bill that are not the check you write.
  static const String _utilityBlacklistSrc =
      r'PREVIOUS BALANCE|AMOUNT PAID|PAYMENT RECEIVED|PAST DUE'
      r'|AMOUNT ENCLOSED|BALANCE FORWARD';

  /// Merchant heuristic: first line with letters, short, not address-like,
  /// not a pure number/date. `high` when the very first line is already
  /// plausible (the usual printed-receipt layout), `medium` when the guess
  /// had to skip noise to find it (e2-capture.md §3).
  ({String name, FieldConfidence confidence})? guessMerchant(
      List<String> lines) {
    var index = 0;
    for (final raw in lines.take(6)) {
      final line = raw.trim();
      index++;
      if (line.length < 2 || line.length > 40) continue;
      final letters = line.replaceAll(RegExp('[^A-Za-zÀ-ÿ]'), '').length;
      if (letters < 2) continue; // pure numbers/dates/punctuation
      if (RegExp(r'^\d').hasMatch(line)) continue; // starts with digit
      if (RegExp(r'\b(ST|STREET|RD|ROAD|AVE|AVENUE|BLVD|SUITE|STE|INC|LLC|LTD)\b',
                  caseSensitive: false)
              .hasMatch(line) &&
          RegExp(r'\d').hasMatch(line)) {
        continue; // address or legal tail
      }
      if (RegExp(
              r'^(THANK|THANKS|VISIT|SCAN|RECEIPT|INVOICE|TEL|PHONE|VAT\s+ID|TAX\s+ID)',
              caseSensitive: false)
          .hasMatch(line)) {
        continue;
      }
      return (
        name: line,
        confidence: index == 1 ? FieldConfidence.high : FieldConfidence.medium,
      );
    }
    return null;
  }

  /// Extract the grand total. Scans bottom-up because the grand total sits
  /// near the bottom of nearly every real receipt; the first anchor hit from
  /// the bottom wins, blacklist excluded. An explicit currency code/symbol on
  /// the anchor line overrides the device base currency (e2-capture.md §3:
  /// currency comes from the anchor line, falling back to base).
  ///
  /// v1.1 (device feedback, 2026-11-03): the anchor list follows the
  /// [classify]d document type; an amount left of the anchor on the same line
  /// counts; an amount-free anchor line looks *down* up to two non-empty
  /// non-blacklisted lines (OCR column split); decimals beat bare integers
  /// (`TOTAL 4 ITEMS 42.50` is 42.50, not 4); amounts re-joined across lines
  /// must carry a symbol or decimal and inherit confidence minus one level.
  ({Money amount, FieldConfidence confidence})? guessTotal(List<String> lines) {
    final type = classify(lines);
    final anchors = _anchorsFor(type);
    final blacklist = _blacklistFor(type);
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (blacklist.hasMatch(line)) continue;
      for (final anchor in anchors) {
        final match = anchor.re.firstMatch(line);
        if (match == null) continue;
        var source = line;
        var merged = false;
        // 1. Amount to the right of the anchor (the classic shape).
        var parsed =
            _bestAmount(line.substring(match.end), requireExact: false);
        // 2. …or to its left on the same line (`42.50 TOTAL` POS layouts).
        //    Must look like money (symbol or decimal) — digits glued to the
        //    label (`TOTAL2`) are OCR noise, not a left-aligned amount.
        parsed ??=
            _bestAmount(line.substring(0, match.start), requireExact: true);
        // 3. …or on one of the next two lines (anchor and right-aligned
        //    amount OCR'd as separate blocks; e2-capture.md §3 v1.1).
        if (parsed == null) {
          var seen = 0;
          for (var j = i + 1; j < lines.length && seen < 2; j++) {
            final next = lines[j].trim();
            if (next.isEmpty) continue;
            seen++;
            if (blacklist.hasMatch(next)) continue;
            final p = _bestAmount(next, requireExact: true);
            if (p != null) {
              parsed = p;
              source = next;
              merged = true;
              break;
            }
          }
        }
        if (parsed == null) continue; // no amount anywhere near this anchor
        final cur =
            _lineCurrency(merged ? '$line $source' : line, parsed.token);
        final amount = cur == null || cur.code == parsed.amount.currency.code
            ? parsed.amount
            : (Money.tryParse(parsed.token, cur) ?? parsed.amount);
        return (
          amount: amount,
          confidence: merged ? _demote(anchor.confidence) : anchor.confidence,
        );
      }
    }
    return null;
  }

  static FieldConfidence _demote(FieldConfidence c) => switch (c) {
        FieldConfidence.high => FieldConfidence.medium,
        FieldConfidence.medium || FieldConfidence.low => FieldConfidence.low,
      };

  /// "Exact money" = a decimal amount or one carrying a currency symbol —
  /// the guard that keeps a barcode (`123456789012`) below a bare `TOTAL`
  /// from becoming the total when lines get re-joined across blocks.
  static bool _looksLikeMoney(String token) =>
      RegExp(r'\d[.,]\d{1,2}\b').hasMatch(token) ||
      RegExp(r'[$€£¥₹]').hasMatch(token);

  /// First positive amount in [s]; a token that looks like money (decimal or
  /// symbol) wins over a bare integer regardless of position, so
  /// `TOTAL 4 ITEMS 42.50` yields 42.50 instead of the item count 4. With
  /// [requireExact] only money-looking tokens count at all.
  ({String token, Money amount})? _bestAmount(String s,
      {required bool requireExact}) {
    ({String token, Money amount})? firstInt;
    for (final m in _amountRe.allMatches(s)) {
      final token = m.namedGroup('amount')!;
      final exact = _looksLikeMoney(token);
      if (requireExact && !exact) continue;
      final parsed = Money.tryParse(token, currency);
      if (parsed == null || !parsed.isPositive) continue;
      if (exact) return (token: token, amount: parsed);
      firstInt ??= (token: token, amount: parsed);
    }
    return firstInt;
  }

  static final RegExp _currencyCodeRe = RegExp(
    r'\b(USD|EUR|GBP|JPY|KRW|CNY|RMB|CHF|SEK|NOK|DKK|PLN|CZK|HUF|INR|BRL|MXN'
    r'|NZD|SGD|ISK|BHD|KWD|CAD|AUD)\b',
  );

  /// Explicit currency written on the anchor line: a 3-letter code (exact)
  /// or an unambiguous symbol. `$` is deliberately never re-resolved — it is
  /// ambiguous across a dozen currencies and already parses cleanly as the
  /// user's base — and `¥` means JPY unless the token has decimals (JPY has
  /// zero minor units, so `¥12.40` is a Chinese receipt).
  Currency? _lineCurrency(String line, String amountToken) {
    final code = _currencyCodeRe.firstMatch(line);
    if (code != null) {
      final c = code.group(1)!;
      return Currency.find(c == 'RMB' ? 'CNY' : c);
    }
    if (line.contains('\u20AC')) return Currency.find('EUR'); // €
    if (line.contains('\u00A3')) return Currency.find('GBP'); // £
    if (line.contains('\u20B9')) return Currency.find('INR'); // ₹
    if (line.contains('\u00A5') || line.contains('\uFFE5')) {
      // ¥ — halfwidth and fullwidth forms. A trailing decimal separator with
      // 1–2 digits (never a 3-digit thousands group) rules out JPY.
      return RegExp(r'\d[.,]\d{1,2}\s*$').hasMatch(amountToken)
          ? Currency.find('CNY')
          : Currency.find('JPY');
    }
    return null;
  }

  /// Date extraction with explicit ambiguity reporting (feasibility §2: dates
  /// are locale-ambiguous — flag, don't guess).
  ({DateTime date, bool ambiguous, FieldConfidence confidence})? guessDate(
      List<String> lines) {
    final text = lines.join('\n');

    // ISO first — unambiguous.
    final iso = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
    if (iso != null) {
      final d = _safeDate(int.parse(iso.group(1)!), int.parse(iso.group(2)!),
          int.parse(iso.group(3)!));
      if (d != null) {
        return (date: d, ambiguous: false, confidence: FieldConfidence.high);
      }
    }

    // "5 Mar 2026" / "Mar 5, 2026" — unambiguous. Month alternation is
    // inlined (not composed) because Dart raw strings do not interpolate
    // `$_identifier` — verified on Dart 3.13.
    final monthName = RegExp(
      r'\b(?<d1>\d{1,2})[\s\-]'
      r'(?<m1>jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)'
      r'[\s\-,]*(?<y1>\d{2,4})\b'
      r'|\b(?<m2>jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)'
      r'[\s\-](?<d2>\d{1,2}),?\s*(?<y2>\d{2,4})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (monthName != null) {
      final dayStr = monthName.namedGroup('d1') ?? monthName.namedGroup('d2');
      final monStr = monthName.namedGroup('m1') ?? monthName.namedGroup('m2');
      final yearStr = monthName.namedGroup('y1') ?? monthName.namedGroup('y2');
      final month = monStr == null ? null : _monthNumber(monStr);
      if (dayStr != null && yearStr != null && month != null) {
        final d = _safeDate(_expandYear(yearStr), month, int.parse(dayStr));
        if (d != null) {
          return (date: d, ambiguous: false, confidence: FieldConfidence.high);
        }
      }
    }

    // Numeric d/m/y — decide order by *unambiguous* candidates only.
    final numeric = RegExp(r'\b(\d{1,2})[./](\d{1,2})[./](\d{2,4})\b')
        .allMatches(text)
        .toList();
    for (final m in numeric) {
      final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
      final year = _expandYear(m.group(3)!);
      int? day, month;
      var ambiguous = false;
      if (a > 12 && b <= 12) {
        day = a;
        month = b;
      } else if (b > 12 && a <= 12) {
        month = a;
        day = b;
      } else {
        ambiguous = true;
        day = a;
        month = b;
      } // flag: assume D/M (device default)
      final d = _safeDate(year, month, day);
      if (d != null) {
        return (
          date: d,
          ambiguous: ambiguous,
          confidence: ambiguous ? FieldConfidence.low : FieldConfidence.medium,
        );
      }
    }
    return null;
  }

  DateTime? _safeDate(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final candidate = DateTime(y, m, d);
    if (candidate.year != y || candidate.month != m || candidate.day != d) {
      return null;
    }
    // Receipts are never more than a day in the future; more than 3 years
    // back is noise on modern receipts.
    if (candidate.isAfter(now.add(const Duration(days: 1)))) return null;
    if (candidate.isBefore(now.subtract(const Duration(days: 365 * 3 + 2)))) {
      return null;
    }
    return candidate;
  }

  static int _expandYear(String y) =>
      y.length <= 2 ? 2000 + int.parse(y) : int.parse(y);

  static final Map<String, int> _months = {
    for (final e in const [
      ('jan', 1),
      ('feb', 2),
      ('mar', 3),
      ('apr', 4),
      ('may', 5),
      ('jun', 6),
      ('jul', 7),
      ('aug', 8),
      ('sep', 9),
      ('oct', 10),
      ('nov', 11),
      ('dec', 12),
    ])
      e.$1: e.$2,
  };

  static int? _monthNumber(String name) =>
      _months[name.toLowerCase().substring(0, 3)];

  /// Run all heuristics.
  ReceiptDraft extract(List<String> lines) {
    final merchant = guessMerchant(lines);
    final total = guessTotal(lines);
    final date = guessDate(lines);
    return ReceiptDraft(
      merchant: merchant?.name,
      merchantConfidence:
          merchant == null ? FieldConfidence.low : merchant.confidence,
      total: total?.amount,
      totalConfidence: total?.confidence ?? FieldConfidence.low,
      date: date?.date,
      dateConfidence: date?.confidence ?? FieldConfidence.low,
      dateIsAmbiguous: date?.ambiguous ?? false,
      rawLines: List.unmodifiable(lines),
    );
  }
}
