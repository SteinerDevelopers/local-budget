/// E13 §3 — merchant-name sanity gate.
///
/// Raster/screen photographs OCR junk lines (`BOUI FVAFD`) that sail through
/// every structural guard and ship as the payee. This gate answers one
/// question — *could this word be a pronounceable English-ish brand?* — and
/// may only ever widen silence: callers drop a flagged line to null or to a
/// corroborated alternative, never invent or rewrite text.
class PayeeSanity {
  PayeeSanity._();

  /// Attested English word-initial consonant clusters. Anything multi-letter
  /// and outside this list with no early vowel is raster territory.
  static const Set<String> _onsets = {
    'bl',
    'br',
    'ch',
    'cl',
    'cr',
    'dr',
    'fl',
    'fr',
    'gl',
    'gr',
    'kl',
    'kn',
    'kr',
    'ph',
    'pl',
    'pr',
    'qu',
    'rh',
    'sc',
    'sch',
    'scr',
    'sh',
    'sk',
    'sl',
    'sm',
    'sn',
    'sp',
    'spl',
    'spr',
    'sq',
    'squ',
    'st',
    'sw',
    'str',
    'th',
    'thr',
    'tr',
    'tw',
    'wh',
  };

  /// Real all-consonant brands, seeded from bounces only (advisor-flagged
  /// `AMZN MKTP` — Amazon's OCR-normal payee). Grows from field evidence.
  static const Set<String> _brandPass = {
    'AMZN MKTP',
    'AMZN*MKT',
    'AMZN MKTP US',
  };

  static bool _isVowel(String c) => 'aeiouy'.contains(c);

  /// True when [line] reads as unpronounceable OCR junk rather than a name.
  static bool junkName(String line) {
    final up = line.toUpperCase();
    for (final brand in _brandPass) {
      if (up.contains(brand)) return false;
    }
    for (final m in RegExp(r'[A-Za-zÀ-ÿ]{3,}').allMatches(line)) {
      if (_junkToken(m.group(0)!)) return true;
    }
    return false;
  }

  static bool _junkToken(String tok) {
    final t = tok.toLowerCase();
    // Raster echo runs: AAAAA / IIIII — fewer than three distinct letters.
    // 1–3 letter tokens are letter-brand territory (XYZ, TGI, CNN):
    // the pronunciation rules below only speak for real words.
    if (t.length <= 3) return false;
    if (t.split('').toSet().length < 3) return true;
    final firstVowel = t.split('').indexWhere(_isVowel);
    if (firstVowel < 0) {
      // All consonants: XYZ / CNN / TGI at 1–3 letters are letter brands;
      // four or more (FVAFD) is noise.
      return t.length >= 4;
    }
    if (firstVowel == 0) return false; // starts on a vowel
    final cluster = t.substring(0, firstVowel);
    if (cluster.length == 1) return false;
    // A multi-consonant onset that no English word carries (FVAFD → 'fv').
    return !_onsets.contains(cluster);
  }

  /// `TOTAL: $45.99` — an amount word leading a line that carries digits is
  /// arithmetic prose, not a merchant (`TOTAL WINE & SPIRITS` has no digits
  /// and stays a keeper). E13 corpus case.
  static bool totalishWithDigits(String line) =>
      RegExp(r'^(TOTAL|SUBTOTAL|BALANCE|AMOUNT)\b', caseSensitive: false)
          .hasMatch(line.trim()) &&
      RegExp(r'\d').hasMatch(line);

  // --- digit-leading merchant shapes (E13 §4) ------------------------------

  static final RegExp _merchantWordRe = RegExp(
    r'\b(MARKET|STORE|SHOP|CAF[EÉ]|DELI|DINER|PIZZA|FOODS|FLOWERS|BURGER|'
    r'BAR|SALON|PHARMACY|STATION|GARAGE|LAUNDROMAT|MOTEL|WORKS|SUPPLY|'
    r'ONLY|CO|INC|LLC)\b',
    caseSensitive: false,
  );
  static final RegExp _phoneRe = RegExp(r'\d{3}[- ]\d{4}|\d{7}');
  static final RegExp _discountRe = RegExp(
    r'^\d+(\s*(OFF|PERCENT)\b|\s*[%¢]|\s*FOR\s)',
    caseSensitive: false,
  );
  static final RegExp _dateRe = RegExp(r'^\d{1,2}[/.-]\d{1,2}');

  /// `99¢ ONLY`, `24 HOUR MARKET`, `1-800-FLOWERS` — real merchants the old
  /// blanket `^\d` reject killed. Order is deliberate (advisor cases):
  /// phone shape is lethal always; a merchant word outranks date *and*
  /// discount shapes (`99¢ ONLY` and `24/7 MARKET` live, `03/15 DUE` and
  /// `10% DISCOUNT` die); with no vocabulary a second printed occurrence
  /// is the only proof. Junk-shaped lines never survive.
  static bool digitLeadingMerchant(String line, List<String> lines) {
    if (_phoneRe.hasMatch(line)) return false;
    if (!RegExp(r'\b[A-Za-zÀ-ÿ]{3,}\b').hasMatch(line)) return false;
    if (junkName(line)) return false;
    if (_merchantWordRe.hasMatch(line)) return true;
    if (_discountRe.hasMatch(line) || _dateRe.hasMatch(line)) return false;
    final up = line.trim().toUpperCase();
    return lines.where((l) => l.trim().toUpperCase() == up).length >= 2;
  }
}
