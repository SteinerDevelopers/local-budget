import 'dart:convert';

import 'package:core/core.dart' show Currency;

import 'csv_import.dart';

/// One row parsed out of a photographed / PDF-text bank or card statement
/// (E11, e11-document-import.md §3). Maps 1:1 onto `CsvPreviewRow` on the
/// import Preview; `externalId` deliberately stays null there — dedupe is
/// the shared E5 date|amount|direction tuple, same as FITID-less OFX rows.
/// One itemized line under a statement row (e12 §5): name left, price right,
/// no date of its own. Only ever stored when the whole block reconciles to
/// its row's amount — silence is the honest answer otherwise.
final class ItemLine {
  const ItemLine({
    required this.name,
    required this.unitPriceMinor,
    this.quantity,
  });

  final String name;
  final int unitPriceMinor;
  final int? quantity;

  int get totalMinor => unitPriceMinor * (quantity ?? 1);
}

final class StatementRow {
  const StatementRow({
    required this.date,
    required this.minor,
    required this.isIncome,
    this.description,
    this.ambiguous = false,
    this.items,
  });

  final DateTime date;

  /// Unsigned minor units, same convention as the CSV import rows.
  final int minor;
  final bool isIncome;
  final String? description;

  /// Itemized lines that reconciled to this row's amount (e12 §5), else null.
  final List<ItemLine>? items;

  /// True when something was *inferred* (balance-column split, carried
  /// year, ambiguous extra numerals) — the Preview renders these amber so
  /// the reviewer's eye lands on them first (decision 5 culture).
  final bool ambiguous;
}

/// Per-issuer column layout learned from a committed statement (e12 §3).
/// A snapshot of what the parser *derived* from a document the user reviewed
/// and committed — the owner's confirmation that the parse was right. It is
/// applied again only when a later document names the same issuer, and the
/// Preview discloses its use with a reset.
final class StatementLayout {
  const StatementLayout({required this.decimalComma, required this.dayFirst});

  /// True when amounts use `12,34` (comma is the decimal mark).
  final bool decimalComma;

  /// True when dates read `DD.MM.YYYY` rather than `MM/DD/…`.
  final bool dayFirst;

  String encode() => jsonEncode({'dc': decimalComma, 'df': dayFirst});

  static StatementLayout? decode(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    try {
      final j = jsonDecode(stored);
      if (j is! Map) return null;
      final dc = j['dc'], df = j['df'];
      if (dc is! bool || df is! bool) return null;
      return StatementLayout(decimalComma: dc, dayFirst: df);
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is StatementLayout &&
      other.decimalComma == decimalComma &&
      other.dayFirst == dayFirst;

  @override
  int get hashCode => Object.hash(decimalComma, dayFirst);
}

/// Result of [StatementLines.tryParse].
final class StatementParse {
  const StatementParse({
    required this.rows,
    required this.skippedLines,
    required this.layout,
  });

  final List<StatementRow> rows;

  /// The layout this parse ran on — derived from the document, or the saved
  /// profile that was applied (e12 §3). Commit persists it per issuer.
  final StatementLayout layout;

  /// Non-blank lines that carried neither a row nor a description wrap —
  /// headers, footers, balance-only lines. Surfaced on Preview so a mostly
  /// garbled scan is visible instead of silently short.
  final int skippedLines;
}

/// Right-to-left amount/balance/date scan over raw statement text (E11 §3).
///
/// Conservative by construction: only the strict CSV helpers parse values,
/// a mixed decimal style refuses the whole document (the caller hints at
/// CSV import instead), and every inference marks its row amber. Pure
/// Dart; the only clock use is [StatementLines.tryParse]'s `now` seam.
class StatementLines {
  /// Parses statement text; **null when the document's decimal style is
  /// ambiguous** (both `12,34` and `12.34` read as decimals somewhere) —
  /// guessing money against a mixed-style scan is the one failure mode E11
  /// is not allowed to have, so the caller must refuse with a CSV hint.
  static StatementParse? tryParse(
    List<String> lines, {
    required Currency currency,
    DateTime? now,
    StatementLayout? layout,
  }) {
    final at = _day(now ?? DateTime.now());
    final cleaned = [for (final l in lines) l.replaceAll('\u00a0', ' ').trim()]
      ..removeWhere((l) => l.isEmpty);
    if (cleaned.isEmpty) return null;

    // Document-level decimal style: provable marks must not contradict —
    // unless a saved profile for this issuer settles the dispute (e12 §3).
    final (commaDecimal, dotDecimal) = _styleProbe(cleaned);
    if (commaDecimal && dotDecimal && layout == null) return null;

    final shapes = [for (final l in cleaned) _shape(l, currency)];
    final rowish = shapes.where((s) => s.dateToken != null && s.hasAmount);

    // Column layout is a property of the statement, not of a row: when
    // most rows print two numerals there is a running-balance column.
    final twoNum = rowish.where((s) => s.amounts.length >= 2).length;
    final balanceColumn = rowish.isNotEmpty && twoNum * 2 >= rowish.length;
    final derivedDayFirst = _dayFirst(cleaned);
    final dayFirst = layout?.dayFirst ?? derivedDayFirst;

    final rows = <StatementRow>[];
    var skipped = 0;
    // e12 §5 — an item block is the run of dateless, priced, lettered lines
    // directly under a row. It is attached only when it closes reconciling
    // exactly to that row's amount; otherwise it is silently dropped.
    var itemOwner = -1;
    var itemBlock = <ItemLine>[];
    void closeItemBlock() {
      if (itemOwner >= 0 && itemBlock.length >= 2) {
        final owner = rows[itemOwner];
        final sum = itemBlock.fold<int>(0, (s, it) => s + it.totalMinor);
        if (sum == owner.minor) {
          rows[itemOwner] = StatementRow(
            date: owner.date,
            minor: owner.minor,
            isIncome: owner.isIncome,
            description: owner.description,
            ambiguous: owner.ambiguous,
            items: List.unmodifiable(itemBlock),
          );
        }
      }
      itemOwner = -1;
      itemBlock = [];
    }

    for (var i = 0; i < cleaned.length; i++) {
      final line = cleaned[i];
      final shape = shapes[i];
      if (shape.dateToken == null && shape.hasAmount) {
        // Dateless priced line: candidate item, or whatever ends a block —
        // a total line, a carried balance, anything untrustworthy.
        final item = shape.hasLetters && itemOwner == rows.length - 1
            ? _itemFrom(line, shape)
            : null;
        if (item != null) {
          itemBlock.add(item);
          continue;
        }
        closeItemBlock();
        skipped++;
        continue;
      }
      if (shape.dateToken == null || !shape.hasAmount) {
        // A letters-only line directly under a row is that row's
        // description wrapped by the OCR (statements do this at every
        // column width); anything else counts as skipped.
        if (rows.isNotEmpty && !shape.hasAmount && shape.hasLetters) {
          final prev = rows.last;
          rows[rows.length - 1] = StatementRow(
            date: prev.date,
            minor: prev.minor,
            isIncome: prev.isIncome,
            description: prev.description == null
                ? line
                : '${prev.description} $line',
            ambiguous: prev.ambiguous,
            items: prev.items,
          );
          continue;
        }
        skipped++;
        continue;
      }
      final date = _resolveDate(
        shape.dateToken!,
        dayFirst: dayFirst,
        previous: rows.isEmpty ? null : rows.last.date,
        now: at,
      );
      if (date == null) {
        skipped++;
        continue;
      }
      // A dated line — whatever item block hung off the previous row ends
      // here on paper, reconciled or not (e12 §5).
      closeItemBlock();
      final amount = _pickAmount(shape, balanceColumn: balanceColumn);
      if (amount == null) {
        skipped++;
        continue;
      }
      rows.add(
        StatementRow(
          date: date,
          minor: amount.minor,
          isIncome: _direction(line, amount.explicitSign),
          description: _describe(line, shape),
          ambiguous: amount.ambiguous || !_hasYearOnPaper(shape.dateToken!),
        ),
      );
      itemOwner = rows.length - 1;
    }
    closeItemBlock();
    return StatementParse(
      rows: rows,
      skippedLines: skipped,
      layout:
          layout ??
          StatementLayout(
            // Undecidable documents default to the dot style the strict
            // CSV helpers already assume; only a *proven* comma mark says
            // comma (e12 §3 keeps the snapshot honest).
            decimalComma: commaDecimal && !dotDecimal,
            dayFirst: derivedDayFirst,
          ),
    );
  }

  // --- decimal style -----------------------------------------------------

  /// Masks date tokens with same-length `~` runs so a numeral scan cannot
  /// read `05.12.2026` as a dot-decimal amount. Year-less pairs are only
  /// masked when both sides are plausible day/month values — `12.34` and
  /// `25.00` are money until proven otherwise; `05.12` is a date.
  /// A match glued to other numerals is *inside* an amount (`1,706.15`
  /// contains a date-looking `06.15`), so it stays untouched — masking it
  /// would fake a comma-decimal and refuse the whole US statement.
  static String _maskDates(String line) => line.replaceAllMapped(_dateRe, (m) {
    final t = m.group(0)!;
    bool numChar(int r) =>
        r == 0x2C || r == 0x2E || (r >= 0x30 && r <= 0x39); // , . 0-9
    final glued =
        (m.start > 0 && numChar(line.codeUnitAt(m.start - 1))) ||
        (m.end < line.length && numChar(line.codeUnitAt(m.end)));
    if (glued) return t;
    final p = RegExp(r'^(\d{1,2})[/.](\d{1,2})$').firstMatch(t);
    if (p != null) {
      final a = int.parse(p.group(1)!), b = int.parse(p.group(2)!);
      final datePlausible =
          (a >= 1 && a <= 12 && b >= 1 && b <= 31) ||
          (b >= 1 && b <= 12 && a >= 1 && a <= 31);
      if (!datePlausible) return t;
    }
    return '~' * t.length;
  });

  /// What the provable marks say about this document's decimal style:
  /// comma-decimal (`12,34`) and/or dot-decimal (`12.34`) present. Both at
  /// once is a contradiction no parser should paper over — unless a saved
  /// per-issuer profile settles it (e12 §3).
  static (bool commaDecimal, bool dotDecimal) _styleProbe(List<String> lines) {
    var commaDecimal = false, dotDecimal = false;
    for (final line in lines) {
      // Dates are not amounts: `05.12.2026` would fake a dot-decimal and
      // `05,12` a comma-decimal, contradicting each other on any European
      // statement. Mask the provable ones before scanning.
      final masked = _maskDates(line);
      for (final m in _numTokenRe.allMatches(masked)) {
        final t = m.group(0)!;
        final comma = t.lastIndexOf(','), dot = t.lastIndexOf('.');
        if (comma >= 0 && dot >= 0) {
          if (comma > dot)
            commaDecimal = true;
          else
            dotDecimal = true;
        } else if (comma >= 0) {
          if (t.length - comma - 1 < 3) commaDecimal = true;
        } else if (dot >= 0) {
          if (t.length - dot - 1 < 3) dotDecimal = true;
        }
      }
    }
    return (commaDecimal, dotDecimal);
  }

  // --- item blocks (e12 §5) ------------------------------------------------

  /// Words that end an item block: the statement's own summary vocabulary.
  static final RegExp _summaryRe = RegExp(
    r'\bTOTALS?\b|\bSUB ?TOTAL\b|\bBALANCE\b|\bAMOUNT\s+DUE\b|\bTAX\b'
    r'|\bGST\b|\bVAT\b|\bPAYMENT\b|\bINTEREST\b|\bFEE TOTAL\b',
    caseSensitive: false,
  );

  static final RegExp _qtyRe = RegExp(r'^(\d{1,2})\s*[x×]\s*(.+)$');

  /// One dateless priced lettered line as an item, or null when the line is
  /// summary vocabulary, carries more than one numeral (that is balance
  /// territory), or has no name left after a `2 ×` quantity prefix is read.
  static ItemLine? _itemFrom(String line, _LineShape shape) {
    if (shape.amounts.length != 1 || _summaryRe.hasMatch(line)) return null;
    final name0 = _describe(line, shape);
    if (name0 == null || !name0.contains(RegExp('[A-Za-z]'))) return null;
    var name = name0.trim();
    int? qty;
    final qm = _qtyRe.firstMatch(name);
    if (qm != null) {
      qty = int.parse(qm.group(1)!);
      name = qm.group(2)!.trim();
      if (name.isEmpty) return null;
    }
    final price = shape.amounts.first.minor; // amounts run right to left
    if (price <= 0) return null;
    return ItemLine(name: name, unitPriceMinor: price, quantity: qty);
  }

  // --- per-line shape ------------------------------------------------------

  /// Date token + amount candidates, computed once per line so style,
  /// layout and row building all agree on what a line holds.
  static _LineShape _shape(String line, Currency currency) {
    var masked = line;
    String? dateToken;
    // Only a *plausible* date reads as one: `120.00` starts with what the
    // bare-pair branch could match (`20.00`), but month 20 does not exist —
    // calling that a date would mask a real amount (e12 §5 item lines).
    for (final dm in _dateRe.allMatches(line)) {
      if (!_plausibleDate(dm.group(0)!)) continue;
      dateToken = dm.group(0)!;
      masked = line.replaceRange(dm.start, dm.end, '~' * dateToken.length);
      break;
    }
    final amounts = <_Amount>[];
    for (final m in _numTokenRe.allMatches(masked)) {
      final t = m.group(0)!;
      if (t.length < 2) continue; // single digit: memo/reference noise
      final digits = int.tryParse(t.replaceAll(RegExp(r'\D'), ''));
      if (digits != null &&
          digits >= 1900 &&
          digits <= 2100 &&
          RegExp(r'^[-+]?\d{4}$').hasMatch(t)) {
        continue; // bare year
      }
      final parsed = parseAmountCell(t, currency);
      if (parsed == null) continue;
      // Reference/account numbers are digit runs the amount parser
      // faithfully reads as absurd money; statement rows stay sane.
      if (parsed.minor ~/ currency.pow10 > 9999999) continue;
      amounts.add(
        _Amount(
          start: m.start,
          end: m.end,
          minor: parsed.minor,
          // A bare integer under 1 000 000 on a decimal currency is the
          // classic shape of a reference number wearing an amount's
          // clothes; keep it, but amber if it stands alone.
          bareInt: currency.minorUnits > 0 && RegExp(r'^\d{1,6}$').hasMatch(t),
          explicitSign:
              t.startsWith('-') ||
                  t.startsWith('(') ||
                  t.endsWith('-') ||
                  t.endsWith(')')
              ? false
              : t.startsWith('+')
              ? true
              : null,
        ),
      );
    }
    // Right-to-left order: `amounts.first` is the right-most numeral.
    amounts.sort((a, b) => b.start.compareTo(a.start));
    return _LineShape(
      dateToken: dateToken,
      amounts: amounts,
      hasLetters: RegExp(r'[A-Za-zÀ-ÿ]{3,}').hasMatch(line),
    );
  }

  /// ISO, `d1 x d2 x yyyy` or a year-less `d1 x d2`. Values above 12
  /// disambiguate at document level (see [_dayFirst]), never per row.
  static final RegExp _dateRe = RegExp(
    r'\d{4}-\d{1,2}-\d{1,2}'
    r'|\d{1,2}[/.-]\d{1,2}[/.-]\d{4}'
    r'|\d{1,2}[/.]\d{1,2}(?![\d/.-])',
  );

  /// Whether a date-shaped token could actually name a calendar date, in
  /// either day/month order. Day-first documents (31.12.) stay plausible;
  /// `20.00`, `80.00`, `24.60` do not and keep their amount meaning.
  static bool _plausibleDate(String t) {
    final p = [for (final s in t.split(RegExp(r'[/.-]'))) int.tryParse(s)];
    if (p.any((e) => e == null)) return false;
    final n = p.cast<int>();
    bool month(int v) => v >= 1 && v <= 12;
    bool day(int v) => v >= 1 && v <= 31;
    if (n.length == 3) {
      if (t.contains('-') && n[0] >= 1900) return month(n[1]) && day(n[2]);
      return day(n[0]) && month(n[1]) && n[2] >= 1900 ||
          month(n[0]) && day(n[1]) && n[2] >= 1900;
    }
    if (n.length == 2) {
      return month(n[0]) && day(n[1]) || month(n[1]) && day(n[0]);
    }
    return false;
  }

  /// Day-first vs month-first for slash dates: document vote from values
  /// above 12 in year-ful dates; no evidence keeps `MM/dd` (US statements).
  static bool _dayFirst(List<String> lines) {
    var dayVotes = 0, monthVotes = 0;
    for (final l in lines) {
      for (final m in _dateRe.allMatches(l)) {
        final parts = m.group(0)!.split(RegExp(r'[/.-]'));
        if (parts.length != 3) continue;
        final y = int.tryParse(parts[2]);
        if (y == null || y < 1000) continue; // year-less pair proves nothing
        final a = int.tryParse(parts[0]) ?? 0;
        final b = int.tryParse(parts[1]) ?? 0;
        if (a > 12) dayVotes++;
        if (b > 12) monthVotes++;
      }
    }
    return dayVotes > monthVotes;
  }

  static DateTime? _resolveDate(
    String token, {
    required bool dayFirst,
    required DateTime? previous,
    required DateTime now,
  }) {
    DateTime? d;
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(token);
    if (iso != null) {
      d = parseDateWithFormat(token, 'yyyy-MM-dd');
    } else {
      final parts = token.split(RegExp(r'[/.-]')).map(int.parse).toList();
      if (parts.isEmpty) return null;
      final yearful = parts.length == 3;
      final y = yearful ? parts[2] : null;
      final a = parts[0], b = parts[1];
      // >12 proves the side; otherwise the document vote decides.
      final (day, month) = a > 12
          ? (a, b)
          : b > 12
          ? (b, a)
          : dayFirst
          ? (a, b)
          : (b, a);
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        if (yearful) {
          final cand = DateTime.utc(y!, month, day);
          if (cand.day == day && cand.month == month) d = cand;
        } else {
          var year = previous?.year ?? now.year;
          // Statement order is the law: December→January rolls forward.
          if (previous != null && previous.month >= 10 && month <= 2) {
            year = previous.year + 1;
          }
          var cand = DateTime.utc(year, month, day);
          if (cand.day != day || cand.month != month) return null;
          // Beyond the grace window means last year's December.
          if (cand.isAfter(now.add(const Duration(days: 92)))) {
            cand = DateTime.utc(year - 1, month, day);
          }
          d = cand;
        }
      }
    }
    if (d == null) return null;
    if (d.isBefore(now.subtract(const Duration(days: 366)))) return null;
    if (d.isAfter(now.add(const Duration(days: 92)))) return null;
    return d;
  }

  /// True when the token itself carries a full year — year-less rows get
  /// their year carried from the previous row (an inference) and go amber.
  static bool _hasYearOnPaper(String token) {
    if (RegExp(r'^\d{4}-\d{1,2}-\d{1,2}$').hasMatch(token)) return true;
    final parts = token.split(RegExp(r'[/.-]'));
    return parts.length == 3 && (int.tryParse(parts[2]) ?? 0) >= 1000;
  }

  // --- amount ----------------------------------------------------------------

  /// Right-most is normally the amount; with a running-balance column the
  /// right-most is the balance and the amount sits left of it (card and
  /// bank statements agree on the column order).
  static ({int minor, bool ambiguous, bool? explicitSign})? _pickAmount(
    _LineShape shape, {
    required bool balanceColumn,
  }) {
    final a = shape.amounts;
    if (a.isEmpty) return null;
    if (balanceColumn && a.length >= 2) {
      // Equal values: the OCR printed one column twice — one amount.
      final left = a[1], right = a.first;
      final chosen = left.minor == right.minor ? right : left;
      return (
        minor: chosen.minor,
        explicitSign: chosen.explicitSign,
        ambiguous: true,
      );
    }
    // Extra numerals without a balance column are reference numbers — the
    // reading might be wrong, so amber. A lone bare whole number is just
    // as likely a reference as money (see _Amount.bareInt): also amber.
    final only = a.first;
    return (
      minor: only.minor,
      explicitSign: only.explicitSign,
      ambiguous: a.length > 1 || only.bareInt,
    );
  }

  // --- direction -------------------------------------------------------------

  static final RegExp _incomeRe = RegExp(
    r'\bDEPOSIT|\bREFUND|\bINTEREST\s+PAID|\bPAYMENT\s+RECEIVED'
    r'|\bTRANSFER\s+IN|\bCASH\s+IN|\bCHARGEBACK|\bCR\b',
    caseSensitive: false,
  );
  static final RegExp _expenseRe = RegExp(
    r'\bPURCHASE|\bPOS\b|\bACH\b|\bWITHDRAW|\bPAYMENT\s+MADE|\bFEE\b'
    r'|\bCHARGE\b|\bDR\b',
    caseSensitive: false,
  );

  /// Explicit sign wins; else the keyword occurring LATER in the line wins
  /// (`CREDIT CARD PURCHASE` reads into an expense); the unsigned default
  /// is expense — the amber row invites the reviewer's flip.
  static bool _direction(String line, bool? explicitIncome) {
    if (explicitIncome == true) return true;
    if (explicitIncome == false) return false;
    final inc = _lastMatch(_incomeRe, line);
    final exp = _lastMatch(_expenseRe, line);
    if (inc != null && exp == null) return true;
    if (exp != null && inc == null) return false;
    if (inc != null && exp != null) return inc < exp;
    return false;
  }

  static int? _lastMatch(RegExp re, String line) {
    int? pos;
    for (final m in re.allMatches(line)) {
      pos = m.start;
    }
    return pos;
  }

  // --- description -----------------------------------------------------------

  /// The line with its date and amount spans blanked out; masking happens
  /// right-to-left on original indexes so earlier spans keep their place.
  static String? _describe(String line, _LineShape shape) {
    final spans = <(int, int)>[];
    if (shape.dateToken != null) {
      final i = line.indexOf(shape.dateToken!);
      if (i >= 0) spans.add((i, i + shape.dateToken!.length));
    }
    for (final a in shape.amounts) {
      spans.add((a.start, a.end));
    }
    spans.sort((x, y) => y.$1.compareTo(x.$1));
    var s = line;
    for (final (st, en) in spans) {
      if (st < 0 || en > s.length) continue;
      s = s.replaceRange(st, en, ' ');
    }
    s = s
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\W_]+|[\W_]+$'), '')
        .trim();
    return s.isEmpty ? null : s;
  }

  // --- shared bits -----------------------------------------------------------

  static final RegExp _numTokenRe = RegExp(
    r'[-+(]?\d[\d.,]*\d[-)+]?|\b\d{1,2}\b',
  );

  static DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
}

final class _Amount {
  const _Amount({
    required this.start,
    required this.end,
    required this.minor,
    this.bareInt = false,
    this.explicitSign,
  });
  final int start;
  final int end;
  final int minor;

  /// A bare whole number (`123456`, no sign, mark or separator) on a
  /// currency that has cents: indistinguishable from a reference number,
  /// so a row built on it alone goes amber.
  final bool bareInt;

  /// false = minus/parens (expense), true = leading `+` (income),
  /// null = unsigned (keywords decide).
  final bool? explicitSign;
}

final class _LineShape {
  const _LineShape({
    required this.dateToken,
    required this.amounts,
    required this.hasLetters,
  });

  final String? dateToken;

  /// Amount candidates ordered RIGHT to left, date token excluded.
  final List<_Amount> amounts;
  final bool hasLetters;

  bool get hasAmount => amounts.isNotEmpty;
}
