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
/// anchors, with one bill-route override: on a card statement the minimum
/// payment due outranks every balance (see [_minPayRe]); due-date and
/// frequency vocabulary is new.
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
    var total = h.guessTotal(lines);
    final due = guessDueDate(lines, now: at);
    final (freq, freqConfidence) = _guessFrequency(lines);
    var payee = merchant?.name;
    var payeeConfidence = merchant?.confidence ?? FieldConfidence.low;
    // A printed remit block names the payee outright — it outranks even a
    // high first-line guess, because on a provider statement that guess is
    // usually the logo ("MRA") and the line below it the paper's heading
    // ("MEDICAL STATEMENT OF SERVICE"), neither of which is who you pay
    // (Lance's radiology stub, 2026-11-05). With no remit block a heading
    // still never ships as the payee: the field stays honestly empty.
    final remit = _payeeAfterRemit(lines);
    if (remit != null) {
      payee = remit;
      payeeConfidence = FieldConfidence.high;
    } else {
      if (payee != null && _sheetTitle(payee)) {
        payee = null;
        payeeConfidence = FieldConfidence.low;
      }
      // Desk clutter (second tester bounce, 2026-11-05): a pen printed
      // with a brand name lay above the page's top edge, photo OCR read
      // that line before any document text, and the pen brand shipped as
      // the payee. A real provider is named more than once on the paper
      // (letterhead plus remit block) or owns an address block directly
      // under it; a lone uncorroborated line is replaced only when the
      // paper itself offers a corroborated name elsewhere. With no better
      // candidate the first guess stands — single-brand billers (one
      // logo line, no address) would otherwise lose their only name.
      if (payee != null && !_providerCorroborated(payee, lines)) {
        final alt = _firstCorroboratedName(lines);
        if (alt != null) {
          payee = alt;
          payeeConfidence = FieldConfidence.medium;
        }
      }
    }
    // A card statement is a BILL about one number: the minimum payment
    // due. The receipt route prefilling the NEW BALANCE (e2 §3) made
    // Lance's photographed Citi statement look like $7,355 of spend
    // instead of the $594.67 check actually due (tester bounce,
    // 2026-11-05). The standalone payment box is its own evidence — no
    // classification gate needed, and warning prose never reads as one.
    final minDue = _minimumPayment(lines, currency);
    if (minDue != null) total = minDue;
    // A photo of a web page OCRs the browser chrome before any logo
    // line, so a non-high merchant guess on a statement is usually
    // chrome, not the card company; the issuer vocabulary then names the
    // payee. A first-line hit (the printed/PDF statement) stays as-is —
    // "Citi Strata" is the brand line the owner reads (2026-11-05).
    if (h.classify(lines) == DocType.cardStatement &&
        (payee == null || payeeConfidence != FieldConfidence.high)) {
      final issuer = _issuerIn(lines);
      if (issuer != null) {
        payee = issuer;
        payeeConfidence = FieldConfidence.medium;
      }
    }
    return BillDraft._(
      payee: payee,
      payeeConfidence: payeeConfidence,
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

  // --- card-statement overrides -------------------------------------------

  /// A standalone minimum-payment line: `MINIMUM PAYMENT DUE`, `MINIMUM
  /// PAYMENT`, `MINIMUM DUE` — alone or followed by its amount. Warning
  /// prose (`Minimum Payment Warning: If you make only…`) is text *about*
  /// the minimum, not the payment box, so anything else trailing the label
  /// disqualifies the line (Lance's Citi statement carries both shapes).
  static final RegExp _minPayRe = RegExp(
    r'^MINIMUM(?:\s*(?:PAYMENT|PYMT|PMT))?(?:\s*DUE)?\s*[:\-]?\s*(.*)$',
    caseSensitive: false,
  );

  /// A line that is nothing but a money value (`$594.67`) — the answer to
  /// a label-only line when OCR splits the columns apart.
  static final RegExp _pureAmountRe = RegExp(
    r'^\(?\s*[-+]?\s*\$?\s*\d[\d,]*(?:\.\d{1,2})?\s*\$?\s*\)?$',
  );

  static ({Money amount, FieldConfidence confidence})? _minimumPayment(
    List<String> lines,
    Currency currency,
  ) {
    // Bottom-up like guessTotal: the payment stub at the foot of a
    // statement is the line the cardholder actually writes the check for.
    for (var i = lines.length - 1; i >= 0; i--) {
      final m = _minPayRe.firstMatch(lines[i].trim());
      if (m == null) continue;
      final rest = m.group(1)!.trim();
      String? raw;
      if (rest.isEmpty) {
        // Label and value on separate lines (the real Citi PDF's shape).
        for (var j = i + 1; j <= i + 2 && j < lines.length; j++) {
          final nxt = lines[j].trim();
          if (nxt.isEmpty) continue;
          if (_pureAmountRe.hasMatch(nxt)) raw = nxt;
          break; // a non-amount next line is prose — this label is not a box
        }
      } else if (_pureAmountRe.hasMatch(rest)) {
        raw = rest;
      }
      if (raw == null) continue;
      final minor = _toMinor(raw, currency);
      if (minor == null || minor <= 0) continue;
      return (
        amount: Money(minor, currency),
        confidence: FieldConfidence.high,
      );
    }
    return null;
  }

  static int? _toMinor(String raw, Currency currency) {
    final digits = raw.replaceAll(RegExp(r'[^0-9.]'), '');
    final v = double.tryParse(digits);
    if (v == null) return null;
    var scale = 1;
    for (var i = 0; i < currency.minorUnits; i++) {
      scale *= 10;
    }
    return (v * scale).round();
  }

  /// US card issuers by the words their statements actually print. Kept
  /// deliberately small — it is a floor for photo-OCR misses (a phone
  /// photo OCRs the browser URL bar before any logo line), not a brand
  /// database: a statement whose header read cleanly names itself better.
  static final List<(RegExp, String)> _issuers = [
    (RegExp(r'CITI\s+CARDS|CITIBANK|CITICARD|\bCITI\b'), 'Citi'),
    (RegExp(r'\bCHASE\b|JPMORGAN'), 'Chase'),
    (RegExp(r'CAPITAL\s+ONE'), 'Capital One'),
    (RegExp(r'\bDISCOVER\b'), 'Discover'),
    (RegExp(r'AMERICAN\s+EXPRESS|\bAMEX\b'), 'American Express'),
    (RegExp(r'BANK\s+OF\s+AMERICA'), 'Bank of America'),
    (RegExp(r'WELLS\s+FARGO'), 'Wells Fargo'),
    (RegExp(r'U\.?\s?S\.?\s+BANK'), 'U.S. Bank'),
    (RegExp(r'\bUSAA\b'), 'USAA'),
    (RegExp(r'NAVY\s+FEDERAL'), 'Navy Federal'),
  ];

  static String? _issuerIn(List<String> lines) {
    final text = lines.take(40).join(' ').toUpperCase();
    for (final (re, name) in _issuers) {
      if (re.hasMatch(text)) return name;
    }
    return null;
  }

  // --- payee --------------------------------------------------------------

  /// `MAKE CHECK PAYABLE (AND) REMIT TO:` — the payment stub's own label.
  /// Whatever follows it (same line, or the next printed line when OCR
  /// split the box) is the provider naming who to pay.
  static final RegExp _remitRe = RegExp(
    r'MAKE\s+CHECK\s+PAYABLE|\bREMIT(?:TANCE)?\s+TO\b',
    caseSensitive: false,
  );

  /// The stub label photographed small prints as a garble the full phrase
  /// misses (`NAKE CHECK PAYABLE AND REMIT T0:`); an all-caps PAYABLE on an
  /// all-caps line is still the remittance word. Lowercase "payable to the
  /// issuer" prose on a card coupon is deliberately NOT a label — the
  /// issuer vocabulary owns that route (2026-11-05 owner decision).
  static final RegExp _remitCapsRe = RegExp(r'\bPAYABLE\b');

  /// Address-shaped lines: `PO Box 830525 …`, `Birmingham AL 35283-0525`,
  /// `5908 Steiner Store Rd # R`.
  static final RegExp _addressishRe = RegExp(
    r'\b(?:PO\.?\s*BOX|BOX|STE|SUITE)\s*#?\d'
    r'|\b[A-Z]{2}\s+\d{5}(?:-\d{4})?\b'
    r'|\b\d+\s+[A-Z0-9][A-Z0-9\s.#-]*\b(?:ST|STREET|RD|ROAD|AVE|AVENUE|BLVD'
    r'|DR|DRIVE|LN|LANE|WAY|PKWY|HWY)\b',
    caseSensitive: false,
  );

  /// Browser chrome / URL lines never name a provider.
  static final RegExp _chromeRe = RegExp(
    r'https?://|www\.|\.(?:COM|NET|ORG|INFO)\b',
    caseSensitive: false,
  );

  /// Name-ish: short, digit-free (never the PO Box or account row), not a
  /// paper heading. Deeper picks in a window carry a word cap so warning
  /// prose cannot read as a payee.
  static bool _nameish(String s, {int? maxWords}) =>
      s.length >= 3 &&
      s.length <= 40 &&
      !s.contains(RegExp(r'\d')) &&
      (maxWords == null || s.split(RegExp(r'\s+')).length <= maxWords) &&
      !_sheetTitle(s);

  /// Professional-suffix tokens that END a provider name. The salvage
  /// below ships only a token run that stops on one, so merged address
  /// debris can never extend a name — and a bare "Birmingham AL" or a
  /// `City ST 20815` line can never impersonate a provider.
  static final RegExp _corpSuffixRe = RegExp(
    r'^(?:P\.?A|P\.?C|L\.?L\.?C|L\.?L\.?P|I\.?N\.?C|PLLC|MD|M\.D\.|DO|DDS|DPM)$',
  );

  /// Tokens that stop a name run dead: address words, URL chrome, '#'.
  static final RegExp _mergeStopRe = RegExp(
    r'^(?:PO|P\.O|BOX|DEPT|STE|SUITE|APT|WWW|HTTP|HTTPS)$'
    r'|\.(?:COM|NET|ORG|INFO)$',
    caseSensitive: false,
  );

  /// The provider name riding at the head of a column-merged row: leading
  /// tokens up to and including a professional suffix, stopping at any
  /// digit-bearing, `#`-bearing or address/URL token (the Coosea capture,
  /// 2026-11-05: tilt merged every band of the two-column stub, so the
  /// row under the remit label read `Montgomery Radiology Associates PA
  /// PO Box 830525 Dept #SF128` — no digit-free line existed and the pen
  /// brand shipped). Deliberately narrow: a suffix must be reached, two
  /// words at least, and the token after it must not be digit-shaped —
  /// `Chevy Chase MD 20815` is a mailing line, not a provider.
  static String? _mergedProviderPrefix(String line) {
    final toks = line.trim().split(RegExp(r'\s+'));
    final out = <String>[];
    for (var i = 0; i < toks.length; i++) {
      final t = toks[i];
      if (t.contains(RegExp(r'\d')) ||
          t.contains('#') ||
          _mergeStopRe.hasMatch(t)) {
        return null;
      }
      final bare = t.replaceAll(RegExp(r'[.,;:]+$'), '');
      out.add(t);
      if (_corpSuffixRe.hasMatch(bare)) {
        if (out.length < 2) return null;
        if (i + 1 < toks.length && toks[i + 1].contains(RegExp(r'\d'))) {
          return null; // `City MD 20815`: a state abbreviation, not PA.
        }
        return out.join(' ');
      }
    }
    return null;
  }

  /// All-caps paper headings — `MEDICAL STATEMENT OF SERVICE`, `FINAL
  /// NOTICE` — are document titles, not payees.
  static final RegExp _paperTitleRe = RegExp(
    r"^[A-Z][A-Z0-9&'\-\s]*"
    r"\b(?:STATEMENT|NOTICE|INVOICE|SUMMARY|REMINDER|SUMMONS"
    r"|HANDOUT|WORKSHEET)\b"
    r"[A-Z0-9&'\-\s]*$",
  );

  /// Demo-paper watermarks ("Sample credit card statement", CFPB handout) —
  /// mixed case, invisible to the all-caps sheet-title check above, but no
  /// real payee starts with a watermark word.
  static final RegExp _titlePrefixRe = RegExp(
    r'^(?:SAMPLE|SPECIMEN|EXAMPLE|DUMMY|TEST(?:ING)?)\b',
    caseSensitive: false,
  );

  /// Statement boilerplate section headings (`Payment Information`,
  /// `Account Summary`, `Transaction History`…). Printed two or three
  /// times per page, they out-vote real names, yet no payee reads like a
  /// section of someone else's paper.
  static final RegExp _sectionHeadingRe = RegExp(
    r'^\s*(?:IMPORTANT DATES|MESSAGE CENTER|INTEREST CALCULATION'
    r'|(?:PAYMENT|ACCOUNT|CUSTOMER|CONTACT|BILLING|ACTIVITY|TRANSACTION)'
    r'\s+(?:INFORMATION|INQUIRIES|DETAILS|HISTORY|SUMMARY))\s*$',
    caseSensitive: false,
  );

  /// Edition/issue banners printed above the document proper
  /// (`Summer 2022`, `Issue 4`, `Vol 11`): top-of-page, alone, and no
  /// payee's legal name is a bare season with a year.
  static final RegExp _editionBannerRe = RegExp(
    r'^\s*(?:SPRING|SUMMER|FALL|AUTUMN|WINTER|TERM|QUARTER|Q[1-4]'
    r'|VOL(?:UME)?|ISSUE|EDITION|SERIES|PAGE)\s*[.:]?\s*\d{1,4}\s*$',
    caseSensitive: false,
  );

  static bool _sheetTitle(String s) =>
      _paperTitleRe.hasMatch(s) ||
      _titlePrefixRe.hasMatch(s) ||
      _sectionHeadingRe.hasMatch(s) ||
      _editionBannerRe.hasMatch(s);

  static String? _payeeAfterRemit(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // Last label match on the line: `MAKE CHECK PAYABLE AND REMIT TO: X`
      // keeps everything after the *final* label.
      RegExpMatch? m;
      for (final cand in _remitRe.allMatches(line)) {
        m = cand;
      }
      if (m == null && line == line.toUpperCase()) {
        for (final cand in _remitCapsRe.allMatches(line)) {
          m = cand;
        }
      }
      if (m == null) continue;
      var tail =
          line.substring(m.end).replaceFirst(RegExp(r'^[:\s]+'), '').trim();
      // OCR lowercases the small connector after the label ("payable to
      // CITI CARDSs", CFPB raster device pass 2026-11); a payee never
      // begins with a lowercase English particle.
      tail = tail.replaceFirst(
        RegExp(r'^(?:to|the|of|a|an|in|at|onto|unto)\s+', caseSensitive: false),
        '',
      );
      // ML Kit can double the final glyph and keep the sentence dot
      // ("CITI CARDSs."); undo the doubling, then any trailing dot.
      tail = tail
          .replaceFirst(RegExp(r'(\w)\1\.+$', caseSensitive: false), r'$1')
          .replaceFirst(RegExp(r'\.+$'), '')
          .trim();
      if (!_nameish(tail)) tail = _mergedProviderPrefix(tail) ?? '';
      if (tail.isEmpty) {
        // OCR splits the stub box, and same-height columns interleave rows
        // (the remitter address block sits level with the remit box): take
        // the first name-ish line within four, skipping digit-bearing
        // address junk. Only the immediate next line prints unbounded —
        // deeper picks must look like a short name. A row too merged for
        // `_nameish` still yields its provider via the suffix salvage.
        for (var j = i + 1; j <= i + 4 && j < lines.length; j++) {
          final nxt = lines[j].trim();
          if (nxt.isEmpty) continue;
          final int? maxWords = j > i + 1 ? 4 : null;
          if (_nameish(nxt, maxWords: maxWords)) {
            tail = nxt;
            break;
          }
          final pre = _mergedProviderPrefix(nxt);
          if (pre != null && _nameish(pre, maxWords: maxWords)) {
            tail = pre;
            break;
          }
        }
      }
      if (tail.isNotEmpty) return tail;
    }
    return null;
  }

  /// A printed provider is corroborated by its own paper: named at least
  /// twice (letterhead + remit block), or owning an address block directly
  /// beneath it. Anything else may be desk clutter photographed with the
  /// document — a pen brand, a bag print, a bottle label.
  static bool _providerCorroborated(String name, List<String> lines) {
    final up = name.toUpperCase();
    var seen = 0;
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].toUpperCase().contains(up)) continue;
      seen++;
      for (var j = i + 1; j <= i + 2 && j < lines.length; j++) {
        final nxt = lines[j].trim();
        if (nxt.isEmpty) continue;
        if (_addressishRe.hasMatch(nxt)) return true;
        break; // an unrelated line follows: no address block under this one
      }
    }
    return seen >= 2;
  }

  /// The first name-ish line in the page's top region the paper corroborates.
  static String? _firstCorroboratedName(List<String> lines) {
    for (final raw in lines.take(12)) {
      var line = raw.trim();
      // Device trace 2026-11-05 (SL219A, photographed ENERGEL radiology
      // stub): the provider prints on one OCR line with its Access# field
      // (`Montgomery Radiology Associates PA Access#: 19803282-1-6282`), so
      // the digit guard killed an otherwise corroborated name and the
      // uncorroborated network logo shipped as the payee. The name is
      // everything before the labelled field.
      final label = _trailingFieldRe.firstMatch(line);
      if (label != null) line = line.substring(0, label.start).trim();
      if (!_nameish(line) || _chromeRe.hasMatch(line)) continue;
      if (_providerCorroborated(line, lines)) return line;
    }
    return null;
  }

  /// A labelled data field mid-line: `Access#: …`, `Account No: …`,
  /// `Ref # …`. Its prefix may be a name; the line as a whole never is.
  static final RegExp _trailingFieldRe = RegExp(
    r'\b(?:ACCESS|ACCT|ACCOUNT|REF|POLICY|GROUP)\s*(?:NO\.?|NUMBER|#)?\s*[:#]',
    caseSensitive: false,
  );

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
