import 'package:core/core.dart';
import 'package:test/test.dart';

/// E11 bill-route groundwork (e11-document-import.md §4): the due-date and
/// frequency vocabulary a photographed bill carries, plus the statement
/// period-end fallback. Everything is pinned against a frozen clock.
void main() {
  final usd = Currency.known['USD']!;
  final now = DateTime.utc(2026, 11, 4);

  group('guessDueDate', () {
    test('due vocabulary on the line yields a high-confidence date', () {
      final r = BillDraft.guessDueDate(
        ['ACME POWER', 'DUE DATE 11/15/2026', 'TOTAL 84.00'],
        now: now,
      );
      expect(r, isNotNull);
      expect(r!.date, DateTime.utc(2026, 11, 15));
      expect(r.confidence, FieldConfidence.high);
    });

    test('month-name spellings parse', () {
      final r = BillDraft.guessDueDate(['PAY BY NOV 15, 2026'], now: now);
      expect(r?.date, DateTime.utc(2026, 11, 15));
    });

    test('OCR-split value on the next line reads medium', () {
      final r = BillDraft.guessDueDate(
        ['ACME POWER UTILITIES', 'DUE DATE', '11/15/2026'],
        now: now,
      );
      expect(r?.date, DateTime.utc(2026, 11, 15));
      expect(r?.confidence, FieldConfidence.medium);
    });

    test('the last date on the line is the operative one', () {
      // `BILLING PERIOD 10/01/2026 - 10/31/2026` must float from the END.
      final r = BillDraft.guessDueDate(
        ['STATEMENT PERIOD 10/01/2026 - 10/31/2026'],
        now: now,
      );
      expect(r?.date, DateTime.utc(2026, 11, 21)); // 10/31 + 21d float
      expect(r?.confidence, FieldConfidence.low);
    });

    test('dates outside the short-cycle window are refused', () {
      // now + ~198 d: nobody bills that far ahead.
      expect(BillDraft.guessDueDate(['DUE DATE 05/21/2027'], now: now), isNull);
      // now − 38 d: last month's bill, not a bill to draft.
      expect(BillDraft.guessDueDate(['DUE DATE 09/27/2026'], now: now), isNull);
    });

    test('a bill due three days ago is still draftable', () {
      // Day-first reading: 01/11 = the 1st of November.
      final r = BillDraft.guessDueDate(['DUE DATE 01/11/2026'], now: now);
      expect(r?.date, DateTime.utc(2026, 11, 1));
    });

    test('year-less period end borrows the year and floats', () {
      final r = BillDraft.guessDueDate(['PERIOD END 12/31'], now: now);
      expect(r?.date, DateTime.utc(2027, 1, 21));
      expect(r?.confidence, FieldConfidence.low);
    });

    test('period float landing out of window refuses the fallback', () {
      // End 88 d out: inside the due window, but outside the 60-day
      // proximity belt the period fallback trusts its float against.
      expect(
        BillDraft.guessDueDate(['BILLING PERIOD 01/01/2027 - 01/31/2027'],
            now: now),
        isNull,
      );
    });
  });

  group('_guessFrequency (through the draft)', () {
    (BillFrequencyHint, FieldConfidence) freq(List<String> lines) {
      final d = BillDraft.draft(lines, currency: usd, now: now);
      return (d.frequency, d.frequencyConfidence);
    }

    test('monthly vocabulary is high', () {
      expect(freq(['BILLING CYCLE: MONTHLY']),
          (BillFrequencyHint.monthly, FieldConfidence.high));
    });

    test('annual wording reads yearly', () {
      expect(freq(['ANNUAL SERVICE FEE']),
          (BillFrequencyHint.yearly, FieldConfidence.high));
    });

    test('quarterly degrades to monthly at medium, never a fake frequency', () {
      expect(freq(['QUARTERLY INSTALLMENT']),
          (BillFrequencyHint.monthly, FieldConfidence.medium));
    });

    test('weekly reads weekly', () {
      expect(freq(['WEEKLY DELIVERY']),
          (BillFrequencyHint.weekly, FieldConfidence.high));
    });

    test('no vocabulary leaves monthly at low', () {
      expect(freq(['ACME POWER', 'TOTAL 40.00']),
          (BillFrequencyHint.monthly, FieldConfidence.low));
    });
  });

  group('BillDraft.draft', () {
    test('a full bill wires payee, amount, due date and frequency', () {
      final d = BillDraft.draft(
        [
          'CITY WATER & SEWER',
          'DUE DATE 11/15/2026',
          'BILLING CYCLE: MONTHLY',
          'TOTAL AMOUNT DUE 84.00',
        ],
        currency: usd,
        now: now,
      );
      expect(d.isEmpty, isFalse);
      expect(d.payee?.toLowerCase(), contains('water'));
      expect(d.amountDue?.minorUnits, 8400);
      expect(d.dueDate, DateTime.utc(2026, 11, 15));
      expect(d.dueDateConfidence, FieldConfidence.high);
      expect(d.frequency, BillFrequencyHint.monthly);
      expect(d.frequencyConfidence, FieldConfidence.high);
    });

    test('an unrecognisable page drafts empty', () {
      final d = BillDraft.draft(
        ['~~~~~~~~', '----'],
        currency: usd,
        now: now,
      );
      expect(d.isEmpty, isTrue);
    });

    // Real-world shape: a US card statement (redacted from a tester's
    // October PDF, 2026-11-05). What the cardholder writes the check for
    // is the MINIMUM PAYMENT DUE — prefilling the balance turned a $594
    // bill into a $7,355 one. Warning prose and the payoff table talk
    // about the minimum without being it; the stub at the foot repeats
    // the box, bottom-up.
    test('a card statement drafts the minimum due, not the balance', () {
      final d = BillDraft.draft(
        [
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
          'Your Citi Flex Plan Payment Amount is included in your Minimum',
          'Payment Due. For more details, see the Citi Flex Plan details',
          'Late Payment Warning:',
          'If we do not receive your Minimum Payment',
          'by the date listed above, you may have to pay a late fee of up to \$41',
          'Minimum Payment Warning:',
          'If you make only the minimum payment each period,',
          'Account Summary',
          'Previous balance',
          r'$7,342.77',
          'New balance',
          r'$7,355.21',
          'Credit limit',
          r'$7,300',
          'Minimum payment due',
          r'$594.67',
          'New balance',
          r'$7,355.21',
          'Payment due date',
          '11/14/26',
        ],
        currency: usd,
        now: now,
      );
      expect(d.payee, 'Citi Strata'); // brand line, first line — kept as read
      expect(d.payeeConfidence, FieldConfidence.high);
      expect(d.amountDue?.minorUnits, 59467); // the minimum, not 735521
      expect(d.amountConfidence, FieldConfidence.high);
      expect(d.dueDate, DateTime.utc(2026, 11, 14));
      expect(d.frequency, BillFrequencyHint.monthly);
    });

    test('a same-line minimum label wins over a balance anchor', () {
      final d = BillDraft.draft(
        [
          'CHASE FREEDOM CARD',
          'MINIMUM PAYMENT DUE: \$42.50',
          'BALANCE DUE \$1,200.00',
          'DUE DATE 11/20/2026',
        ],
        currency: usd,
        now: now,
      );
      expect(d.amountDue?.minorUnits, 4250);
      expect(d.amountConfidence, FieldConfidence.high);
    });

    test('warning prose about the minimum does not hijack the amount', () {
      // Label-only lines whose next line is prose disqualify; the balance
      // anchor remains the fallback for statements with no payment box.
      final d = BillDraft.draft(
        [
          'CITI CARD ACCOUNT',
          'Minimum Payment Warning: If you make only the minimum payment',
          'you will pay more in interest and it will take you longer.',
          'NEW BALANCE \$250.00',
        ],
        currency: usd,
        now: now,
      );
      expect(d.amountDue?.minorUnits, 25000);
    });

    test('a statement photo whose OCR lead is chrome drafts the issuer', () {
      // Phone photo of the web statement: status bar and browser address
      // bar OCR before the logo, and no clean merchant line survives the
      // first six — the issuer vocabulary names the payee instead.
      final d = BillDraft.draft(
        [
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
        ],
        currency: usd,
        now: now,
      );
      expect(d.payee, 'Citi');
      expect(d.payeeConfidence, FieldConfidence.medium);
      expect(d.amountDue?.minorUnits, 59467);
    });

    test('non-card bills keep the merchant heuristic untouched', () {
      final d = BillDraft.draft(
        ['CITY WATER & SEWER', 'DUE DATE 11/15/2026', 'TOTAL AMOUNT DUE 84.00'],
        currency: usd,
        now: now,
      );
      expect(d.payee?.toLowerCase(), contains('water'));
    });
  });

  // Medical provider statements (tester bounce, 2026-11-05: a radiology
  // payment stub scanned "okay sometimes and garbled others" — depending
  // on which rows photo OCR survived, the all-caps paper heading won the
  // payee or the whole page missed classification). Names, numbers and
  // addresses below are synthetic; the line shapes are the photo's.
  group('medical statement stub', () {
    const stub = <String>[
      'MEDICAL STATEMENT OF SERVICE',
      'MRI MONTGOMERY RADIOLCGY',
      'Riverbend Imaging Associates PA',
      'PO Box 830525 Dept #SF128',
      'Birmingham AL 35283-0525',
      'Pay Online www.cPayitOnline.com',
      'Code ID: MSN00001',
      'Pay By Phone (800) 841-4236',
      'Statement Date Account # AMOUNT DUE',
      '10/16/26 647760 \$36.00',
      '111300006477600000003600',
      'JANE Q PUBLIC 647760',
      '12 Main St',
      'Honoraville AL 36042-5304',
      'MAKE CHECK PAYABLE AND REMIT TO:',
      'Riverbend Imaging Associates PA',
      'PO Box 830525 Dept #SF128',
    ];
    const shedRows = <String>[
      'MEDICAL STATEMENT OF SERVICE',
      'Riverbend Imaging Associates PA',
      'PO Box 830525 Dept SF128',
      'Enter Complete URL www.cPavit0nline.com',
      'Code ID: MSN00001 Access#: 19803282-1-6282',
      'Statement Date Account # AMOUNT DUE 10/16/26 647760 \$36.00',
      '111300006477600000003600 JANE Q PUBLIC 647760',
      'MAKE CHECK PAYABLE AND REMIT TO:',
      'Riverbend Imaging Associates PA',
    ];

    test('the payee is the printed remit block, not the paper heading', () {
      final d = BillDraft.draft(stub, currency: usd, now: now);
      expect(d.payee, 'Riverbend Imaging Associates PA');
      expect(d.payeeConfidence, FieldConfidence.high);
      expect(d.amountDue?.minorUnits, 3600);
      // A statement date is not a due date: no vocabulary, no date.
      expect(d.dueDate, isNull);
    });

    test('OCR shedding the phone row and merging the stub table still drafts',
        () {
      final d = BillDraft.draft(shedRows, currency: usd, now: now);
      expect(d.payee, 'Riverbend Imaging Associates PA');
      expect(d.amountDue?.minorUnits, 3600);
      final h = ReceiptHeuristics(currency: usd, now: now);
      expect(h.classify(shedRows), DocType.utilityBill);
    });

    test('a paper heading with no remit block leaves the payee empty', () {
      final d = BillDraft.draft(
        ['MEDICAL STATEMENT OF SERVICE', 'AMOUNT DUE \$36.00'],
        currency: usd,
        now: now,
      );
      expect(d.payee, isNull);
      expect(d.amountDue?.minorUnits, 3600);
    });
  });

  // Out-of-document clutter (second tester bounce, 2026-11-05: the same
  // radiology stub photographed on a desk — the frame's top held a pen
  // printed "ENERGEL", photo OCR read that line BEFORE the page, the small
  // blue remit label survived garbled, and the pen brand shipped as the
  // payee). Synthetic brand word, real line shapes.
  group('desk clutter above the frame', () {
    const provider = 'Montgomery Radiology Associates PA';
    const penStub = <String>[
      'GELMASTER', // pen brand, above the page edge
      'MRA MONTGOMERY RADIOLOGY',
      provider,
      'PO Box 830525 Dept #SF128',
      'Birmingham AL 35283-0525',
      'Toll Free: (800) 841-4236',
      'Statement Date 10/16/26',
      'AMOUNT DUE \$36.00',
      'NAKE CHECK PAYABLE AND REMIT T0:', // the small blue label, garbled
      provider,
      'PO Box 830525 Dept #SF128',
      'Birmingham AL 35283-0525',
    ];

    test('a garbled label still wins: PAYABLE alone names the remit block', () {
      final d = BillDraft.draft(penStub, currency: usd, now: now);
      expect(d.payee, provider);
      expect(d.payeeConfidence, FieldConfidence.high);
      expect(d.payee, isNot('GELMASTER'));
      expect(d.amountDue?.minorUnits, 3600);
      expect(d.dueDate, isNull);
    });

    test('with no label at all the letterhead outranks the pen brand', () {
      final noLabel = [
        for (final l in penStub)
          if (!l.startsWith('NAKE')) l,
      ];
      final d = BillDraft.draft(noLabel, currency: usd, now: now);
      expect(d.payee, provider);
      expect(d.payee, isNot('GELMASTER'));
    });

    test('a corroborated name keeps its place behind an interleaved address',
        () {
      // ML Kit merges same-height columns: the stub's remitter block sits
      // level with the remit box, so junk lines land between label and name.
      final d = BillDraft.draft(
        [
          'GELMASTER',
          'JANE Q PUBLIC 647760',
          '12 Main St',
          'MAKE CHECK PAYABLE AND REMIT TO:',
          'Honoraville AL 36042-5304',
          provider,
          'AMOUNT DUE \$36.00',
        ],
        currency: usd,
        now: now,
      );
      expect(d.payee, provider);
      expect(d.amountDue?.minorUnits, 3600);
    });

    test('a tilted photo merging BOTH columns still names the provider', () {
      // Third tester bounce (2026-11-05), the real Coosea capture: the
      // stub prints two side-by-side columns, and tilt merged every band
      // left-to-right — the label row picked up the remitter's name row,
      // the provider row its own address, so no line under the label was
      // digit-free and `_nameish` refused them all: the pen brand shipped.
      // Line shapes frozen from a full-page transcription of the photo.
      final tiltMerged = <String>[
        'ENERGEL', // pen brand, above the page edge
        'MEDICAL STATEMENT OF SERVICE',
        'MRA MONTGOMERY RADIOLOGY ASSOCIATES',
        'Montgomery Radiology Associates PA Pay Online',
        'PO Box 830525 Dept #SF128 Enter Complete URL',
        'Birmingham AL 35283-0525 www.ePayitOnline.com',
        'Toll Free: (800) 841-4236 Code ID: MSN00001',
        'Statement Date 10/16/26 Account # 647760 AMOUNT DUE \$36.00',
        '1113000064776000000036001',
        'JACLYN A HARE 647760 MAKE CHECK PAYABLE AND REMIT TO:',
        'Montgomery Radiology Associates PA PO Box 830525 Dept #SF128',
        'Birmingham AL 35283-0525',
      ];
      final d = BillDraft.draft(tiltMerged, currency: usd, now: now);
      expect(d.payee, isNot('ENERGEL'));
      expect(d.payee, provider);
      expect(d.payeeConfidence, FieldConfidence.high);
      expect(d.amountDue?.minorUnits, 3600);
      expect(d.dueDate, isNull);
    });

    test('uncorroborated single-word billers survive the clutter guard', () {
      // A one-brand PDF has exactly one occurrence and no address line —
      // with no better candidate the guard must keep the honest guess.
      final d = BillDraft.draft(
        [
          'NETFLIX',
          'Your monthly membership',
          'AMOUNT DUE \$15.99',
          'DUE DATE 11/20/2026',
        ],
        currency: usd,
        now: now,
      );
      expect(d.payee?.toUpperCase(), 'NETFLIX');
    });
  });

  group('public-domain sample statement (CFPB handout)', () {
    // Verbatim lines from the CFPB "Building Blocks" sample credit card
    // statement (US Government work, public domain) — the corpus lives in
    // import-samples/ with provenance in its SOURCES.md.
    test('minimum payment wins; sheet and watermark titles stay out', () {
      final d = BillDraft.draft(
        [
          'BUILDING BLOCKS STUDENT HANDOUT',
          'Sample credit card statement',
          'Payment Information',
          'Date: 12/30/XX',
          'Payment Due Date: 1/23/XX',
          'New Balance: \$1392.71',
          'Minimum Payment: \$25',
          'Account Summary',
          'Previous Balance',
          '\$482.42',
          'Payment, Credits',
          '-\$350.42',
          'Minimum Payment Due',
          '\$25',
          'Annual Percentage Rate (APR)',
          '19.80%',
          'Name: Susan Doe',
          'Address: 1234 Main Street, Anytown, USA',
        ],
        currency: usd,
        now: now,
      );
      expect(d.amountDue?.minorUnits, 2500); // not the \$1392.71 balance
      expect(d.dueDate, isNull); // "1/23/XX" carries no machine year
      expect((d.payee ?? '').toUpperCase(), isNot(contains('HANDOUT')));
      expect((d.payee ?? '').toLowerCase(), isNot(startsWith('sample')));
    });
  });

  group('device trace — photographed ENERGEL radiology stub (SL219A)', () {
    // Verbatim [ocr-lines] dump of 2026-11-05: a tilted desk photo of a
    // pay-by-phone remittance stub. The first line is the payment-network
    // logo; the provider shares its line with an Access# field and repeats
    // in the remit columns below it.
    final stub = [
      'ENERGEL',
      'MCUIUAL OAIEMENI OSEKVIGE',
      'Enter Complete URL',
      'www.ePayitOnline.com',
      'MRA Pay Online 05915',
      'Code ID: MSNOO001',
      'Montgomery Radiology Associates PA Access#: 19803282-1-6282',
      'PO Box 830525 Dept #SF128',
      'Birmingham AL 35283-0525 UPay By Phone (800) 841-4236',
      'Statement Date Account # AMOUNT DUE',
      '10/16/26 647760 \$36.00',
      'Toll Free: (800) 841-4236',
      '11130DD0647760000D0036001',
      'MAKE CHECK PAYABLE AND REMIT TO:',
      'D5995 Inuulur"plpla||lrlilury',
      'JACLYNA HARE 647760 Montgomery Radiology Associates PA',
      '5908 Steiner Store Rd #R PO Box 830325 Dept #SF128',
      'Honoraville AL 36042-5304 Bimingham AL 35283-0525',
    ];

    test('the corroborated provider outranks the lone network logo', () {
      final d = BillDraft.draft(stub, currency: usd, now: now);
      expect(d.payee, 'Montgomery Radiology Associates PA');
      expect(d.amountDue?.minorUnits, 3600);
    });
  });
}
