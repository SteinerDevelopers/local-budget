import 'package:core/core.dart';

/// Input buffer for the QuickAdd keypad (design §2.2).
///
/// Pure logic, no Flutter: the sheet keeps one of these, the keypad calls
/// [digit]/[dot]/[back], and [money] is the exact minor-unit result — built
/// from string parts so floating point never touches a typed amount
/// (core's invariant, carried through the UI layer).
final class AmountPad {
  AmountPad({required this.currency});

  final Currency currency;

  /// Integer digits before separators — enough for any sane budget, and it
  /// keeps the 40 pt display from overflowing.
  static const int maxIntegerDigits = 9;

  String _buffer = '';

  bool get isEmpty => _buffer.isEmpty;

  /// What the 40 pt display shows: the raw typed digits, or a dimmed `0`
  /// placeholder before the first digit (§2.2 item 2).
  String get display => _buffer.isEmpty ? '0' : _buffer;
  bool get isPlaceholder => _buffer.isEmpty;

  int get _decimals => currency.minorUnits;

  void digit(String d) {
    assert(RegExp(r'^[0-9]$').hasMatch(d));
    final dot = _buffer.indexOf('.');
    if (dot < 0) {
      // No leading zeros (hardening #20): a lone '0' behaves like a
      // calculator's fresh display — the next digit replaces it, so the
      // buffer never grows '00' or '007' into the 40 pt display.
      if (_buffer == '0') {
        _buffer = d;
        return;
      }
      if (_buffer.length >= maxIntegerDigits) return;
      _buffer += d;
    } else {
      if (_buffer.length - dot - 1 >= _decimals) return; // fraction full
      _buffer += d;
    }
  }

  void dot() {
    if (_decimals == 0 || _buffer.contains('.')) return;
    if (_buffer.isEmpty) {
      _buffer = '0.';
      return;
    }
    // A lone leading zero absorbs the dot: "0." not "00.".
    if (_buffer == '0') {
      _buffer = '0.';
      return;
    }
    _buffer += '.';
  }

  void back() {
    if (_buffer.isNotEmpty) _buffer = _buffer.substring(0, _buffer.length - 1);
  }

  void clear() => _buffer = '';

  /// Prefill from an extracted total (E2 Review sheet): the same buffer the
  /// keypad would have typed, trailing fraction zeros trimmed exactly like a
  /// hand-typed `12.3`. Zero clears to the dimmed placeholder — an empty
  /// pad IS the "no total found" state (§2.3), never a fake `0` entry.
  void fill(Money m) {
    final units = m.minorUnits;
    if (units <= 0) {
      _buffer = '';
      return;
    }
    final major = units ~/ currency.pow10;
    final frac = units % currency.pow10;
    if (_decimals == 0 || frac == 0) {
      _buffer = '$major';
      return;
    }
    var f = frac.toString().padLeft(_decimals, '0');
    while (f.endsWith('0')) {
      f = f.substring(0, f.length - 1);
    }
    _buffer = '$major.$f';
  }

  /// Exact minor-unit value of the buffer; 0 while empty. The padded-fraction
  /// split means `12.4` in USD is 1240, in JPY (0 decimals) `12.` is 12.
  Money get money {
    if (_buffer.isEmpty) return Money.zero(currency);
    final dot = _buffer.indexOf('.');
    final major = dot < 0 ? _buffer : _buffer.substring(0, dot);
    final rawFrac = dot < 0 ? '' : _buffer.substring(dot + 1);
    final frac = rawFrac.padRight(_decimals, '0');
    final majorUnits = (major.isEmpty ? '0' : major);
    final minor =
        (int.parse(majorUnits) * currency.pow10) +
        (frac.isEmpty ? 0 : int.parse(frac));
    return Money(minor, currency);
  }
}
