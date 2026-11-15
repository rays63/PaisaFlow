import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_flow/data/app_store.dart';
import 'package:paisa_flow/data/insights.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _entry(String id, double amount, String day) => {
  'id': id,
  'bookId': 'NIC',
  'title': id,
  'amount': amount,
  'type': 'cashOut',
  'occurredAt': '${day}T12:00:00.000',
  'createdAt': '${day}T12:00:00.000',
  'updatedAt': '${day}T12:00:00.000',
  'category': 'Food',
  'paymentMode': 'Cash',
  'notes': '',
};

Future<AppStore> _store() async {
  SharedPreferences.setMockInitialValues({
    'hissabkitab_data_v1': jsonEncode({
      'onboarded': true,
      'defaultCurrency': 'NPR',
      'monthStartDay': 25,
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
      'transactions': [
        _entry('before', 100, '2026-10-24'),
        _entry('first', 200, '2026-10-25'),
        _entry('mid', 400, '2026-11-13'),
        _entry('last', 800, '2026-11-24'),
        _entry('next', 1600, '2026-11-25'),
      ],
    }),
  });
  final store = AppStore();
  await store.load();
  return store;
}

void main() {
  test('a month runs from the start day to the day before it', () async {
    final store = await _store();
    expect(store.monthStartDay, 25);
    // 13 Nov falls in the period that began 25 Oct.
    expect(store.periodAnchor(DateTime(2026, 11, 13)), DateTime(2026, 10));
    expect(store.periodAnchor(DateTime(2026, 11, 25)), DateTime(2026, 11));
    final (start, end) = store.periodOf(DateTime(2026, 10));
    expect(start, DateTime(2026, 10, 25));
    expect(end, DateTime(2026, 11, 25));
  });

  test('budgets count the period, not the calendar month', () async {
    final store = await _store();
    expect(
      store.budgetSpent('currency:NPR', 'Food', DateTime(2026, 10)),
      200 + 400 + 800,
    );
    expect(store.budgetSpent('currency:NPR', 'Food', DateTime(2026, 11)), 1600);
  });

  test('flow and pace follow the start day', () async {
    final store = await _store();
    final insights = Insights(
      store.transactions,
      now: DateTime(2026, 11, 13, 10),
      startDay: 25,
    );
    final flow = insights.flow(DateTime(2026, 10));
    expect(flow.totalOut, 1400);

    final pace = insights.pace(DateTime(2026, 10));
    // 25 Oct through 24 Nov is 31 days; 13 Nov is its 20th day.
    expect(pace.days, 31);
    expect(pace.throughDay, 20);
    expect(pace.thisMonth.first, 200);
    expect(pace.thisMonth.last, 600);
    expect(pace.spent, 600);
  });

  test('the setting persists and day 1 stays a plain calendar month', () async {
    final store = await _store();
    await store.setMonthStartDay(1);
    final reloaded = AppStore();
    await reloaded.load();
    expect(reloaded.monthStartDay, 1);
    expect(reloaded.periodAnchor(DateTime(2026, 11, 13)), DateTime(2026, 11));
    expect(
      reloaded.budgetSpent('currency:NPR', 'Food', DateTime(2026, 11)),
      400 + 800 + 1600,
    );
  });
}
