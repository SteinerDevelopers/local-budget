// E11 §6 — synthetic bill & bank-statement scripts for the benchmark corpus.
//
// Same philosophy as receipt_scripts.dart: seeded RNG, plain pixels, ground
// truth alongside every image. Statements carry the row-level truth (date,
// minor units, income flag) that `StatementLines` is scored against; bills
// carry payee/amount-due/due-date for `BillDraft`. Amount notation is the
// *document's own* notation (US decimal dot, RU decimal comma) on purpose:
// unlike the receipt matrix, number notation is exactly what the E11 parsers
// must survive.
//
// The clock for generated dates and the scorer's `now` both come from the
// manifest's `benchNow`, so a corpus scored months later measures the same
// thing.

import 'dart:math';

/// Fixed evaluation clock (2026-11-04T12:00Z), mirrored into the manifest.
final DateTime kBenchNow = DateTime.utc(2026, 11, 4, 12).toLocal();

class StatementRowTruth {
  StatementRowTruth(this.date, this.minor, this.isIncome);
  final DateTime date;
  final int minor;
  final bool isIncome;
  Map<String, Object?> toJson() =>
      {'date': isoDate(date), 'minor': minor, 'isIncome': isIncome};
}

class StatementScript {
  StatementScript({
    required this.script,
    required this.currency,
    required this.lines,
    required this.rows,
  });

  final String script;
  final String currency;
  final List<String> lines;
  final List<StatementRowTruth> rows;
}

class BillScript {
  BillScript({
    required this.script,
    required this.currency,
    required this.lines,
    required this.payee,
    required this.amountCents,
    required this.dueDate,
  });

  final String script;
  final String currency;
  final List<String> lines;
  final String payee;
  final int amountCents;
  final DateTime dueDate;
}

String _dot2(int cents) => (cents / 100).toStringAsFixed(2);

/// `1,204.60` with thousands commas (US ledger style).
String _usd(int cents) {
  final s = _dot2(cents);
  final i = s.indexOf('.');
  final whole = s.substring(0, i);
  if (whole.length <= 3) return s;
  final buf = StringBuffer();
  for (var k = 0; k < whole.length; k++) {
    if (k > 0 && (whole.length - k) % 3 == 0) buf.write(',');
    buf.write(whole[k]);
  }
  return '$buf.${s.substring(i + 1)}';
}

/// `2026-11-04` — the manifest's date notation.
String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// --- statements ------------------------------------------------------------

const _usDesc = [
  'CORNER FOOD MART',
  'FUEL STATION 12',
  'CITY TRANSIT CARD',
  'HARDWARE DEPOT',
  'COFFEE BEAN STAND',
  'PHOENIX PHARMACY',
  'STREAMING PLUS',
  'LAWN SERVICE CO',
];

const _ruDescSafe = [
  'МАГАЗИН ПРОДУКТЫ',
  'АЗС НОМЕР 14',
  'ПРОЕЗДНЫЕ БИЛЕТЫ',
  'РЕМОНТ ТЕЛЕФОНОВ',
  'АПТЕКА ЗДРАВУШКА',
  'САЛОН СВЯЗИ',
];

/// One statement: header noise + rows of `DATE DESC AMOUNT BALANCE`.
StatementScript makeStatement(String script, Random rnd) {
  final n = 5 + rnd.nextInt(4);
  final rows = <StatementRowTruth>[];
  final lines = <String>[];
  final ru = script == 'cyrillic';

  var balance = 180000 + rnd.nextInt(140000); // 1800.00 .. 3200.00
  if (ru) {
    lines.addAll([
      'СЕВЕРО-ЗАПАДНЫЙ БАНК',
      'СЧЕТ 4081 7781 4471 0296',
      'ОПЕРАЦИИ ПО СЧЕТУ',
    ]);
  } else {
    lines.addAll([
      'NORTHFIELD CREDIT UNION',
      'ACCOUNT 4471 0296',
      'DATE DESCRIPTION AMOUNT BALANCE',
    ]);
  }

  final month = 1 + rnd.nextInt(9);
  for (var i = 0; i < n; i++) {
    // Day > 12 keeps every date unambiguous in its own convention.
    final day = 13 + rnd.nextInt(16);
    final date = DateTime(2026, month, day);
    final income = i > 0 && rnd.nextInt(4) == 0;
    final desc = ru
        ? _ruDescSafe[rnd.nextInt(_ruDescSafe.length)]
        : _usDesc[rnd.nextInt(_usDesc.length)];
    final int amount;
    if (income) {
      amount = 120000 + rnd.nextInt(140000);
      balance += amount;
      rows.add(StatementRowTruth(date, amount, true));
    } else {
      amount = 800 + rnd.nextInt(8800);
      balance -= amount;
      rows.add(StatementRowTruth(date, amount, false));
    }
    // Income carries an explicit '+' — the one notation both ledgers agree
    // on; expenses stay unsigned like the real statements the parser saw.
    final amt =
        ru ? '+${_dot2(amount).replaceAll('.', ',')}' : '+${_dot2(amount)}';
    final plain = ru ? _dot2(amount).replaceAll('.', ',') : _dot2(amount);
    final bal = ru ? _dot2(balance).replaceAll('.', ',') : _usd(balance);
    lines.add('${_ruDate(date, ru)} $desc ${income ? amt : plain} $bal');
  }
  return StatementScript(
      script: script, currency: ru ? 'RUB' : 'USD', lines: lines, rows: rows);
}

String _ruDate(DateTime d, bool ru) => ru
    ? '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}'
    : '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';

// --- bills (US utility/subscription bills; latin script) --------------------

const _billPayees = [
  'ACME ELECTRIC COMPANY',
  'RIVER CITY WATER UTILITY',
  'CITY GAS WORKS',
  'CENTRUM BROADBAND',
];

BillScript makeBill(Random rnd) {
  final payee = _billPayees[rnd.nextInt(_billPayees.length)];
  final amount = 3000 + rnd.nextInt(13000);
  final minimum = (amount * 0.18).round().clamp(500, amount);
  // Due date within the next ~45 days of the bench clock — inside the
  // bill window `guessDueDate` reads. A day past the 12th keeps the
  // printed MM/DD token unambiguous, the same convention the receipt
  // corpus uses against `parseDateLoose`'s day-first tie.
  var due = kBenchNow.add(Duration(days: 3 + rnd.nextInt(42)));
  while (due.day <= 12) {
    due = due.add(const Duration(days: 1));
  }
  final lines = [
    payee,
    'ACCOUNT NUMBER 4471 2208',
    'SERVICE PERIOD OCT 01 - OCT 31',
    // `PREVIOUS BALANCE` next to `MINIMUM PAYMENT` reads as a *credit*
    // statement to the E2 classifier, whose anchor list has no bare
    // AMOUNT DUE; utility invoices print the prior cycle as an AMOUNT DUE
    // compound, so the corpus does too — and the bottom-up anchor must
    // still prefer the current cycle's amount.
    'PREVIOUS AMOUNT DUE ${_dot2(amount + 1200)}',
    'NEW CHARGES ${_dot2(amount)}',
    'AMOUNT DUE ${_dot2(amount)}',
    'MINIMUM PAYMENT ${_dot2(minimum)}',
    'DUE DATE ${_ruDate(due, false)}',
    'PAY BY MAIL OR ONLINE BEFORE THE DUE DATE',
  ];
  return BillScript(
      script: 'latin',
      currency: 'USD',
      lines: lines,
      payee: payee,
      amountCents: amount,
      dueDate: due);
}
