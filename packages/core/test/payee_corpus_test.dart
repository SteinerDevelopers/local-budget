// E13 §5 — the consolidated bounce corpus. Every row is a real incident
// (tester email, device session, or the desk-photo traces recorded in the
// code comments) or one of the two E13 classes; the table is the regression
// bar: keepers never drop, bounces never pass. Line sets for the historical
// bounces are copied verbatim from bill_heuristics_test.dart.
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  final usd = Currency.resolve('USD');
  final now = DateTime(2026, 11, 2);

  const citiPrinted = [
    'Citi Strata',
    'www.citicards.com',
    'OCTOBER STATEMENT',
    'Billing Period: 09/17/26-10/16/26',
    'New balance as of 10/16/26:',
    r'$7,355.21',
    'Minimum payment due:',
    r'$594.67',
    'Payment due date:',
    '11/14/26',
  ];
  const citiChrome = [
    '9:20',
    'b.https://online.citicards.com/.../statements',
    'BILLING INQUIRIES AND CUSTOMER SERVICE',
    'BOX 6062 SIOUX FALLS, SD 57117',
    '1-800-555-0100, (TTY: 711)',
    'www.citicards.com',
    'OCTOBER STATEMENT',
    'Billing Period: 09/17/26-10/16/26',
    'New balance as of 10/16/26:',
    r'$7,355.21',
    'Minimum payment due:',
    r'$594.67',
    'Payment due date:',
    '11/14/26',
  ];
  const penStub = [
    'GELMASTER', // pen brand, above the page edge
    'MRA MONTGOMERY RADIOLOGY',
    'Montgomery Radiology Associates PA',
    'PO Box 830525 Dept #SF128',
    'Birmingham AL 35283-0525',
    'Statement Date 10/16/26',
    'AMOUNT DUE \$36.00',
    'NAKE CHECK PAYABLE AND REMIT T0:', // the small blue label, garbled
    'Montgomery Radiology Associates PA',
    'PO Box 830525 Dept #SF128',
  ];
  const rasterStub = [
    'ENERGEL',
    'MCUIUAL OAIEMENI OSEKVIGE', // raster junk, real device trace
    'Enter Complete URL',
    'www.ePayitOnline.com',
    'MRA Pay Online 05915',
    'Montgomery Radiology Associates PA Access#: 19803282-1-6282',
    'PO Box 830525 Dept #SF128',
    'Birmingham AL 35283-0525 UPay By Phone (800) 841-4236',
    '10/16/26 647760 \$36.00',
    'MAKE CHECK PAYABLE AND REMIT TO:',
    'JACLYNA HARE 647760 Montgomery Radiology Associates PA',
  ];
  const energelSimple = [
    'ENERGEL',
    'Account Summary 04/2026',
    'Previous balance 55.10',
    'TOTAL DUE 61.20',
    'DUE DATE 05/02/26',
  ];

  final cases = <(String, List<String>, String?, FieldConfidence?)>[
    // — historical bounces (verbatim fixtures) —
    (
      'Citi printed statement keeps the brand line',
      citiPrinted,
      'Citi Strata',
      FieldConfidence.high
    ),
    (
      'Citi photo behind browser chrome falls to the issuer',
      citiChrome,
      'Citi',
      FieldConfidence.medium
    ),
    (
      'pen brand never outranks a labelled remit block',
      penStub,
      'Montgomery Radiology Associates PA',
      FieldConfidence.high
    ),
    (
      'raster junk + logo lose to the corroborated provider',
      rasterStub,
      'Montgomery Radiology Associates PA',
      null
    ),
    (
      'plain ENERGEL bill ships its letterhead',
      energelSimple,
      'ENERGEL',
      FieldConfidence.high
    ),
    // — E13 class 1: raster junk widens to silence —
    (
      'lone raster junk ships no payee',
      ['BOUI FVAFD', '04/12/2026', 'TOTAL DUE 22.40'],
      null,
      null
    ),
    (
      'junk on line 1 hands off to the real provider below',
      ['BOUI FVAFD', 'ENERGEL', 'TOTAL DUE 61.20'],
      'ENERGEL',
      null
    ),
    (
      'a doubled unpronounceable mark still ships, at medium',
      ['XQZP STORE', '04/12/2026', 'XQZP STORE', 'TOTAL 22.40'],
      'XQZP STORE',
      FieldConfidence.medium
    ),
    // odd-but-real letter brands keep shipping
    (
      'TGI FRIDAYS is a merchant, not junk',
      ['TGI FRIDAYS', 'TOTAL 22.40'],
      'TGI FRIDAYS',
      FieldConfidence.high
    ),
    (
      'AMZN MKTP ships on the seeded whitelist',
      ['AMZN MKTP', 'TOTAL 13.99'],
      'AMZN MKTP',
      FieldConfidence.high
    ),
    // — E13 class 2: digit-leading merchants —
    (
      '99¢ ONLY keeps its name',
      ['99¢ ONLY', 'MILK 4.00', 'TOTAL 12.50'],
      '99¢ ONLY',
      FieldConfidence.medium
    ),
    (
      '24 HOUR MARKET keeps its name',
      ['24 HOUR MARKET', 'TOTAL 9.99'],
      '24 HOUR MARKET',
      FieldConfidence.medium
    ),
    (
      '1-800-FLOWERS is a merchant, not a phone',
      ['1-800-FLOWERS', 'TOTAL 49.00'],
      '1-800-FLOWERS',
      FieldConfidence.medium
    ),
    ('a date line is still not a merchant', ['03/15 DUE', '22.40'], null, null),
    (
      'discount prose is still not a merchant',
      ['10% DISCOUNT', 'TOTAL 5.00'],
      null,
      null
    ),
    (
      'a bare account card number is not a merchant',
      ['1234 5678 9012 3456', 'TOTAL 5.00'],
      null,
      null
    ),
  ];

  for (final (name, lines, payee, confidence) in cases) {
    test(name, () {
      final d = BillDraft.draft(lines, currency: usd, now: now);
      expect(d.payee, payee);
      if (confidence != null) expect(d.payeeConfidence, confidence);
    });
  }
}
