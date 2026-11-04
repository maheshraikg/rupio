/// Turns parsed bank events into ledger changes: new transactions, bills for
/// cards, and cards/accounts that were seen but are not in the app yet.
library;

import '../data/csv.dart' show guessCategory, guessIncomeCategory;
import '../ledger/ledger.dart';
import '../models/models.dart';
import '../models/money.dart';
import 'bank_messages.dart';
import '../l10n/strings.dart';

/// A parsed event with a stable key for its source message, e.g.
/// "sms:3f9a…". The prefix (sms, mail, pdf) names the source.
class SourcedEvent {
  const SourcedEvent(this.key, this.event);
  final String key;
  final BankEvent event;

  String get source => key.split(':').first;
}

/// Stable 64-bit FNV-1a hash as hex, for message keys.
String stableHash(String s) {
  var h = 0xcbf29ce484222325;
  for (final unit in s.codeUnits) {
    h ^= unit;
    h *= 0x100000001b3; // wraps at 64 bits
  }
  return h.toUnsigned(64).toRadixString(16);
}

/// A card or account mentioned in messages that the app does not track.
class DetectedHolding {
  DetectedHolding({required this.isCard, required this.digits, this.bank});

  final bool isCard;
  final String digits;
  String? bank;
  int count = 0;
  Paise spent = 0;

  /// Latest available card limit (cards) or balance (accounts) reported.
  Paise? latestFigure;
  DateTime? latestDate;

  String get label => '${bank ?? (isCard ? 'Card' : 'Account')} ••$digits';
}

/// The bank's latest balance for an account, to compare with the app.
class BalanceHint {
  const BalanceHint(this.balance, this.date);
  final Paise balance;
  final DateTime date;
}

class SyncResult {
  SyncResult();

  /// New entries to save (ids are 0; sourceKey is set).
  final List<Txn> added = [];

  /// Existing entries to replace (a card payment matched to the bank debit
  /// that paid it).
  final List<Txn> updated = [];

  /// Latest bank bill per card id.
  final Map<int, BankBill> bills = {};

  /// Latest bank-reported balance per account id.
  final Map<int, BalanceHint> balances = {};

  /// Cards and accounts seen in messages but not in the app, by key.
  final Map<String, DetectedHolding> unknown = {};

  /// Events already in the app (same message, or matched to an entry typed
  /// in by hand or imported from another source).
  int duplicates = 0;

  bool get isEmpty =>
      added.isEmpty && updated.isEmpty && bills.isEmpty && unknown.isEmpty;
}

/// Works out what [events] add to the ledger [l]. Keys in [ignoredKeys]
/// (entries the user deleted) are skipped. [sourceLabel] names the source in
/// bank bills ("SMS", "email", "statement PDF").
SyncResult planSync(
  List<SourcedEvent> events,
  Ledger l, {
  Set<String> ignoredKeys = const {},
  String sourceLabel = 'SMS',
}) {
  final result = SyncResult();
  final known = {
    for (final t in l.txns)
      if (t.sourceKey != null) t.sourceKey!,
    ...ignoredKeys,
  };
  final claimed = <int>{};
  // Indexes of added card payments that still lack the paying account.
  final openPayments = <int>[];

  final sorted = [...events]
    ..sort((a, b) => a.event.date.compareTo(b.event.date));

  /// An existing entry (typed in by hand, or from a different source) for
  /// the same money movement. Entries from the same source are skipped
  /// unless [sameSource]: two identical SMS purchases are two purchases, but
  /// a card payment and the bank debit that paid it are one movement.
  Txn? findExisting(
    SourcedEvent se,
    bool Function(Txn) same,
    int days, {
    bool sameSource = false,
  }) {
    for (final t in l.txns) {
      if (claimed.contains(t.id)) continue;
      if (!sameSource &&
          t.sourceKey != null &&
          t.sourceKey!.startsWith('${se.source}:')) {
        continue;
      }
      if (t.amount != se.event.amount) continue;
      if (t.date.difference(se.event.date).inDays.abs() > days) continue;
      if (same(t)) return t;
    }
    return null;
  }

  CreditCard? cardFor(String? digits) {
    if (digits == null || digits.isEmpty) return null;
    for (final c in l.cards) {
      if (digitsMatch(c.lastFour, digits)) return c;
    }
    return null;
  }

  Account? accountFor(String digits) {
    for (final a in l.accounts) {
      if (digitsMatch(a.lastFour, digits)) return a;
    }
    return null;
  }

  void noteUnknown(BankEvent e) {
    final key = '${e.isCard ? 'c' : 'a'}${e.digits}';
    final h = result.unknown.putIfAbsent(
      key,
      () => DetectedHolding(isCard: e.isCard, digits: e.digits, bank: e.bank),
    );
    h.bank ??= e.bank;
    h.count++;
    if (e.kind == BankEventKind.cardSpend ||
        e.kind == BankEventKind.accountDebit) {
      h.spent += e.amount;
    }
    final figure = e.isCard ? e.availableLimit : e.balance;
    if (figure != null &&
        (h.latestDate == null || !e.date.isBefore(h.latestDate!))) {
      h.latestFigure = figure;
      h.latestDate = e.date;
    }
  }

  Txn txn(
    SourcedEvent se,
    TxnType type, {
    String? category,
    int? fromAccountId,
    int? fromCardId,
    int? toAccountId,
    int? toCardId,
  }) => Txn(
    id: 0,
    type: type,
    amount: se.event.amount,
    date: se.event.date,
    category: category,
    note: se.event.description,
    fromAccountId: fromAccountId,
    fromCardId: fromCardId,
    toAccountId: toAccountId,
    toCardId: toCardId,
    sourceKey: se.key,
  );

  for (final se in sorted) {
    final e = se.event;
    if (known.contains(se.key)) {
      result.duplicates++;
      continue;
    }

    if (e.isCard) {
      final card = cardFor(e.digits);
      if (card == null) {
        noteUnknown(e);
        continue;
      }
      switch (e.kind) {
        case BankEventKind.cardBill:
          final current = result.bills[card.id];
          if (current == null || !e.dueDate!.isBefore(current.dueDate)) {
            result.bills[card.id] = BankBill(
              totalDue: e.amount,
              minDue: e.minDue,
              dueDate: e.dueDate!,
              statementDate: e.statementDate,
              source: sourceLabel,
            );
          }
        case BankEventKind.cardSpend:
          final match = findExisting(se, (t) => t.fromCardId == card.id, 2);
          if (match != null) {
            claimed.add(match.id);
            result.duplicates++;
          } else {
            result.added.add(
              txn(
                se,
                TxnType.expense,
                category: guessCategory(e.description ?? ''),
                fromCardId: card.id,
              ),
            );
          }
        case BankEventKind.cardRefund:
          final match = findExisting(se, (t) => t.toCardId == card.id, 2);
          if (match != null) {
            claimed.add(match.id);
            result.duplicates++;
          } else {
            result.added.add(
              txn(
                se,
                TxnType.refund,
                category: guessCategory(e.description ?? ''),
                toCardId: card.id,
              ),
            );
          }
        case BankEventKind.cardPayment:
          // Already recorded from the bank side (or by hand)?
          final match = findExisting(
            se,
            (t) => t.type == TxnType.cardPayment && t.toCardId == card.id,
            4,
            sameSource: true,
          );
          final pendingMatch = result.added.indexWhere(
            (t) =>
                t.type == TxnType.cardPayment &&
                t.toCardId == card.id &&
                t.amount == e.amount &&
                t.date.difference(e.date).inDays.abs() <= 4,
          );
          if (match != null) {
            claimed.add(match.id);
            result.duplicates++;
          } else if (pendingMatch >= 0) {
            result.duplicates++;
          } else {
            result.added.add(txn(se, TxnType.cardPayment, toCardId: card.id));
            openPayments.add(result.added.length - 1);
          }
        default:
          break;
      }
      continue;
    }

    final account = accountFor(e.digits);
    if (account == null) {
      noteUnknown(e);
      continue;
    }
    if (e.balance != null) {
      final hint = result.balances[account.id];
      if (hint == null || !e.date.isBefore(hint.date)) {
        result.balances[account.id] = BalanceHint(e.balance!, e.date);
      }
    }

    if (e.kind == BankEventKind.accountDebit && e.paysCard) {
      final card =
          cardFor(e.cardDigits) ??
          (l.cards.length == 1 ? l.cards.single : null);
      if (card != null) {
        // The card's own "payment received" message may already be here,
        // without the paying account: complete it instead of adding another.
        final open = openPayments.where((i) {
          final t = result.added[i];
          return t.toCardId == card.id &&
              t.amount == e.amount &&
              t.date.difference(e.date).inDays.abs() <= 4;
        }).firstOrNull;
        if (open != null) {
          openPayments.remove(open);
          result.added[open] = Txn.fromJson({
            ...result.added[open].toJson(),
            'fromAccount': account.id,
          });
          result.duplicates++;
          continue;
        }
        final existing = findExisting(
          se,
          (t) => t.type == TxnType.cardPayment && t.toCardId == card.id,
          4,
          sameSource: true,
        );
        if (existing != null) {
          claimed.add(existing.id);
          if (existing.fromAccountId == null) {
            result.updated.add(
              Txn.fromJson({...existing.toJson(), 'fromAccount': account.id}),
            );
          } else {
            result.duplicates++;
          }
          continue;
        }
        result.added.add(
          txn(
            se,
            TxnType.cardPayment,
            fromAccountId: account.id,
            toCardId: card.id,
          ),
        );
        continue;
      }
    }

    if (e.kind == BankEventKind.accountDebit) {
      final match = findExisting(se, (t) => t.fromAccountId == account.id, 2);
      if (match != null) {
        claimed.add(match.id);
        result.duplicates++;
      } else {
        result.added.add(
          txn(
            se,
            TxnType.expense,
            category: e.paysCard ? 'Bills' : guessCategory(e.description ?? ''),
            fromAccountId: account.id,
          ),
        );
      }
    } else if (e.kind == BankEventKind.accountCredit) {
      final match = findExisting(se, (t) => t.toAccountId == account.id, 2);
      if (match != null) {
        claimed.add(match.id);
        result.duplicates++;
      } else {
        result.added.add(
          txn(
            se,
            TxnType.income,
            category: guessIncomeCategory(e.description ?? ''),
            toAccountId: account.id,
          ),
        );
      }
    }
  }
  return result;
}

/// Short summary of a result for a snackbar.
String describeSync(SyncResult r) {
  final parts = <String>[
    if (r.added.isNotEmpty) tr('{0} new', [r.added.length]),
    if (r.updated.isNotEmpty) tr('{0} linked', [r.updated.length]),
    if (r.bills.isNotEmpty)
      r.bills.length == 1 ? tr('1 bill') : tr('{0} bills', [r.bills.length]),
    if (r.unknown.isNotEmpty)
      r.unknown.length == 1
          ? tr('1 new card/account found')
          : tr('{0} new cards/accounts found', [r.unknown.length]),
  ];
  return parts.isEmpty ? tr('Everything is up to date') : parts.join(' · ');
}
