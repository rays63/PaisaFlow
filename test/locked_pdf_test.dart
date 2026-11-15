import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_flow/data/import_parser.dart';
import 'package:paisa_flow/data/models.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;

/// A statement PDF locked with [password], laid out like the banks whose
/// PDFs put every table cell on its own line. Built here rather than kept
/// as a file, so no real statement is committed.
List<int> _lockedStatement({required String password}) {
  final document = sfpdf.PdfDocument();
  if (password.isNotEmpty) {
    document.security.userPassword = password;
  }
  final page = document.pages.add();
  final font = sfpdf.PdfStandardFont(sfpdf.PdfFontFamily.helvetica, 10);
  const lines = [
    'Electronic Account Statement',
    'Account Name: RAM BAHADUR',
    'Account Number 01234567890123',
    'Date',
    'Description',
    'Debit',
    'Credit',
    'Balance',
    '2026-10-02',
    'QR PAYMENT-2308abcd, HIMALAYAN JAVA',
    '450.00',
    '-',
    '24,550.00',
    '2026-10-05',
    'SALARY OCTOBER',
    '-',
    '60,000.00',
    '84,550.00',
    '2026-10-09',
    'Load eSewa 987654321',
    '1,000.00',
    '-',
    '83,550.00',
  ];
  var y = 0.0;
  for (final line in lines) {
    page.graphics.drawString(line, font, bounds: Rect.fromLTWH(0, y, 500, 14));
    y += 14;
  }
  final bytes = document.saveSync();
  document.dispose();
  return bytes;
}

void main() {
  group('password-protected statements', () {
    test('a locked PDF asks for a password instead of failing', () {
      final bytes = _lockedStatement(password: 'nepal123');
      expect(
        () => ImportParser.readPdf(
          fileName: 'locked.pdf',
          bookId: 'b',
          bytes: bytes,
        ),
        throwsA(
          isA<PdfPasswordException>().having(
            (e) => e.wrongPassword,
            'wrongPassword',
            isFalse,
          ),
        ),
      );
    });

    test('a wrong password says so, so the prompt can repeat', () {
      final bytes = _lockedStatement(password: 'nepal123');
      expect(
        () => ImportParser.readPdf(
          fileName: 'locked.pdf',
          bookId: 'b',
          bytes: bytes,
          password: 'wrong',
        ),
        throwsA(
          isA<PdfPasswordException>().having(
            (e) => e.wrongPassword,
            'wrongPassword',
            isTrue,
          ),
        ),
      );
    });

    test('the right password reads the entries', () {
      final parsed = ImportParser.readPdf(
        fileName: 'locked.pdf',
        bookId: 'b',
        bytes: _lockedStatement(password: 'nepal123'),
        password: 'nepal123',
      );
      expect(parsed.rows, hasLength(3));
      final qr = parsed.rows.first;
      expect(qr.title, 'QR · Himalayan Java');
      expect(qr.type, TransactionType.cashOut);
      expect(qr.amount, 450);
      expect(qr.paymentMode, 'QR');
      expect(qr.occurredAt, DateTime(2026, 10, 2));

      final salary = parsed.rows[1];
      expect(salary.type, TransactionType.cashIn);
      expect(salary.amount, 60000);
      expect(salary.category, 'Salary');

      final load = parsed.rows.last;
      expect(load.title, 'eSewa load');
      expect(load.paymentMode, 'eSewa');
      expect(load.statementBalance, 83550);
    });

    test('the same statement unlocked reads identically', () {
      final locked = ImportParser.readPdf(
        fileName: 'locked.pdf',
        bookId: 'b',
        bytes: _lockedStatement(password: 'nepal123'),
        password: 'nepal123',
      );
      final open = ImportParser.readPdf(
        fileName: 'open.pdf',
        bookId: 'b',
        bytes: _lockedStatement(password: ''),
      );
      expect(
        open.rows.map((r) => (r.title, r.amount, r.type)),
        locked.rows.map((r) => (r.title, r.amount, r.type)),
      );
    });
  });
}
