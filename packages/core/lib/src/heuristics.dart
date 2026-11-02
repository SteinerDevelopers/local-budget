import 'currency.dart';
import 'money.dart';
import 'receipt.dart';

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
    r'CARD|CASH|CHANGE|TENDERED|AUTH|APPROVED|BALANCE)|GRATUITY|TIP[\s\-]?LINE',
    caseSensitive: false,
  );

  /// Grand-total anchors with their confidence, best first. `TOTAL DUE`
  /// (utility bills) and `AMOUNT DUE` rank above bare `TOTAL` because on
  /// utility statements a bare TOTAL is often a subtotal of charges.
  static final List<({RegExp re, FieldConfidence confidence})> _totalAnchors = [
    (
      re: RegExp(r'\bTOTAL\s+DUE\b', caseSensitive: false),
      confidence: FieldConfidence.high
    ),
    (
      re: RegExp(r'\bAMOUNT\s+DUE\b', caseSensitive: false),
      confidence: FieldConfidence.high
    ),
    (
      re: RegExp(r'\bTOTAL\b', caseSensitive: false),
      confidence: FieldConfidence.medium
    ),
    (
      re: RegExp(r'\bBALANCE\s+DUE\b', caseSensitive: false),
      confidence: FieldConfidence.medium
    ),
    (
      re: RegExp(r'\bNET\s+TOTAL\b', caseSensitive: false),
      confidence: FieldConfidence.medium
    ),
  ];

  static final RegExp _amountRe = RegExp(
    r'(?<amount>[-−(]?\s*(?:[$€£¥₹]|US\$|CA\$|AU\$|NZ\$|EUR|USD|GBP)?\s*\d{1,3}(?:[.,\s\u00A0]\d{3})*(?:[.,]\d{1,2})?\s*[-−)]?)',
  );

  /// Merchant heuristic: first line with letters, short, not address-like,
  /// not a pure number/date.
  String? guessMerchant(List<String> lines) {
    for (final raw in lines.take(6)) {
      final line = raw.trim();
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
      return line;
    }
    return null;
  }

  /// Extract the grand total. Scans bottom-up because the grand total sits
  /// near the bottom of nearly every real receipt; the first anchor hit from
  /// the bottom wins, blacklist excluded.
  ({Money amount, FieldConfidence confidence})? guessTotal(List<String> lines) {
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (_totalBlacklist.hasMatch(line)) continue;
      for (final anchor in _totalAnchors) {
        final match = anchor.re.firstMatch(line);
        if (match == null) continue;
        // Amount must come *after* the anchor word on the line.
        final tail = line.substring(match.end);
        final parsed = _firstAmount(tail);
        if (parsed == null) continue;
        return (amount: parsed, confidence: anchor.confidence);
      }
    }
    return null;
  }

  Money? _firstAmount(String s) {
    for (final m in _amountRe.allMatches(s)) {
      final parsed = Money.tryParse(m.namedGroup('amount')!, currency);
      if (parsed != null && parsed.isPositive) return parsed;
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
      merchant: merchant,
      merchantConfidence:
          merchant == null ? FieldConfidence.low : FieldConfidence.medium,
      total: total?.amount,
      totalConfidence: total?.confidence ?? FieldConfidence.low,
      date: date?.date,
      dateConfidence: date?.confidence ?? FieldConfidence.low,
      dateIsAmbiguous: date?.ambiguous ?? false,
      rawLines: List.unmodifiable(lines),
    );
  }
}
