import 'models.dart';

/// What an imported statement row probably is, besides a plain entry.
///
/// [bookId] is the user's account the money likely moved to (or came from).
/// [matchedEntryId] is an existing entry in that account that mirrors this
/// row (same amount, opposite direction, within a day) — importing then
/// links the two instead of creating a double. [confident] rows start
/// ticked as transfers in the preview; the user can untick them.
typedef TransferHint = ({
  String bookId,
  String? matchedEntryId,
  bool confident,
  bool walletLoad,
});

/// A transfer hint for [row], or null when nothing fits.
///
/// Wallet loads can also be payments of someone else's wallet, and the
/// number in the description is a per-transaction reference, not a wallet
/// id. So a load is only confident when the matching cash-in actually
/// exists in the user's wallet account; otherwise it stays a tappable
/// option (and the preview offers a bulk "mark all" action).
TransferHint? transferHint(
  LedgerTransaction row,
  List<LedgerBook> books,
  List<LedgerTransaction> entries, {
  required String currency,
}) {
  final text = '${row.title} ${row.notes}'.toLowerCase();
  final out = row.type == TransactionType.cashOut;
  final candidates = books
      .where((book) => book.id != row.bookId && book.currency == currency)
      .toList();

  String? named(String name) {
    for (final book in candidates) {
      if (book.accountType == AccountType.wallet &&
          book.name.toLowerCase().contains(name)) {
        return book.id;
      }
    }
    return null;
  }

  String? ofType(AccountType type) {
    final matches = candidates.where((book) => book.accountType == type);
    // Only when it is unambiguous which account was meant.
    return matches.length == 1 ? matches.single.id : null;
  }

  /// An existing entry in [bookId] that mirrors this row.
  String? match(String bookId) {
    for (final entry in entries) {
      if (entry.bookId != bookId ||
          entry.type == row.type ||
          entry.isTransferLeg ||
          entry.amount != row.amount) {
        continue;
      }
      if (entry.occurredAt.difference(row.occurredAt).inHours.abs() <= 36) {
        return entry.id;
      }
    }
    return null;
  }

  TransferHint? load(String? bookId) {
    if (bookId == null) return null;
    final matched = match(bookId);
    return (
      bookId: bookId,
      matchedEntryId: matched,
      confident: matched != null,
      walletLoad: true,
    );
  }

  if (out && RegExp(r'\b(load ?esewa|esewa load)').hasMatch(text)) {
    return load(named('esewa'));
  }
  if (out && RegExp(r'\b(khalti load|load wallet khalti)').hasMatch(text)) {
    return load(named('khalti'));
  }
  if (!out && text.contains('esewa withdrawal')) return load(named('esewa'));
  if (out && RegExp(r'\b(atm withdrawal|atm wdl|cwdr/)').hasMatch(text)) {
    // An ATM withdrawal is always the user's own cash, so it starts ticked
    // when they keep a cash account.
    final cash = ofType(AccountType.cash);
    if (cash == null) return null;
    return (
      bookId: cash,
      matchedEntryId: match(cash),
      confident: true,
      walletLoad: false,
    );
  }
  if (out &&
      RegExp(
        r'\b(card (pmt|payment)|credit ?card (pmt|payment|bill)|cc (pmt|payment))',
      ).hasMatch(text)) {
    final card = ofType(AccountType.card);
    if (card == null) return null;
    return (
      bookId: card,
      matchedEntryId: match(card),
      confident: false,
      walletLoad: false,
    );
  }
  return null;
}
