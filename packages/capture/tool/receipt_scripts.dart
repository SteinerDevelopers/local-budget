// #31 — synthetic receipt scripts for the benchmark corpus.
//
// Two scripts per the plan risk row (§4.4): `latin` (US retail receipt) and
// `cyrillic` (RU cafe/retail). Content is generated from a seeded RNG so the
// exact same corpus comes out of every run, and every image carries the
// ground truth (merchant, ISO date, total in cents) that the benchmark
// scores against. Amounts are plain decimal (no decimal comma) on purpose:
// the matrix this suite measures is *screenshot legibility*, not number
// notation.

import 'dart:math';

/// One generated receipt plus the truth we score the pipeline against.
class ReceiptScript {
  ReceiptScript({
    required this.script,
    required this.currency,
    required this.lines,
    required this.merchant,
    required this.date,
    required this.totalCents,
  });

  final String script;
  final String currency;
  final List<String> lines;
  final String merchant;
  final DateTime date;
  final int totalCents;
}

String _money(int cents) => (cents / 100).toStringAsFixed(2);

ReceiptScript makeLatin(Random rnd) {
  const merchants = [
    'MARKET STREET GROCERS',
    'CORNER FOOD MART',
    'QUICKSTOP MARKET',
    'FRESH DAYS GROCERY',
  ];
  const pool = [
    ('BANANAS', 159),
    ('MILK 2PCT', 349),
    ('BREAD WHEAT', 275),
    ('EGGS LARGE', 429),
    ('GROUND COFFEE', 699),
    ('ORANGE JUICE', 379),
    ('PASTA', 119),
    ('YOGURT GREEK', 549),
    ('FROZEN PIZZA', 725),
    ('SPARKLING WATER', 499),
  ];
  final merchant = merchants[rnd.nextInt(merchants.length)];
  // Day > 12 keeps the numeric date unambiguous (US MM/DD/YYYY layout).
  final date = DateTime(2026, 1 + rnd.nextInt(12), 13 + rnd.nextInt(16));
  final order = pool.toList()..shuffle(rnd);
  final chosen = order.sublist(0, 3 + rnd.nextInt(3));

  final lines = <String>[
    merchant,
    '1420 HARBOUR WAY',
    'TEL 555-0${100 + rnd.nextInt(900)}',
    '${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}/${date.year}',
    'CASHIER ${10 + rnd.nextInt(90)}',
    '',
  ];
  var subtotal = 0;
  for (final (name, unit) in chosen) {
    final qty = 1 + rnd.nextInt(3);
    final ext = unit * qty;
    subtotal += ext;
    lines.add('$qty $name ${_money(unit)} ${_money(ext)}');
  }
  final tax = (subtotal * 0.0825).round();
  final total = subtotal + tax;
  lines.addAll([
    '',
    'SUBTOTAL ${_money(subtotal)}',
    'TOTAL TAX 8.25% ${_money(tax)}',
    'TOTAL ${_money(total)}',
    'CASH ${_money(total + 1000)}',
    'CHANGE ${_money(1000 - (total % 100))}',
    '',
    'THANK YOU - VISIT SOON!',
  ]);
  return ReceiptScript(
    script: 'latin',
    currency: 'USD',
    lines: lines,
    merchant: merchant,
    date: date,
    totalCents: total,
  );
}

ReceiptScript makeCyrillic(Random rnd) {
  const merchants = [
    'КАФЕ ВЕТЕР',
    'СТОЛОВАЯ РУСЬ',
    'ПЕКАРНЯ ХЛЕБ',
    'МАГАЗИН РОМАШКА',
  ];
  const pool = [
    ('КОФЕ', 12000),
    ('ЧАЙ', 9000),
    ('БУЛОЧКА', 6550),
    ('САЛАТ ОВИЩ', 21000),
    ('ПИЦА', 35000),
    ('МОЛОКО', 8900),
    ('ХЛЕБ', 4500),
    ('СИР', 15500),
  ];
  final merchant = merchants[rnd.nextInt(merchants.length)];
  // DD.MM.YYYY, day > 12: unambiguous day-first (the opposite of the latin
  // script's assumption — exactly the confusion this matrix exposes).
  final date = DateTime(2026, 1 + rnd.nextInt(12), 13 + rnd.nextInt(16));
  final order = pool.toList()..shuffle(rnd);
  final chosen = order.sublist(0, 3 + rnd.nextInt(3));

  final lines = <String>[
    merchant,
    'МОСКВА ТВЕРСКАЯ 12',
    'ТЕЛ 555-0${100 + rnd.nextInt(900)}',
    '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.${date.year}',
    'ЗАКАЗ ${100 + rnd.nextInt(900)}',
    '',
  ];
  var total = 0;
  for (final (name, unit) in chosen) {
    final qty = 1 + rnd.nextInt(2);
    final ext = unit * qty;
    total += ext;
    lines.add('$qty $name ${_money(unit)} ${_money(ext)}');
  }
  lines.addAll([
    '',
    'ИТОГО ${_money(total)}',
    'НАЛИЧНЫМИ ${_money(total)}',
    'СДАЧА 0.00',
    '',
    'СПАСИБО ЗА ПОКУПКУ',
  ]);
  return ReceiptScript(
    script: 'cyrillic',
    currency: 'USD', // RUB is not in core's table; amounts render bare.
    lines: lines,
    merchant: merchant,
    date: date,
    totalCents: total,
  );
}

ReceiptScript makeReceipt(String script, Random rnd) =>
    script == 'cyrillic' ? makeCyrillic(rnd) : makeLatin(rnd);

/// Longest line of a receipt — the rasteriser sizes its scale to fit.
int maxLineLength(ReceiptScript r) =>
    r.lines.fold<int>(0, (a, l) => l.length > a ? l.length : a);
