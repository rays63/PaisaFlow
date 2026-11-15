import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_flow/data/app_store.dart';
import 'package:paisa_flow/data/models.dart';
import 'package:paisa_flow/features/import/import_preview_screen.dart';
import 'package:paisa_flow/l10n/app_localizations.dart';
import 'package:paisa_flow/theme/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

LedgerTransaction _load(String id) => LedgerTransaction.fromJson({
  'id': id,
  'bookId': 'NIC',
  'title': 'eSewa load',
  'amount': 500.0,
  'type': 'cashOut',
  'occurredAt': '2026-11-02T10:00:00.000',
  'createdAt': '2026-11-02T10:00:00.000',
  'updatedAt': '2026-11-02T10:00:00.000',
  'category': 'Imported',
  'paymentMode': 'eSewa',
  'notes': 'LoadeSewa 123456789',
  'importSource': 'NIC Asia',
});

void main() {
  testWidgets('wallet loads get a bulk mark-as-transfers action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'hissabkitab_data_v1': jsonEncode({
        'onboarded': true,
        'defaultCurrency': 'NPR',
        'books': [
          for (final (id, type) in [('NIC', 'bank'), ('eSewa', 'wallet')])
            {
              'id': id,
              'name': id,
              'createdAt': '2026-01-01T00:00:00.000',
              'updatedAt': '2026-01-01T00:00:00.000',
              'currency': 'NPR',
              'type': type,
            },
        ],
        'transactions': const [],
      }),
    });
    final store = AppStore();
    await store.load();
    final rows = [_load('l1'), _load('l2')];
    final preview = ImportPreview(
      source: 'NIC Asia',
      importable: rows,
      duplicates: const [],
      ignored: const [],
    );
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        store: store,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: const [PfColors.light]),
          home: ImportPreviewScreen(
            bookId: 'NIC',
            batch: ImportBatch(
              files: [
                (
                  const ParsedStatement(
                    fileName: 'nov.pdf',
                    format: 'PDF',
                    rows: [],
                    ignored: [],
                  ),
                  preview,
                ),
              ],
              combined: preview,
              sources: const ['NIC Asia'],
              chainGaps: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Neither load is ticked until the user acts.
    expect(
      find.text('Mark 2 wallet top-ups as transfers to eSewa'),
      findsOneWidget,
    );
    await tester.tap(find.text('Mark 2 wallet top-ups as transfers to eSewa'));
    await tester.pumpAndSettle();
    expect(
      find.text('2 top-ups marked as transfers to eSewa — tap to undo'),
      findsOneWidget,
    );

    await tester.tap(find.text('Import 2 entries'));
    await tester.pumpAndSettle();
    expect(
      store.transactions.where((t) => t.bookId == 'eSewa' && t.isTransferLeg),
      hasLength(2),
    );
    expect(store.balanceFor('eSewa'), 1000);
  });
}
