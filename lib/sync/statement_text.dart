/// Reads the text of a bank or credit card statement (extracted from the PDF)
/// into [BankEvent]s: the bill summary and one event per transaction line.
library;

import '../models/money.dart';
import 'bank_messages.dart';

class StatementText {
  const StatementText({
    required this.isCard,
    required this.events,
    this.digits,
    this.bank,
  });

  /// Credit card statement (otherwise a bank account statement).
  final bool isCard;

  /// Card or account digits printed on the statement, if found.
  final String? digits;
  final String? bank;

  /// Bill (cards) followed by transactions, oldest first.
  final List<BankEvent> events;

  int get transactionCount =>
      events.where((e) => e.kind != BankEventKind.cardBill).length;
}

const _date =
    r'\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}'
    r'|\d{1,2}[\s\-]+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[\s\-,]+\d{2,4}'
    r'|\d{4}-\d{2}-\d{2}';
const _amt = r'([0-9][0-9,]*\.[0-9]{2})';
const _cur = r'(?:₹|rs\.?|inr)?\s*';

/// A transaction line: date, optional value date, description, amount,
/// optional Cr/Dr marker, optional running balance.
final _lineRe = RegExp(
  '^($_date)\\s+(?:(?:$_date)\\s+)?(.+?)\\s+$_cur$_amt\\s*(cr|dr|c|d|\\+|-)?'
  '(?:\\s+$_cur(-?[0-9][0-9,]*\\.[0-9]{2})\\s*(?:cr|dr)?)?\\s*\$',
  caseSensitive: false,
);

final _skipLineRe = RegExp(
  r'opening balance|closing balance|previous balance|balance (?:b/f|c/f|brought|carried)'
  r'|^\s*total|statement (?:date|period)|payment due date|minimum amount',
  caseSensitive: false,
);

final _creditWordsRe = RegExp(
  r'payment received|payment - thank|thank you|refund|reversal|reversed|cashback'
  r'|credit adj|neft cr|imps cr|upi cr|salary|interest paid|int\.?\s*pd|by transfer',
  caseSensitive: false,
);

/// Parses statement text. Returns null when it does not look like a bank or
/// card statement.
StatementText? parseStatementText(String text, {String sender = ''}) {
  final flat = text.replaceAll(RegExp(r'[ \t]+'), ' ');
  final lower = flat.toLowerCase();
  final isCard =
      lower.contains('credit card') ||
      lower.contains('minimum amount due') ||
      lower.contains('total amount due');
  final bank = detectBank(sender, flat);

  final digits = RegExp(
    r'(?:\d{4}|[x*•]{4})[\s\-]*[x*•]{2,4}[\s\-]*[x*•]{2,4}[\s\-]*(\d{4})'
    r'|(?:card|account|a/c)\s*(?:no\.?|number)?\s*:?\s*[x*•]{2,}\s*(\d{3,6})',
    caseSensitive: false,
  ).firstMatch(flat);
  final cardDigits = digits?.group(1) ?? digits?.group(2);

  final events = <BankEvent>[];
  if (isCard) {
    final total = amountAfter(flat, [
      'total amount due',
      'total amt due',
      'total dues',
      'total due',
    ], window: 80);
    final due = dateAfter(flat, [
      'payment due date',
      'due date',
      'pay by',
    ], window: 80);
    if (total != null && due != null && cardDigits != null) {
      events.add(
        BankEvent(
          kind: BankEventKind.cardBill,
          amount: total,
          date: due,
          dueDate: due,
          digits: cardDigits,
          bank: bank,
          minDue: amountAfter(flat, [
            'minimum amount due',
            'minimum amt due',
            'min amount due',
            'minimum due',
          ], window: 80),
          statementDate: dateAfter(flat, [
            'statement date',
            'stmt date',
          ], window: 60),
          availableLimit: amountAfter(flat, [
            'available credit limit',
            'available limit',
          ], window: 80),
        ),
      );
    }
  }

  Paise? previousBalance;
  for (final raw in text.split('\n')) {
    final line = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (line.isEmpty || _skipLineRe.hasMatch(line)) continue;
    final m = _lineRe.firstMatch(line);
    if (m == null) continue;
    final dates = datesIn(m.group(1)!);
    if (dates.isEmpty) continue;
    final description = m.group(2)!.trim();
    final amount = parseMoney(m.group(3)!);
    if (amount == null || amount == 0) continue;
    final marker = (m.group(4) ?? '').toLowerCase();
    final balanceText = m.group(5);
    final balance = balanceText == null
        ? null
        : (balanceText.startsWith('-') ? -1 : 1) *
              (parseMoney(balanceText.replaceFirst('-', '')) ?? 0);

    // Money in or out: explicit marker, else the change in running balance,
    // else words like "refund" / "payment received".
    bool? credit = switch (marker) {
      'cr' || 'c' || '+' => true,
      'dr' || 'd' || '-' => false,
      _ => null,
    };
    if (credit == null && balance != null && previousBalance != null) {
      if (balance - previousBalance == amount) credit = true;
      if (previousBalance - balance == amount) credit = false;
    }
    credit ??= _creditWordsRe.hasMatch(description);
    if (balance != null) previousBalance = balance;

    final lowerDesc = description.toLowerCase();
    final BankEventKind kind;
    if (isCard) {
      kind = !credit
          ? BankEventKind.cardSpend
          : (lowerDesc.contains('payment') || lowerDesc.contains('thank you'))
          ? BankEventKind.cardPayment
          : BankEventKind.cardRefund;
    } else {
      kind = credit ? BankEventKind.accountCredit : BankEventKind.accountDebit;
    }
    events.add(
      BankEvent(
        kind: kind,
        amount: amount,
        date: dates.first,
        digits: cardDigits ?? '',
        bank: bank,
        description: description,
        balance: isCard ? null : balance,
        paysCard:
            !isCard &&
            !credit &&
            RegExp(
              r'credit\s*card|card\s*payment|\bcc\b',
              caseSensitive: false,
            ).hasMatch(description),
      ),
    );
  }

  if (events.isEmpty) return null;
  events.sort((a, b) {
    // The bill first, then transactions oldest first.
    if (a.kind == BankEventKind.cardBill) return -1;
    if (b.kind == BankEventKind.cardBill) return 1;
    return a.date.compareTo(b.date);
  });
  return StatementText(
    isCard: isCard,
    events: events,
    digits: cardDigits,
    bank: bank,
  );
}
