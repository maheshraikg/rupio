import 'package:flutter_test/flutter_test.dart';
import 'package:rupeetrack/app/store.dart';
import 'package:rupeetrack/ledger/ledger.dart';
import 'package:rupeetrack/models/models.dart';
import 'package:rupeetrack/sync/bank_messages.dart';
import 'package:rupeetrack/app/native.dart';
import 'package:rupeetrack/sync/sms_sync.dart';
import 'package:rupeetrack/sync/statement_pdf.dart';
import 'package:rupeetrack/sync/statement_text.dart';
import 'package:rupeetrack/sync/sync.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

SourcedEvent sms(String body, DateTime received, {String sender = ''}) {
  final e = parseBankMessage(body, received: received, sender: sender);
  expect(e, isNotNull, reason: body);
  return SourcedEvent('sms:${stableHash('$sender|$received|$body')}', e!);
}

const hdfc = CreditCard(
  id: 10,
  name: 'HDFC Millennia',
  lastFour: '4821',
  creditLimit: 15000000,
  statementDay: 15,
  dueDay: 5,
);
const sbi = Account(
  id: 1,
  name: 'SBI',
  kind: AccountKind.savings,
  openingBalance: 10000000,
  lastFour: '1234',
);

final spend = sms(
  'Spent Rs.499.00 On HDFC Bank Card 4821 At SWIGGY On 2026-10-29:14:22:05 '
  'Bal Rs.115151.00',
  DateTime(2026, 10, 29, 14, 23),
);
final bill = sms(
  'Statement for your HDFC Bank Credit Card ending 4821 has been generated. '
  'Total Amount Due: Rs.30,150.00, Minimum Amount Due: Rs.1,510.00. Payment '
  'Due Date: 05-11-2026.',
  DateTime(2026, 10, 16, 9),
);
final cardPaid = sms(
  'Payment of Rs. 30,150.00 has been received on your HDFC Bank Credit Card '
  'ending 4821 on 01-11-2026. Thank you.',
  DateTime(2026, 11, 1, 10),
);
final bankPaid = sms(
  'Rs.30150.00 debited from A/c XX1234 on 01-11-26 towards HDFC Bank Credit '
  'Card XX4821 payment. Avl bal Rs.65,382.00',
  DateTime(2026, 11, 1, 9, 58),
);
final otherCard = sms(
  'INR 2,499.00 spent using ICICI Bank Card XX4003 on 29-Oct-26 on AMAZON. '
  'Avl Limit: INR 1,38,000.00.',
  DateTime(2026, 10, 29, 20),
);

void main() {
  test('stableHash is stable and spreads', () {
    expect(stableHash('abc'), stableHash('abc'));
    expect(stableHash('abc'), isNot(stableHash('abd')));
  });

  test('card spend becomes an expense with a guessed category', () {
    final r = planSync([spend], Ledger(cards: [hdfc]));
    final t = r.added.single;
    expect(t.type, TxnType.expense);
    expect(t.fromCardId, 10);
    expect(t.amount, 49900);
    expect(t.category, 'Food');
    expect(t.note, 'SWIGGY');
    expect(t.sourceKey, startsWith('sms:'));
  });

  test('same message twice, or a deleted one, is not added again', () {
    final l = Ledger(
      cards: [hdfc],
      txns: [
        planSync([spend], Ledger(cards: [hdfc])).added.single.copyWith(id: 5),
      ],
    );
    expect(planSync([spend], l).added, isEmpty);
    expect(
      planSync([spend], Ledger(cards: [hdfc]), ignoredKeys: {spend.key}).added,
      isEmpty,
    );
  });

  test('matches an entry typed in by hand instead of duplicating it', () {
    final manual = Txn(
      id: 7,
      type: TxnType.expense,
      amount: 49900,
      date: d(2026, 10, 28),
      category: 'Food',
      fromCardId: 10,
    );
    final r = planSync([spend], Ledger(cards: [hdfc], txns: [manual]));
    expect(r.added, isEmpty);
    expect(r.duplicates, 1);
  });

  test('two identical purchases from the same source both count', () {
    final second = sms(
      'Spent Rs.499.00 On HDFC Bank Card 4821 At SWIGGY On '
      '2026-10-29:20:01:00 Bal Rs.114652.00',
      DateTime(2026, 10, 29, 20, 2),
    );
    expect(
      planSync([spend, second], Ledger(cards: [hdfc])).added,
      hasLength(2),
    );
  });

  test('statement SMS sets the bill and due day', () async {
    final store = FinanceStore.memory();
    await store.restoreBackup(
      '{"app":"rupeetrack","cards":[${_json(hdfc)}],"nextId":20}',
    );
    await store.applySync(store.planEvents([bill]));
    final c = store.ledger.cards.single;
    expect(c.bill!.totalDue, 3015000);
    expect(c.bill!.minDue, 151000);
    expect(c.dueDay, 5);
    final s = store.ledger.cardStatus(c, d(2026, 10, 30));
    expect(s.fromBank, isTrue);
    expect(s.amountDue, 3015000);
    expect(s.minDue, 151000);
    expect(s.dueDate, d(2026, 11, 5));
  });

  test('card payment and the bank debit that paid it become one entry', () {
    final r = planSync([
      cardPaid,
      bankPaid,
    ], Ledger(accounts: [sbi], cards: [hdfc]));
    final t = r.added.single;
    expect(t.type, TxnType.cardPayment);
    expect(t.fromAccountId, 1);
    expect(t.toCardId, 10);
    expect(r.balances[1]!.balance, 6538200);
  });

  test('a later bank debit completes an earlier imported card payment', () {
    final first = planSync([cardPaid], Ledger(accounts: [sbi], cards: [hdfc]));
    final l = Ledger(
      accounts: [sbi],
      cards: [hdfc],
      txns: [first.added.single.copyWith(id: 3)],
    );
    expect(l.txns.single.fromAccountId, isNull);
    final r = planSync([bankPaid], l);
    expect(r.added, isEmpty);
    expect(r.updated.single.id, 3);
    expect(r.updated.single.fromAccountId, 1);
  });

  test('unknown cards and accounts are reported, not imported', () {
    final r = planSync([otherCard, bankPaid], Ledger(cards: [hdfc]));
    expect(r.added, isEmpty);
    final card = r.unknown['c4003']!;
    expect(card.isCard, isTrue);
    expect(card.bank, 'ICICI Bank');
    expect(card.count, 1);
    expect(card.spent, 249900);
    expect(card.latestFigure, 13800000);
    expect(r.unknown['a1234']!.isCard, isFalse);
  });

  test(
    'imported history before a card was added does not change what is owed',
    () {
      final card = CreditCard(
        id: 10,
        name: 'HDFC',
        lastFour: '4821',
        creditLimit: 15000000,
        statementDay: 15,
        dueDay: 5,
        openingOutstanding: 3000000,
        since: d(2026, 10, 30),
      );
      final r = planSync([spend], Ledger(cards: [card]));
      final l = Ledger(cards: [card], txns: [r.added.single.copyWith(id: 1)]);
      expect(l.cardOutstanding(10), 3000000);
      expect(l.spending(d(2026, 10, 1), d(2026, 10, 31)), 49900);
    },
  );

  test('SMS from personal numbers are ignored; keys are stable', () {
    const body =
        'Spent Rs.499.00 On HDFC Bank Card 4821 At SWIGGY On 2026-10-29';
    final at = DateTime(2026, 10, 29, 14);
    final events = SmsSync.eventsFrom([
      SmsMessage(sender: 'AD-HDFCBK', body: body, received: at),
      SmsMessage(sender: '+919876543210', body: body, received: at),
      SmsMessage(sender: 'AD-HDFCBK', body: 'Your OTP is 123456', received: at),
    ]);
    expect(events, hasLength(1));
    final again = SmsSync.eventsFrom([
      SmsMessage(sender: 'AD-HDFCBK', body: body, received: at),
    ]);
    expect(again.single.key, events.single.key);
  });

  test('importing the same statement twice adds nothing the second time', () {
    const text = """
HDFC Bank Credit Card Statement
Card No: 5241 XXXX XXXX 4821
Payment Due Date 05/11/2026
Total Amount Due Rs. 2,948.00
18/09/2026 SWIGGY BANGALORE 450.00
18/09/2026 SWIGGY BANGALORE 450.00
""";
    final plan = planStatement(text)!;
    final first = planSync(plan.events, Ledger(cards: [hdfc]));
    expect(first.added, hasLength(2)); // two identical lines = two orders
    final l = Ledger(
      cards: [hdfc],
      txns: [
        for (var i = 0; i < first.added.length; i++)
          first.added[i].copyWith(id: i + 1),
      ],
    );
    expect(planSync(planStatement(text)!.events, l).added, isEmpty);
  });

  group('statement PDF text', () {
    test('credit card statement', () {
      const text = '''
HDFC Bank Credit Card Statement
Card No: 5241 XXXX XXXX 4821
Statement Date 15/10/2026
Payment Due Date 05/11/2026
Total Amount Due Rs. 30,150.00
Minimum Amount Due Rs. 1,510.00
Date Transaction Description Amount (in Rs.)
18/09/2026 AMAZON PAY INDIA BANGALORE 2,499.00
22/09/2026 SWIGGY BANGALORE 450.50
01/10/2026 PAYMENT RECEIVED - THANK YOU 12,000.00 Cr
05/10/2026 AMAZON REFUND 499.00 Cr
''';
      final s = parseStatementText(text)!;
      expect(s.isCard, isTrue);
      expect(s.digits, '4821');
      expect(s.bank, 'HDFC Bank');
      final kinds = s.events.map((e) => e.kind).toList();
      expect(kinds, [
        BankEventKind.cardBill,
        BankEventKind.cardSpend,
        BankEventKind.cardSpend,
        BankEventKind.cardPayment,
        BankEventKind.cardRefund,
      ]);
      expect(s.events.first.amount, 3015000);
      expect(s.events.first.minDue, 151000);
      expect(s.events.first.dueDate, d(2026, 11, 5));
      expect(s.events.first.statementDate, d(2026, 10, 15));
      expect(s.events[2].amount, 45050);
      expect(s.transactionCount, 4);
    });

    test('bank statement: direction from the running balance', () {
      const text = '''
State Bank of India
Account Number XXXXXXX1234
Date Description Debit Credit Balance
01/10/2026 Opening Balance 10,000.00
01/10/2026 NEFT SALARY ACME CORP 85,000.00 95,000.00
03/10/2026 UPI/SWIGGY/612345 250.00 94,750.00
05/10/2026 ATM WDL BANGALORE 2,000.00 92,750.00
''';
      final s = parseStatementText(text)!;
      expect(s.isCard, isFalse);
      expect(s.digits, '1234');
      expect(s.events.map((e) => e.kind), [
        BankEventKind.accountCredit,
        BankEventKind.accountDebit,
        BankEventKind.accountDebit,
      ]);
      expect(s.events.last.balance, 9275000);
    });

    test('not a statement', () {
      expect(parseStatementText('Hello world\nNothing here'), isNull);
    });
  });
}

String _json(CreditCard c) {
  final j = c.toJson();
  return '{${j.entries.map((e) => '"${e.key}":${e.value is String ? '"${e.value}"' : e.value}').join(',')}}';
}
