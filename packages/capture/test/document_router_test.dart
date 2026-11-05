import 'package:capture/capture.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  final usd = Currency.resolve('USD');
  final now = DateTime.utc(2026, 11, 4);
  DocRoute route(List<String> lines) =>
      DocumentRouter.route(lines, currency: usd, now: now);

  // A one-page credit-card bill: dense transaction rows AND a bill
  // signature — precedence (e11 §1) must route it to the bill editor.
  final cardBill = [
    'ACME BANK CREDIT CARD',
    'MINIMUM PAYMENT DUE 15.00',
    '10/01/2026 CORNER MARKET 24.60 1,204.60',
    '10/03/2026 FUEL CO 41.20 1,245.80',
    '10/05/2026 ONLINE PAYMENT -50.00 1,195.80',
    'AMOUNT DUE 84.00',
    'PAYMENT DUE DATE 01/15/2027',
  ];

  final bankStatement = [
    '10/01/2026 CORNER MARKET 24.60 1,204.60',
    '10/03/2026 SALARY CREDIT 2,400.00 3,604.60',
    '10/05/2026 UTILITY AUTO PAY 84.00 3,520.60',
  ];

  group('DocumentRouter.route', () {
    test('bill signature beats line density (dense card bill)', () {
      expect(route(cardBill), DocRoute.bill);
    });

    test('sparse utility bill with due date + amount → bill', () {
      expect(
        route([
          'NORTHERN POWER & LIGHT',
          'ACCOUNT 4471-88',
          'AMOUNT DUE 84.00',
          'PAYMENT DUE DATE 12/15/2026',
          'THANK YOU',
        ]),
        DocRoute.bill,
      );
    });

    test('keyword-only utility bill (no parseable pair) still → bill', () {
      expect(
        route([
          'NORTHERN POWER & LIGHT SERVICE PERIOD 10/01 THRU 10/31',
          'ACCOUNT NUMBER 4471-88',
          'PLEASE PAY BY 01/01/2020', // far outside the ±window
          'TOTAL AMOUNT DUE 84.00',
          'THANK YOU FOR YOUR BILL',
        ]),
        DocRoute.bill,
      );
    });

    test('dense transaction rows, no bill signature → statement', () {
      expect(route(bankStatement), DocRoute.statement);
    });

    test('two row-like lines stay under the density bar → other', () {
      expect(
        route([
          'CORNER MARKET',
          '10/01/2026 CORNER MARKET 24.60',
          '10/03/2026 FUEL CO 41.20',
          'THANK YOU, PLEASE COME AGAIN',
        ]),
        DocRoute.other,
      );
    });

    test('third row-like line tips it to statement', () {
      expect(
        route([
          '10/01/2026 CORNER MARKET 24.60',
          '10/03/2026 FUEL CO 41.20',
          '10/05/2026 MAIL ROOM 8.00',
        ]),
        DocRoute.statement,
      );
    });

    test('grocery receipt → other (the scanner, not a second UI)', () {
      expect(
        route([
          'GREEN GROCERS',
          '03/15/2026 14:22',
          '2 MILK 3.50',
          '1 BREAD 2.25',
          'TOTAL 5.75',
        ]),
        DocRoute.other,
      );
    });

    test('card slip → other (receipt flow owns it)', () {
      expect(
        route([
          'VISA 4*** 1234',
          'TOTAL AMOUNT: (215.60)',
          'APPROVED 00',
        ]),
        DocRoute.other,
      );
    });

    test('dates alone never count as rows', () {
      expect(
        route([
          '10/01/2026 10/02/2026 10/03/2026',
          'SERVICE PERIOD 05.12.2026',
          'STATEMENT DATE 12/31/2025',
        ]),
        DocRoute.other,
      );
    });

    test('empty text → other', () {
      expect(route([]), DocRoute.other);
    });

    test('kStatementMinRows is the density bar', () {
      expect(DocumentRouter.kStatementMinRows, 3);
    });
  });
}
