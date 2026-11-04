import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rupeetrack/app/widget_data.dart';
import 'package:rupeetrack/app/store.dart';
import 'package:rupeetrack/ledger/ledger.dart';
import 'package:rupeetrack/models/goals.dart';
import 'package:rupeetrack/models/models.dart';

void main() {
  test('loan progress, next due, EMI per month and alerts', () async {
    final store = FinanceStore.memory();
    final acc = await store.addAccount('SBI', AccountKind.savings, 10000000);
    final loan = await store.saveLoan(
      Loan(
        id: 0,
        name: 'Bike',
        emi: 500000,
        tenureMonths: 12,
        firstEmiDate: DateTime.utc(2026, 1, 31),
        paidBefore: 9,
      ),
    );
    final day = DateTime.utc(2026, 10, 29);
    var s = store.ledger.loanStatus(loan, day);
    expect(s.emisPaid, 9);
    expect(s.emisLeft, 3);
    expect(s.nextDue, DateTime.utc(2026, 10, 31));
    expect(s.remaining, 1500000);
    expect(loan.lastEmiDate, DateTime.utc(2026, 12, 31));
    expect(DateTime.utc(2026, 2, 28), loan.emiDate(1)); // clamped
    expect(store.ledger.monthlyEmi(day), 500000);
    expect(
      store.ledger.alerts(day).where((a) => a.kind == AlertKind.emiDue),
      hasLength(1),
    );

    await store.payEmi(loan, accountId: acc.id, date: day);
    s = store.ledger.loanStatus(loan, day);
    expect(s.emisPaid, 10);
    expect(s.paidThisMonth, isTrue);
    expect(s.nextDue, DateTime.utc(2026, 11, 30));
    expect(store.ledger.accountBalance(acc.id), 9500000);
    expect(store.ledger.spendingByCategory(day, day)['EMI'], 500000);

    // Payoff: 2 EMIs left (Nov 30, Dec 31) at the start of November.
    final payoff = store.ledger.loanPayoff(day);
    expect(payoff.first, (DateTime.utc(2026, 10), 1000000 + 0));
    expect(payoff.map((p) => p.$2), [1000000, 1000000, 500000, 0]);
    expect(store.ledger.debtFreeMonth(day), DateTime.utc(2026, 12));

    // Survives a JSON round trip.
    final copy = FinanceStore.memory();
    await copy.restoreBackup(store.backupJson());
    expect(copy.ledger.loanStatus(copy.ledger.loans.single, day).emisPaid, 10);
  });

  test('savings goal progress and monthly amount needed', () async {
    final store = FinanceStore.memory();
    final g = await store.saveGoal(
      SavingsGoal(
        id: 0,
        name: 'Phone',
        target: 6000000,
        targetDate: DateTime.utc(2027, 4, 1),
        entries: [GoalEntry(DateTime.utc(2026, 10, 1), 1200000)],
      ),
    );
    expect(g.progress, closeTo(0.2, 1e-9));
    expect(g.monthlyNeeded(DateTime.utc(2026, 10, 15)), 800000); // 6 months
    await store.addToGoal(g, 4800000, DateTime.utc(2026, 11, 1));
    final done = store.ledger.goals.single;
    expect(done.reached, isTrue);
    expect(done.monthlyNeeded(DateTime.utc(2026, 11, 2)), isNull);
    expect(store.ledger.goalsSaved, 6000000);
  });

  test('home widget data: this month per day', () async {
    final store = FinanceStore.memory();
    final acc = await store.addAccount('Cash', AccountKind.cash, 100000);
    await store.saveTxn(
      Txn(
        id: 0,
        type: TxnType.expense,
        amount: 25050,
        date: DateTime.utc(2026, 11, 3),
        category: 'Food',
        fromAccountId: acc.id,
      ),
    );
    final j = jsonDecode(widgetJson(store.ledger, DateTime.utc(2026, 11, 20)));
    expect(j['label'], 'Spent in November');
    expect(j['total'], '₹250.50');
    expect((j['values'] as List), hasLength(30));
    expect((j['values'] as List)[2], 250.5);
  });
}
