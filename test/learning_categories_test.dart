import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_flow/data/app_store.dart';
import 'package:paisa_flow/data/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

LedgerTransaction _imported(String id, String title, {String book = 'NIC'}) =>
    LedgerTransaction.fromJson({
      'id': id,
      'bookId': book,
      'title': title,
      'amount': 500.0,
      'type': 'cashOut',
      'occurredAt': '2026-11-0${id.length}T10:00:00.000',
      'createdAt': '2026-11-01T10:00:00.000',
      'updatedAt': '2026-11-01T10:00:00.000',
      'category': 'Imported',
      'paymentMode': 'QR',
      'notes': '',
      'importSource': 'NIC Asia',
    });

Future<AppStore> _store() async {
  SharedPreferences.setMockInitialValues({
    'hissabkitab_data_v1': jsonEncode({
      'onboarded': true,
      'defaultCurrency': 'NPR',
      'books': [
        {
          'id': 'NIC',
          'name': 'NIC',
          'createdAt': '2026-01-01T00:00:00.000',
          'updatedAt': '2026-01-01T00:00:00.000',
          'currency': 'NPR',
          'type': 'bank',
        },
      ],
      'transactions': [_imported('a', 'QR · Mega Mart').toJson()],
    }),
  });
  final store = AppStore();
  await store.load();
  return store;
}

void main() {
  test('correcting an imported category teaches the next import', () async {
    final store = await _store();
    final entry = store.transactionById('a')!;
    await store.saveTransaction(entry.copyWith(category: 'Groceries'));

    final preview = store.previewImport(
      bookId: 'NIC',
      source: 'PDF',
      parsed: [_imported('ab', 'QR · Mega Mart')],
      ignored: const [],
    );
    expect(preview.importable.single.category, 'Groceries');

    // The lesson survives a restart.
    final reloaded = AppStore();
    await reloaded.load();
    expect(reloaded.learnedCategories['qr · mega mart'], 'Groceries');
  });

  test('what the user taught beats a keyword guess', () async {
    final store = await _store();
    await store.saveTransaction(
      store.transactionById('a')!.copyWith(category: 'Groceries'),
    );
    // 'Food' here is what the keyword rules guessed from the description.
    final preview = store.previewImport(
      bookId: 'NIC',
      source: 'PDF',
      parsed: [_imported('ab', 'QR · Mega Mart').copyWith(category: 'Food')],
      ignored: const [],
    );
    expect(preview.importable.single.category, 'Groceries');
  });

  test('generic titles are not learned', () async {
    final store = await _store();
    await store.saveTransaction(
      _imported('b', 'QR payment').copyWith(category: 'Food'),
    );
    final before = store.transactionById('b')!;
    await store.saveTransaction(before.copyWith(category: 'Cafe'));
    expect(store.learnedCategories, isEmpty);
  });

  test(
    'renaming a category renames what was learned; deleting forgets it',
    () async {
      final store = await _store();
      await store.saveTransaction(
        store.transactionById('a')!.copyWith(category: 'Groceries'),
      );
      await store.addCategory('Groceries');
      await store.renameCategory('Groceries', 'Kirana');
      expect(store.learnedCategories['qr · mega mart'], 'Kirana');
      await store.removeCategory('Kirana');
      expect(store.learnedCategories, isEmpty);
    },
  );
}
