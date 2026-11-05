import 'currency.dart';
import 'heuristics.dart';
import 'money.dart';
import 'receipt.dart';

/// Recurrence suggested by document text. Mirrors the three frequencies the
/// rule engine (E3) actually stores — a quarterly bill lands on `monthly`
/// with the parsed due date as the first-due cursor (e11 §4), never on an
/// invented frequency the editor cannot show.
enum BillFrequencyHint {
  weekly('weekly'),
  monthly('monthly'),
  yearly('yearly');

  const BillFrequencyHint(this.wireName);
  final String wireName;
}

/// E11 bill-route draft: the four fields the bill editor needs, each with
/// its own confidence so the editor can mark a prefilled value amber exactly
/// like the receipt review sheet does (decision 5 — the editor still has to
/// be confirmed; nothing here persists).
///
/// Payee and amount reuse [ReceiptHeuristics] under their DocType-aware
/// anchors (utility/card sets prefer TOTAL / AMOUNT DUE over balances);
/// due-date and frequency vocabulary is new.
class BillDraft {
  BillDraft._({
    this.payee,
    this.payeeConfidence = FieldConfidence.low,
    this.amountDue,
    this.amountConfidence = FieldConfidence.low,
    this.dueDate,
    this.dueDateConfidence = FieldConfidence.low,
    this.frequency = BillFrequencyHint.monthly,
    this.frequencyConfidence = FieldConfidence.low,
  });

  /// Drafts a bill from OCR/text lines. [currency] gates the amount parse;
  /// [now] bounds the due-date window (test seam, never a hidden default in
  /// the result).
  factory BillDraft.draft(
    List<String> lines, {
    required Currency currency,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final h = ReceiptHeuristics(currency: currency, now: at);
    final merchant = h.guessMerchant(lines);
    final total = h.guessTotal(lines);
    final due = guessDueDate(lines, now: at);
    final (freq, freqConfidence) = _guessFrequency(lines);
    return BillDraft._(
      payee: merchant?.name,
      payeeConfidence: merchant?.confidence ?? FieldConfidence.low,
      amountDue: total?.amount,
      amountConfidence: total?.confidence ?? FieldConfidence.low,
      dueDate: due?.date,
      dueDateConfidence: due?.confidence ?? FieldConfidence.low,
      frequency: freq,
      frequencyConfidence: freqConfidence,
    );
  }

  final String? payee;
  final FieldConfidence payeeConfidence;
  final Money? amountDue;
  final FieldConfidence amountConfidence;

  /// When the bill should hit — the editor's start/next-due seed.
  final DateTime? dueDate;
  final FieldConfidence dueDateConfidence;

  /// Recurrence suggestion; low confidence means "no vocabulary found,
  /// monthly is the statistical default", not a reading of the document.
  final BillFrequencyHint frequency;
  final FieldConfidence frequencyConfidence;

  /// Nothing at all was recognised — the caller should show an empty editor
  /// rather than a draft full of amber nulls.
  bool get isEmpty => payee == null && amountDue == null && dueDate == null;

  // --- due date ---------------------------------------------------------

  /// `DUE DATE …`, `PAY BY …`, `PAYMENT DUE BY …` — bill vocabulary.
  static final RegExp _dueRe = RegExp(
    r'\bDUE[\s\-]?DATE\b|\bDUE\s+(?:ON|BY)\b|\bPAY(?:MENT)?\s+(?:BY|MUST BE|IS DUE)'
    r'|\bPAYMENT DUE\b',
    caseSensitive: false,
  );

  /// Statement-period vocabulary: without a due line the period end plus a
  /// standard 21-day float is the best legal suggestion, clearly low
  /// confidence so the editor shows it amber (e11 §4).
  static final RegExp _periodRe = RegExp(
    r'PERIOD\s+(?:END|THROUGH|THRU)|STATEMENT\s+PERIOD|BILLING\s+PERIOD'
    r'|YOUR\s+ACCOUNT\s+PERIOD',
    caseSensitive: false,
  );

  /// Loose date reader shared by the due/period scans: numeric
  /// `yyyy-MM-dd | d/M/yyyy | d.M.yyyy` (day/month resolved from the values
  /// themselves when one exceeds 12) plus `Nov 3` / `3 Nov` / `Nov 3, 2026`.
  static DateTime? parseDateLoose(String token, {int? yearFallback}) {
    final s = token.trim().replaceAll('.', ' ').replaceAll(RegExp(r'\s+'), ' ');
    var m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(token.trim());
    if (m != null) {
      return _safeDate(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
    }
    m = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})$').firstMatch(
      token.trim(),
    );
    if (m != null) {
      final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
      var y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      // Values above 12 disambiguate; otherwise day-first is the calmer
      // assumption for bills (US statements print MM/dd, but a bill line
      // `05/09/2026` is only provably month-first by a >12 day elsewhere).
      final (day, month) = a > 12
          ? (a, b)
          : b > 12
              ? (b, a)
              : (a, b);
      return _safeDate(y, month, day);
    }
    m = RegExp(
      r'^([A-Za-z]{3,9})\.? (\d{1,2})(?:,? (\d{4}))?$',
    ).firstMatch(s);
    if (m != null) {
      final month = _monthFromName(m.group(1)!);
      if (month != null) {
        return _safeDate(
          int.parse(m.group(3) ?? '$yearFallback'),
          month,
          int.parse(m.group(2)!),
        );
      }
    }
    m = RegExp(
      r'^(\d{1,2}) ([A-Za-z]{3,9})\.?(?:,? (\d{4}))?$',
    ).firstMatch(s);
    if (m != null) {
      final month = _monthFromName(m.group(2)!);
      if (month != null) {
        return _safeDate(
          int.parse(m.group(3) ?? '$yearFallback'),
          month,
          int.parse(m.group(1)!),
        );
      }
    }
    // Year-less numeric pair (`05/09`), same >12 rule.
    m = RegExp(r'^(\d{1,2})[/.-](\d{1,2})$').firstMatch(token.trim());
    if (m != null && yearFallback != null) {
      final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
      final (day, month) = a > 12
          ? (a, b)
          : b > 12
              ? (b, a)
              : (a, b);
      return _safeDate(yearFallback, month, day);
    }
    return null;
  }

  /// Finds a due date: a due-vocabulary line wins (same line high, next
  /// line medium — OCR sometimes splits the value); otherwise a statement
  /// period end + [kPeriodFloatDays] at low confidence. Window: bills are
  /// short-cycle paperwork, so only `now − 7d … now + 90d` is believable
  /// (e11 §4 — yesterday's missed bill is still worth entering, last
  /// spring's is a statement).
  static ({DateTime date, FieldConfidence confidence})? guessDueDate(
    List<String> lines, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final window = Duration(days: 90);
    final back = const Duration(days: 7);
    for (var i = 0; i < lines.length; i++) {
      if (!_dueRe.hasMatch(lines[i])) continue;
      final confidence = i == 0 || _dateTokenIn(lines[i]) != null
          ? FieldConfidence.high
          : FieldConfidence.medium;
      // The value usually shares the line; OCR also splits it to the next.
      for (final j in [i, if (i + 1 < lines.length) i + 1]) {
        final tok = _dateTokenIn(lines[j]);
        if (tok == null) continue;
        final d = parseDateLoose(tok, yearFallback: at.year);
        if (d == null) continue;
        if (d.isBefore(at.subtract(back)) || d.isAfter(at.add(window))) {
          continue;
        }
        return (date: d, confidence: confidence);
      }
    }
    for (var i = 0; i < lines.length; i++) {
      if (!_periodRe.hasMatch(lines[i])) continue;
      final tok = _dateTokenIn(lines[i]) ??
          (i + 1 < lines.length ? _dateTokenIn(lines[i + 1]) : null);
      if (tok == null) continue;
      final d = parseDateLoose(tok, yearFallback: at.year);
      if (d == null) continue;
      if (d.difference(at).abs() > const Duration(days: 60)) continue;
      final floated = d.add(const Duration(days: kPeriodFloatDays));
      if (floated.isBefore(at)) continue;
      return (date: floated, confidence: FieldConfidence.low);
    }
    return null;
  }

  static const kPeriodFloatDays = 21;

  /// Right-most date-shaped token in a line (numeric triples, year-less
  /// pairs, or month names). Statements open with the document date and
  /// end with the operative one: `BILLING PERIOD 09/01/2026 - 09/30/2026`
  /// must yield the period END, and a due line carrying an invoice date
  /// too still points at its last date. Kept deliberately greedy on
  /// shapes and strict on values — `parseDateLoose` still has to accept it.
  static String? _dateTokenIn(String line) {
    final re = RegExp(
      r'\d{4}-\d{1,2}-\d{1,2}|\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}'
      r'|\d{1,2}[/.-]\d{1,2}(?![\d/.-])'
      // Real month names with a word boundary: a loose `[JFMASOND]` class
      // reads the D of "DATE" as December and swallows the digits after it.
      r'|(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?'
      r'|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?'
      r'|Nov(?:ember)?|Dec(?:ember)?)(?![a-z])\.?,?\s*\d{1,2}(?:,?\s*\d{4})?'
      r'|\d{1,2}\s+(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May'
      r'|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?'
      r'|Nov(?:ember)?|Dec(?:ember)?)(?![a-z])\.?(?:,?\s*\d{4})?',
      caseSensitive: false,
    );
    String? tok;
    for (final m in re.allMatches(line)) {
      tok = m.group(0);
    }
    return tok?.trim();
  }

  static final List<String> _months = const [
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
  ];

  static int? _monthFromName(String name) {
    final n = name.toLowerCase();
    for (var i = 0; i < _months.length; i++) {
      if (_months[i].startsWith(n)) return i + 1;
    }
    return null;
  }

  static DateTime? _safeDate(int y, int mo, int d) {
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || y < 1990 || y > 2100) {
      return null;
    }
    final dt = DateTime.utc(y, mo, d);
    if (dt.day != d || dt.month != mo) return null; // 31.02 style overflow
    return dt;
  }

  // --- frequency ---------------------------------------------------------

  static final RegExp _yearlyRe = RegExp(
    r'\bANNUAL(?:LY)?\b|\bYEARLY\b|EVERY\s+YEAR',
    caseSensitive: false,
  );
  static final RegExp _quarterlyRe = RegExp(
    r'\bQUARTERLY\b|EVERY\s+(?:3|THREE)\s+MONTHS?',
    caseSensitive: false,
  );
  static final RegExp _weeklyRe = RegExp(
    r'\bWEEKLY\b|EVERY\s+WEEK',
    caseSensitive: false,
  );
  static final RegExp _monthlyRe = RegExp(
    r'\bMONTHLY\b|EVERY\s+MONTH',
    caseSensitive: false,
  );

  static (BillFrequencyHint, FieldConfidence) _guessFrequency(
    List<String> lines,
  ) {
    final text = lines.join('\n');
    // Quarterly has no rule-engine representation: monthly with the parsed
    // due date as first-due cursor is the faithful degrade (e11 §4), so it
    // reports monthly at medium — better than nothing, honest about it.
    if (_yearlyRe.hasMatch(text)) {
      return (BillFrequencyHint.yearly, FieldConfidence.high);
    }
    if (_weeklyRe.hasMatch(text)) {
      return (BillFrequencyHint.weekly, FieldConfidence.high);
    }
    if (_quarterlyRe.hasMatch(text)) {
      return (BillFrequencyHint.monthly, FieldConfidence.medium);
    }
    if (_monthlyRe.hasMatch(text)) {
      return (BillFrequencyHint.monthly, FieldConfidence.high);
    }
    return (BillFrequencyHint.monthly, FieldConfidence.low);
  }
}
