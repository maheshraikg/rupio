import 'package:flutter_test/flutter_test.dart';
import 'package:rupeetrack/ledger/billing_cycle.dart';
import 'package:rupeetrack/ledger/ledger.dart';
import 'package:rupeetrack/models/models.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

const sbi = Account(
  id: 1,
  name: 'SBI Savings',
  kind: AccountKind.savings,
  openingBalance: 1000000, // ₹10,000
);
const canara = Account(
  id: 2,
  name: 'Canara',
  kind: AccountKind.savings,
  openingBalance: 500000,
);
const hdfc = CreditCard(
  id: 10,
  name: 'HDFC',
  lastFour: '1234',
  creditLimit: 10000000, // ₹1,00,000
  statementDay: 15,
  dueDay: 5,
);
const fund = Investment(
  id: 20,
  name: 'Index fund',
  type: InvestmentType.mutualFund,
);

Txn txn(
  int id,
  TxnType type,
  int rupees,
  DateTime date, {
  String? category,
  int? fromAccount,
  int? fromCard,
  int? toAccount,
  int? toCard,
  int? investment,
}) => Txn(
  id: id,
  type: type,
  amount: rupees * 100,
  date: date,
  category: category,
  fromAccountId: fromAccount,
  fromCardId: fromCard,
  toAccountId: toAccount,
  toCardId: toCard,
  investmentId: investment,
);

void main() {
  group('accounting rules', () {
    test('₹250 food expense from SBI reduces SBI and counts as Food', () {
      final l = Ledger(
        accounts: [sbi],
        txns: [
          txn(
            1,
            TxnType.expense,
            250,
            d(2026, 10, 3),
            category: 'Food',
            fromAccount: 1,
          ),
        ],
      );
      expect(l.accountBalance(1), 975000);
      expect(l.spendingByCategory(d(2026, 10, 1), d(2026, 10, 31)), {
        'Food': 25000,
      });
      expect(l.totalCardOutstanding, 0);
    });

    test('transfers move money but are not income or spending', () {
      final l = Ledger(
        accounts: [sbi, canara],
        txns: [
          txn(
            1,
            TxnType.transfer,
            2000,
            d(2026, 10, 3),
            fromAccount: 1,
            toAccount: 2,
          ),
        ],
      );
      expect(l.accountBalance(1), 800000);
      expect(l.accountBalance(2), 700000);
      expect(l.totalCash, 1500000);
      expect(l.spending(d(2026, 10, 1), d(2026, 10, 31)), 0);
      expect(l.income(d(2026, 10, 1), d(2026, 10, 31)), 0);
    });

    test(
      'card purchase is an expense; paying the bill is not a second one',
      () {
        final l = Ledger(
          accounts: [sbi],
          cards: [hdfc],
          txns: [
            txn(
              1,
              TxnType.expense,
              3000,
              d(2026, 10, 2),
              category: 'Shopping',
              fromCard: 10,
            ),
            txn(
              2,
              TxnType.cardPayment,
              3000,
              d(2026, 10, 20),
              fromAccount: 1,
              toCard: 10,
            ),
          ],
        );
        expect(l.spending(d(2026, 10, 1), d(2026, 10, 31)), 300000);
        expect(l.cardOutstanding(10), 0);
        expect(l.accountBalance(1), 700000);
      },
    );

    test('refund reduces spending in its category and the card balance', () {
      final l = Ledger(
        cards: [hdfc],
        txns: [
          txn(
            1,
            TxnType.expense,
            1000,
            d(2026, 10, 2),
            category: 'Shopping',
            fromCard: 10,
          ),
          txn(
            2,
            TxnType.refund,
            400,
            d(2026, 10, 5),
            category: 'Shopping',
            toCard: 10,
          ),
        ],
      );
      expect(l.spendingByCategory(d(2026, 10, 1), d(2026, 10, 31)), {
        'Shopping': 60000,
      });
      expect(l.cardOutstanding(10), 60000);
    });

    test('investing is kept out of spending and adds to the portfolio', () {
      final l = Ledger(
        accounts: [sbi],
        investments: [fund],
        txns: [
          txn(
            1,
            TxnType.invest,
            2000,
            d(2026, 10, 5),
            fromAccount: 1,
            investment: 20,
          ),
        ],
      );
      expect(l.accountBalance(1), 800000);
      expect(l.spending(d(2026, 10, 1), d(2026, 10, 31)), 0);
      expect(l.invested(d(2026, 10, 1), d(2026, 10, 31)), 200000);
      expect(l.investmentSummary(fund, d(2026, 10, 30)).netInvested, 200000);
    });

    test(
      'investment bought on a card: card liability and investment, no expense',
      () {
        final l = Ledger(
          accounts: [sbi],
          cards: [hdfc],
          investments: [fund],
          txns: [
            txn(
              1,
              TxnType.invest,
              5000,
              d(2026, 10, 5),
              fromCard: 10,
              investment: 20,
            ),
            txn(
              2,
              TxnType.cardPayment,
              5000,
              d(2026, 11, 1),
              fromAccount: 1,
              toCard: 10,
            ),
          ],
        );
        expect(l.spending(d(2026, 10, 1), d(2026, 11, 30)), 0);
        expect(l.investmentSummary(fund, d(2026, 11, 2)).contributed, 500000);
        expect(l.cardOutstanding(10), 0);
      },
    );

    test('net worth = cash + investments − card dues', () {
      final valued = fund.withValue(13375000, d(2026, 10, 30));
      final l = Ledger(
        accounts: [
          const Account(
            id: 1,
            name: 'SBI',
            kind: AccountKind.savings,
            openingBalance: 4825000,
          ),
        ],
        cards: [
          const CreditCard(
            id: 10,
            name: 'HDFC',
            lastFour: '',
            creditLimit: 10000000,
            statementDay: 15,
            dueDay: 5,
            openingOutstanding: 1260000,
          ),
        ],
        investments: [valued],
      );
      final w = l.netWorth(d(2026, 10, 30));
      expect(w.cash, 4825000);
      expect(w.investments, 13375000);
      expect(w.liabilities, 1260000);
      expect(w.total, 16940000); // ₹1,69,400 as in the concept example
      expect(w.hasUnvaluedInvestments, isFalse);
    });

    test('unvalued investments count at cost and are flagged', () {
      final l = Ledger(
        accounts: [sbi],
        investments: [fund],
        txns: [
          txn(
            1,
            TxnType.invest,
            2000,
            d(2026, 10, 5),
            fromAccount: 1,
            investment: 20,
          ),
        ],
      );
      final w = l.netWorth(d(2026, 10, 30));
      expect(w.investments, 200000);
      expect(w.hasUnvaluedInvestments, isTrue);
      expect(w.total, 1000000);
    });

    test('savings rate', () {
      final l = Ledger(
        accounts: [sbi],
        txns: [
          txn(
            1,
            TxnType.income,
            50000,
            d(2026, 10, 1),
            category: 'Salary',
            toAccount: 1,
          ),
          txn(
            2,
            TxnType.expense,
            30000,
            d(2026, 10, 9),
            category: 'Rent',
            fromAccount: 1,
          ),
        ],
      );
      expect(l.savingsRate(d(2026, 10, 1), d(2026, 10, 31)), 40);
    });

    test('transactions are sorted newest first', () {
      final l = Ledger(
        accounts: [sbi],
        txns: [
          txn(1, TxnType.expense, 1, d(2026, 10, 1), fromAccount: 1),
          txn(2, TxnType.expense, 1, d(2026, 10, 3), fromAccount: 1),
          txn(3, TxnType.expense, 1, d(2026, 10, 3), fromAccount: 1),
        ],
      );
      expect(l.txns.map((t) => t.id), [3, 2, 1]);
    });
  });

  group('validate', () {
    test('expense needs exactly one source', () {
      expect(validate(txn(1, TxnType.expense, 10, d(2026, 1, 1))), isNotEmpty);
      expect(
        validate(
          txn(
            1,
            TxnType.expense,
            10,
            d(2026, 1, 1),
            fromAccount: 1,
            fromCard: 2,
          ),
        ),
        isNotEmpty,
      );
      expect(
        validate(txn(1, TxnType.expense, 10, d(2026, 1, 1), fromAccount: 1)),
        isEmpty,
      );
    });

    test('amount must be positive', () {
      expect(
        validate(txn(1, TxnType.expense, 0, d(2026, 1, 1), fromAccount: 1)),
        isNotEmpty,
      );
    });

    test('transfer needs two different accounts', () {
      expect(
        validate(
          txn(
            1,
            TxnType.transfer,
            10,
            d(2026, 1, 1),
            fromAccount: 1,
            toAccount: 1,
          ),
        ),
        isNotEmpty,
      );
    });

    test('dividend can be reinvested (no account)', () {
      expect(
        validate(
          txn(1, TxnType.investIncome, 10, d(2026, 1, 1), investment: 20),
        ),
        isEmpty,
      );
    });
  });

  group('credit card billing', () {
    test('statement and due dates', () {
      // Statement on the 15th, due on the 5th of the next month.
      expect(
        BillingCycle.lastStatementDate(hdfc, d(2026, 10, 20)),
        d(2026, 10, 15),
      );
      expect(
        BillingCycle.lastStatementDate(hdfc, d(2026, 10, 15)),
        d(2026, 10, 15),
      );
      expect(
        BillingCycle.lastStatementDate(hdfc, d(2026, 10, 10)),
        d(2026, 9, 15),
      );
      expect(
        BillingCycle.lastStatementDate(hdfc, d(2026, 1, 3)),
        d(2025, 12, 15),
      );
      expect(BillingCycle.dueDateFor(hdfc, d(2026, 10, 15)), d(2026, 11, 5));
      expect(BillingCycle.dueDateFor(hdfc, d(2025, 12, 15)), d(2026, 1, 5));
    });

    test('short months clamp to the last day', () {
      const card = CreditCard(
        id: 1,
        name: 'X',
        lastFour: '',
        creditLimit: 1,
        statementDay: 31,
        dueDay: 20,
      );
      expect(
        BillingCycle.lastStatementDate(card, d(2026, 3, 1)),
        d(2026, 2, 28),
      );
      expect(BillingCycle.dueDateFor(card, d(2026, 2, 28)), d(2026, 3, 20));
      expect(
        BillingCycle.nextStatementDate(card, d(2026, 2, 28)),
        d(2026, 3, 31),
      );
    });

    test('bill, cycle spend and due date', () {
      final l = Ledger(
        accounts: [sbi],
        cards: [hdfc],
        txns: [
          txn(
            1,
            TxnType.expense,
            4000,
            d(2026, 10, 1),
            category: 'Shopping',
            fromCard: 10,
          ),
          txn(
            2,
            TxnType.expense,
            600,
            d(2026, 10, 18),
            category: 'Food',
            fromCard: 10,
          ),
        ],
      );
      final s = l.cardStatus(hdfc, d(2026, 10, 30));
      expect(s.statementBalance, 400000);
      expect(s.amountDue, 400000);
      expect(s.cycleSpend, 60000);
      expect(s.outstanding, 460000);
      expect(s.availableCredit, 9540000);
      expect(s.dueDate, d(2026, 11, 5));
      expect(s.overdue, isFalse);
      expect(s.utilisationPercent, closeTo(4.6, 1e-9));
    });

    test(
      'partial payment leaves the rest due; unpaid after due date is overdue',
      () {
        final l = Ledger(
          accounts: [sbi],
          cards: [hdfc],
          txns: [
            txn(1, TxnType.expense, 4000, d(2026, 10, 1), fromCard: 10),
            txn(
              2,
              TxnType.cardPayment,
              1500,
              d(2026, 10, 25),
              fromAccount: 1,
              toCard: 10,
            ),
          ],
        );
        expect(l.cardStatus(hdfc, d(2026, 11, 1)).amountDue, 250000);
        final late = l.cardStatus(hdfc, d(2026, 11, 8));
        expect(late.overdue, isTrue);
        expect(late.dueDate, d(2026, 11, 5));
      },
    );

    test('settled bill moves on to the next due date', () {
      final l = Ledger(
        accounts: [sbi],
        cards: [hdfc],
        txns: [
          txn(1, TxnType.expense, 4000, d(2026, 10, 1), fromCard: 10),
          txn(
            2,
            TxnType.cardPayment,
            4000,
            d(2026, 11, 2),
            fromAccount: 1,
            toCard: 10,
          ),
        ],
      );
      final s = l.cardStatus(hdfc, d(2026, 11, 8));
      expect(s.overdue, isFalse);
      expect(s.amountDue, 0);
      expect(s.dueDate, d(2026, 12, 5));
    });

    test('alerts: due soon and utilisation thresholds', () {
      final l = Ledger(
        accounts: [sbi],
        cards: [hdfc],
        txns: [txn(1, TxnType.expense, 55000, d(2026, 10, 1), fromCard: 10)],
      );
      expect(l.alerts(d(2026, 10, 20)).map((a) => a.kind), [
        AlertKind.highUtilisation,
      ]);
      final soon = l.alerts(d(2026, 11, 1));
      expect(soon.map((a) => a.kind), [
        AlertKind.dueSoon,
        AlertKind.highUtilisation,
      ]);
      expect(soon.first.message, contains('due in 4 days'));
      expect(soon.last.message, contains('over 50%'));
      expect(l.alerts(d(2026, 11, 5)).first.message, contains('due today'));
      expect(l.alerts(d(2026, 11, 6)).first.kind, AlertKind.overdue);
    });
  });
}
