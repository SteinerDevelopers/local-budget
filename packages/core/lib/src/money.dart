import 'currency.dart';

/// Money as an immutable integer count of **minor units** (cents, sen, …).
///
/// Floating point never touches an amount at rest — the single most important
/// invariant in a budgeting app (see feasibility §5, "money as integer minor
/// units"). Arithmetic is exact; only display and FX conversion round, and
/// only explicitly.
final class Money implements Comparable<Money> {
  /// Construct from an exact minor-unit count (may be negative for refunds).
  const Money(this.minorUnits, this.currency);

  /// Construct from a major-unit integer, e.g. `Money.fromMajor(12, USD)`.
  factory Money.fromMajor(int major, Currency currency) =>
      Money(major * currency.pow10, currency);

  /// Zero in [currency].
  factory Money.zero(Currency currency) => Money(0, currency);

  /// Exact minor-unit amount (cents). The canonical storage form.
  final int minorUnits;

  final Currency currency;

  bool get isZero => minorUnits == 0;
  bool get isPositive => minorUnits > 0;
  bool get isNegative => minorUnits == 0 ? false : minorUnits < 0;

  Money operator +(Money other) {
    _sameCurrency(other, '+');
    return Money(minorUnits + other.minorUnits, currency);
  }

  Money operator -(Money other) {
    _sameCurrency(other, '-');
    return Money(minorUnits - other.minorUnits, currency);
  }

  Money operator -() => Money(-minorUnits, currency);

  /// Sum, guarding against mixed currencies (which is always a bug here).
  static Money sum(Iterable<Money> amounts, Currency currency) {
    var total = 0;
    for (final a in amounts) {
      if (a.currency.code != currency.code) {
        throw ArgumentError(
            'cannot sum ${a.currency.code} into ${currency.code}');
      }
      total += a.minorUnits;
    }
    return Money(total, currency);
  }

  /// Proportional split by [weights] using largest-remainder apportionment:
  /// exact, deterministic, and the parts always re-sum to `this` (ties go to
  /// the lower index).
  List<Money> split(List<int> weights) {
    assert(weights.isNotEmpty && weights.every((w) => w > 0));
    final totalWeight = weights.fold<int>(0, (a, b) => a + b);
    final floors = <int>[];
    final remainders = <double>[];
    var allocated = 0;
    for (final w in weights) {
      final exact = minorUnits * w / totalWeight;
      final f = exact.floor();
      floors.add(f);
      remainders.add(exact - f);
      allocated += f;
    }
    final leftover = minorUnits - allocated; // 0 .. weights.length-1
    final order = List.generate(weights.length, (i) => i)
      ..sort((a, b) {
        final byRem = remainders[b].compareTo(remainders[a]);
        return byRem != 0 ? byRem : a.compareTo(b);
      });
    for (var i = 0; i < leftover; i++) {
      floors[order[i]] += 1;
    }
    return [for (final f in floors) Money(f, currency)];
  }

  /// Convert with [rate] (units of target currency per 1 unit of source),
  /// rounding half-away-from-zero at the *target* currency's minor step.
  /// Rounding is explicit because FX conversion is the only place it happens
  /// outside display (feasibility §5: one network touch, cached rates).
  Money convertTo(Currency target, double rate) {
    if (rate.isNaN || rate <= 0) {
      throw ArgumentError.value(rate, 'rate', 'must be > 0');
    }
    final scale = target.pow10 / currency.pow10;
    final converted = minorUnits * rate * scale;
    return Money(_roundHalfAway(converted), target);
  }

  /// Major units as double — **display/formatting only**, never storage.
  double get major => minorUnits / currency.pow10;

  /// Locale-free display form: `$1,234.56`, `¥1,485`, `-€12,345` (German
  /// comma comes from the currency's convention only in parse; display here
  /// is the canonical dot form — the UI layer may re-localize).
  String format() {
    final sign = minorUnits < 0 ? '-' : '';
    final abs = minorUnits.abs();
    final intPart = (abs ~/ currency.pow10).toString();
    final grouped = _groupThousands(intPart);
    if (currency.minorUnits == 0) return '$sign${currency.symbol}$grouped';
    final frac =
        (abs % currency.pow10).toString().padLeft(currency.minorUnits, '0');
    return '$sign${currency.symbol}$grouped.$frac';
  }

  static String _groupThousands(String digits) {
    if (digits.length <= 3) return digits;
    final tail = digits.substring(digits.length - 3);
    return '${_groupThousands(digits.substring(0, digits.length - 3))},$tail';
  }

  /// Parse a user/OCR string in [currency]. Accepts currency symbols/prefix
  /// codes, thousands separators (space, nbsp, comma or dot depending on the
  /// decimal convention), and a leading minus.
  ///
  /// **Total function**: every input yields a [Money] or null — it never
  /// throws, so the E2 ingest pipeline can call it blindly on raw OCR text.
  /// Amounts beyond ~int64 range (e.g. a misread barcode) are null, not an
  /// exception.
  ///
  /// [decimalComma] = true for `1.234,56`; false for `1,234.56`. Auto-detected
  /// when null: the last separator character decides the decimal one.
  static Money? tryParse(String raw, Currency currency, {bool? decimalComma}) {
    var s = raw.trim().replaceAll('\u00A0', ' ');
    if (s.isEmpty) return null;

    var negative = false;
    if (s.startsWith('-') || s.startsWith('−')) {
      negative = true;
      s = s.substring(1).trim();
    } else if (s.startsWith('(') && s.endsWith(')')) {
      negative = true;
      s = s.substring(1, s.length - 1).trim();
    }

    // Strip a trailing minus style used by some EU receipts ("12,34-").
    if (s.endsWith('-') || s.endsWith('−')) {
      negative = true;
      s = s.substring(0, s.length - 1).trim();
    }

    // Strip leading symbols/ISO codes: "$", "US$", "€ ", "USD ", "kr ", "R$".
    s = s.replaceFirst(RegExp(r'^(?:[A-Z]{3}\s?|[^\d.,\-\s]){1,4}\s?'), '');
    // Strip any remaining non-digit/non-separator chars.
    s = s.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (s.isEmpty) return null;

    final lastComma = s.lastIndexOf(',');
    final lastDot = s.lastIndexOf('.');
    if (s.endsWith('.') || s.endsWith(',')) return null; // trailing separator
    final useCommaAsDecimal =
        decimalComma ?? _autoDecimalComma(s, lastComma, lastDot);

    String digits;
    if (useCommaAsDecimal) {
      digits = s.replaceAll('.', '').replaceAll(',', '.');
    } else {
      digits = s.replaceAll(',', '');
    }

    // Two decimal separators after normalisation => malformed.
    if (digits.indexOf('.') != digits.lastIndexOf('.')) return null;

    final dotPos = digits.indexOf('.');
    var intPart = dotPos == -1 ? digits : digits.substring(0, dotPos);
    var fracPart = dotPos == -1 ? '' : digits.substring(dotPos + 1);
    if (intPart.isEmpty && fracPart.isEmpty) return null;
    if (intPart.isEmpty) intPart = '0';
    // Total-contract guard (hardening #21): the int.parse calls below throw
    // FormatException once the digits exceed int64 (a 40-digit barcode run
    // parses fine as a *string* — as a number it is simply "not an amount").
    intPart = intPart.replaceFirst(RegExp('^0+(?=\\d)'), '');
    if (intPart.length > 18 - currency.minorUnits) return null;

    // More fraction digits than the currency has => round the excess.
    if (fracPart.length > currency.minorUnits) {
      final keep = fracPart.substring(0, currency.minorUnits);
      final roundUp = int.parse(fracPart[currency.minorUnits]) >= 5;
      fracPart = keep;
      final value =
          int.parse('$intPart$keep'.padLeft(currency.minorUnits + 1, '0')) +
              (roundUp ? 1 : 0);
      // carry handled implicitly by value math below
      intPart = (value ~/ currency.pow10).toString();
      fracPart =
          (value % currency.pow10).toString().padLeft(currency.minorUnits, '0');
    } else {
      fracPart = fracPart.padRight(currency.minorUnits, '0');
    }

    final minor = int.parse('$intPart$fracPart') * (negative ? -1 : 1);
    return Money(minor, currency);
  }

  /// Decide whether a comma is the decimal separator when the caller did not
  /// pass an explicit locale.
  ///
  /// Rules (documented quirk): a digits-string shaped `1,234` / `1.234` /
  /// `12.345.678` — one separator type, every segment after a separator
  /// exactly 3 digits, first segment 1–3 — is read as *grouping*, not a
  /// decimal. This makes `¥1,500` = ¥1500 and `1.234` = 1234, at the cost of
  /// misreading a 3-decimal amount like `10.500` (only BHD/KWD have 3 minor
  /// units; pass `decimalComma` explicitly for those locales).
  static bool _autoDecimalComma(String s, int lastComma, int lastDot) {
    if (lastComma != -1 && lastDot != -1) return lastComma > lastDot;
    if (lastComma == -1 && lastDot == -1) return false;
    final sep = lastComma != -1 ? ',' : '.';
    final grouped = RegExp(r'^\d{1,3}(?:[' + sep + r']\d{3})+$');
    if (grouped.hasMatch(s)) return sep == ',' ? false : false; // grouping
    return sep ==
        ','; // lone comma => decimal comma locale; lone dot => decimal
  }

  static int _roundHalfAway(double v) =>
      v >= 0 ? (v + 0.5).floor() : -((-v + 0.5).floor());

  void _sameCurrency(Money other, String op) {
    if (currency.code != other.currency.code) {
      throw ArgumentError(
          'cannot $op ${currency.code} with ${other.currency.code}');
    }
  }

  @override
  int compareTo(Money other) {
    if (currency.code != other.currency.code) {
      throw ArgumentError('cannot compare ${currency.code} with '
          '${other.currency.code}');
    }
    return minorUnits.compareTo(other.minorUnits);
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currency.code == currency.code;

  @override
  int get hashCode => Object.hash(minorUnits, currency.code);

  @override
  String toString() => '$minorUnits ${currency.code}';
}
