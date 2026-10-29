import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_flow/data/description_cleaner.dart';
import 'package:paisa_flow/data/import_parser.dart';
import 'package:paisa_flow/data/models.dart';
import 'package:paisa_flow/data/xlsx_writer.dart';

// Made-up lines in each bank's format; real statements stay local (see
// statement_import_test.dart).
void main() {
  group('Global IME descriptions', () {
    test('Fonepay QR keeps the merchant, drops the run-on remark', () {
      expect(
        cleanDescription(
          'FPS:FPQR:1300000001:5900:9800000000:NIBLNPKT:BHAT111142-AB12CD34EF5',
        ),
        'QR · Bhat',
      );
    });

    test('eSewa payments keep the remark', () {
      expect(
        cleanDescription(
          'MOS:eSewa:9800000001:books2MV280VF4DG:9800000000:600:LT',
        ),
        'eSewa · books',
      );
    });

    test('mobile banking transfers name the other person', () {
      const raw =
          'MOS:Trf to ASHA from RAM:Bills and Utilities2WDGLS66QR9:9800000000:650:FE';
      expect(
        cleanDescription(raw, type: TransactionType.cashOut),
        'Mobile banking · Asha · Bills and Utilities',
      );
      expect(
        cleanDescription(
          'MOS:Trf to RAM from SITA:Food and Drinks33XPVNCRFL5:9800000002:18:FEF',
          type: TransactionType.cashIn,
        ),
        'Mobile banking · Sita · Food and Drinks',
      );
    });

    test('connectIPS keeps the merchant', () {
      expect(
        cleanDescription(
          'CIPS/Others: 100200000000001/NPAY QR ACCOUNT/HIMAL TRADERS/MPBL16084/745946335/IPS',
        ),
        'IPS · Himal Traders',
      );
    });

    test('interest and the tax on it', () {
      expect(
        cleanDescription('34800000000001:Int.Pd:17-07-2026 to 17-10-2026'),
        'Interest',
      );
      expect(
        cleanDescription('34800000000001:WTax.Pd:17-07-2026to 17-10-2026'),
        'Tax on interest',
      );
    });
  });

  group('NMB', () {
    // Text as the PDF extracts it: the empty Debit or Credit cell is missing,
    // newest row first.
    const text = '''
Date
Value Date
Description
Debit
Credit
Balance
14-Apr-2026
13-Apr-2026
2020000000000001:Int.Pd:15-01-2026to 13-04-2026
12.05
1026.66
14-Apr-2026
13-Apr-2026
2020000000000001:WTax.Pd:15-01-
2026to 13-04-2026
0.72
1014.61
10-Apr-2026
10-Apr-2026
FBS:IBFT:1450000000:5376:NARBNPKA:
SITA KC
1000.00
1015.33
Transaction Summary
Opening Balance : 15.33
Closing Balance : 1026.66
''';

    test('direction comes from the balance chain', () {
      final (rows, ignored) = ImportParser.nmbRecords(text, 'b');
      expect(ignored, isEmpty);
      expect(
        [for (final r in rows) (r.type, r.amount)],
        [
          (TransactionType.cashIn, 1000.00),
          (TransactionType.cashOut, 0.72),
          (TransactionType.cashIn, 12.05),
        ],
      );
      expect(rows.first.occurredAt, DateTime(2026, 4, 10));
      expect(rows.first.statementBalance, 1015.33);
    });

    test('is recognised and its titles cleaned', () {
      expect(ImportParser.detectSource(text), isNull);
      expect(
        ImportParser.detectSource('$text\nNMB Bank\'s sustainability'),
        ImportParser.nmb,
      );
      expect(
        cleanDescription('FBS:IBFT:1450000000:5376:NARBNPKA:SITA KC'),
        'Fonepay · Sita KC',
      );
    });
  });

  group('Khalti', () {
    List<int> export(List<List<Object>> rows) => writeXlsx(
      sheetName: 'Statement',
      headers: const [
        'Transaction ID',
        'Transaction Type',
        'Transaction State',
        'Transaction Date',
        'Transaction Time',
        'Service',
        'Description',
        'From',
        'To',
        'Username',
        'Fullname',
        'Branch',
        'Purpose',
        'Remarks',
        'Reference',
        'Amount(-) Rs',
        'Amount(+) Rs',
        'Balance',
      ],
      rows: rows,
    );

    test('reads amounts, direction and the other party', () {
      final parsed = ImportParser.readXls(
        fileName: 'khalti.xls',
        bookId: 'b',
        bytes: export([
          [
            'tx2',
            'Event booking',
            'Completed',
            '2026-10-06',
            '10:16:07',
            '',
            'Payment of Rs 2550.0 to book an event.',
            'Ram (9800000000)',
            'Events Nepal (hello@example.com)',
            '',
            '',
            '',
            '',
            '',
            '',
            2550,
            '',
            10.1,
          ],
          [
            'tx1',
            'Bank deposit',
            'Completed',
            '2026-10-06',
            '10:13:48',
            '',
            'Fund added from Nabil Bank Limited.',
            'Nabil Bank Limited',
            'Ram (9800000000)',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            2560,
            2560.1,
          ],
          [
            'tx0',
            'Bank deposit',
            'Failed',
            '2026-10-05',
            '09:00:00',
            '',
            'Fund added.',
            'Nabil Bank Limited',
            'Ram (9800000000)',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            500,
            0.1,
          ],
        ]),
      );
      expect(parsed.source, ImportParser.khalti);
      expect(parsed.ignored, hasLength(1)); // the failed deposit
      final booking = parsed.rows.first;
      expect(booking.title, 'Event booking · Events Nepal');
      expect(booking.type, TransactionType.cashOut);
      expect(booking.amount, 2550);
      expect(booking.occurredAt, DateTime(2026, 10, 6, 10, 16, 7));
      expect(booking.externalReference, 'tx2');
      final deposit = parsed.rows.last;
      expect(deposit.title, 'Bank deposit · Nabil Bank Limited');
      expect(deposit.type, TransactionType.cashIn);
      expect(deposit.amount, 2560);
      expect(deposit.paymentMode, ImportParser.khalti);
    });
  });
}
