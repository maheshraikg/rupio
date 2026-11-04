import 'package:flutter_test/flutter_test.dart';
import 'package:rupeetrack/ledger/ledger.dart';
import 'package:rupeetrack/ledger/returns.dart';
import 'package:rupeetrack/models/models.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

void main() {
  group('xirr', () {
    test('one year, 10% gain', () {
      final r = xirr([
        CashFlow(d(2025, 1, 1), -100000),
        CashFlow(d(2026, 1, 1), 110000),
      ]);
      expect(r, closeTo(0.10, 1e-6));
    });

    test('monthly SIP with a loss gives a negative rate', () {
      final flows = [
        for (var m = 1; m <= 12; m++) CashFlow(d(2025, m, 5), -500000),
        CashFlow(d(2026, 1, 5), 5700000),
      ];
      expect(xirr(flows)!, lessThan(0));
    });

    test('needs money in and out on different dates', () {
      expect(xirr([CashFlow(d(2025, 1, 1), -100)]), isNull);
      expect(
        xirr([CashFlow(d(2025, 1, 1), -100), CashFlow(d(2025, 1, 1), 110)]),
        isNull,
      );
    });
  });

  test(
    'investment summary counts withdrawals and payouts, not reinvested income',
    () {
      final fund = const Investment(
        id: 1,
        name: 'PPF',
        type: InvestmentType.ppf,
      ).withValue(11000000, d(2026, 10, 1));
      final l = Ledger(
        accounts: [
          const Account(
            id: 2,
            name: 'SBI',
            kind: AccountKind.savings,
            openingBalance: 0,
          ),
        ],
        investments: [fund],
        txns: [
          Txn(
            id: 3,
            type: TxnType.invest,
            amount: 10000000,
            date: d(2025, 10, 1),
            fromAccountId: 2,
            investmentId: 1,
          ),
          Txn(
            id: 4,
            type: TxnType.investWithdrawal,
            amount: 500000,
            date: d(2026, 4, 1),
            toAccountId: 2,
            investmentId: 1,
          ),
          Txn(
            id: 5,
            type: TxnType.investIncome,
            amount: 100000,
            date: d(2026, 5, 1),
            toAccountId: 2,
            investmentId: 1,
          ),
          Txn(
            id: 6,
            type: TxnType.investIncome,
            amount: 999900,
            date: d(2026, 6, 1),
            investmentId: 1,
          ),
        ],
      );
      final s = l.investmentSummary(fund, d(2026, 10, 30));
      expect(s.contributed, 10000000);
      expect(s.withdrawn, 500000);
      expect(s.incomePaidOut, 100000);
      expect(s.netInvested, 9500000);
      // 1,10,000 value + 5,000 withdrawn + 1,000 paid out − 1,00,000 put in.
      expect(s.absoluteReturn, 1600000);
      expect(s.returnPercent, closeTo(16, 1e-9));
      expect(s.xirr, isNotNull);
      expect(s.xirr!, greaterThan(0.15));
    },
  );

  test('no current value means no return shown', () {
    const inv = Investment(id: 1, name: 'NSC', type: InvestmentType.nsc);
    final s = Ledger(investments: [inv]).investmentSummary(inv, d(2026, 1, 1));
    expect(s.absoluteReturn, isNull);
    expect(s.returnPercent, isNull);
    expect(s.xirr, isNull);
  });
}
