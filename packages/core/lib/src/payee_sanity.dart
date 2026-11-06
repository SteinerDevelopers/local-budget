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
}
