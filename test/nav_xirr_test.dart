import 'package:flutter_test/flutter_test.dart';
import 'package:rupeetrack/app/store.dart';
import 'package:rupeetrack/data/amfi.dart';
import 'package:rupeetrack/models/models.dart';

void main() {
  test(
    'SIP into a NAV-linked fund buys units; value follows the NAV',
    () async {
      final store = FinanceStore.memory();
      final acc = await store.addAccount('SBI', AccountKind.savings, 10000000);
      var fund = await store.addInvestment(
        'Index fund',
        InvestmentType.mutualFund,
      );
      await store.linkScheme(fund, '120716', 100); // 100 units held
      await store.applyNavs({
        '120716': NavQuote(
          code: '120716',
          name: 'Index',
          nav: 50,
          date: DateTime.utc(2026, 10, 1),
        ),
      });
      fund = store.ledger.investments.single;
      expect(store.ledger.valueOf(fund), 500000); // 100 × ₹50

      // ₹1,000 SIP at NAV 50 buys 20 units.
      await store.saveTxn(
        Txn(
          id: 0,
          type: TxnType.invest,
          amount: 100000,
          date: DateTime.utc(2026, 10, 5),
          fromAccountId: acc.id,
          investmentId: fund.id,
        ),
      );
      expect(store.ledger.unitsHeld(fund), closeTo(120, 1e-9));
      expect(store.ledger.valueOf(store.ledger.investments.single), 600000);

      // NAV rises to 55: value = 120 × 55.
      await store.applyNavs({
        '120716': NavQuote(
          code: '120716',
          name: 'Index',
          nav: 55,
          date: DateTime.utc(2026, 11, 1),
        ),
      });
      expect(store.ledger.valueOf(store.ledger.investments.single), 660000);

      // Withdrawing ₹550 sells 10 units.
      await store.saveTxn(
        Txn(
          id: 0,
          type: TxnType.investWithdrawal,
          amount: 55000,
          date: DateTime.utc(2026, 11, 2),
          toAccountId: acc.id,
          investmentId: fund.id,
        ),
      );
      expect(
        store.ledger.unitsHeld(store.ledger.investments.single),
        closeTo(110, 1e-9),
      );
    },
  );

  test('XIRR counts from the investment date, not from today', () async {
    final store = FinanceStore.memory();
    // ₹1,00,000 invested on 1 Nov 2024, worth ₹1,21,000 on 1 Nov 2026:
    // 10% a year over two years.
    final inv = await store.addInvestment(
      'FD',
      InvestmentType.fixedDeposit,
      invested: 10000000,
      investedOn: DateTime.utc(2024, 11, 1),
    );
    await store.updateInvestmentValue(inv, 12100000, DateTime.utc(2026, 11, 1));
    final s = store.ledger.investmentSummary(
      store.ledger.investments.single,
      DateTime.utc(2026, 11, 1),
    );
    expect(s.xirr, closeTo(0.10, 0.001));
    expect(s.returnPercent, closeTo(21, 1e-9));
  });

  test('under a year: no yearly rate, only the plain return', () async {
    final store = FinanceStore.memory();
    final inv = await store.addInvestment(
      'Fund',
      InvestmentType.mutualFund,
      invested: 10000000,
      investedOn: DateTime.utc(2026, 10, 20),
    );
    await store.updateInvestmentValue(inv, 10200000, DateTime.utc(2026, 11, 1));
    final s = store.ledger.investmentSummary(
      store.ledger.investments.single,
      DateTime.utc(2026, 11, 1),
    );
    expect(s.xirr, isNull); // 2% in 12 days must not show as ~80% a year
    expect(s.xirrTooEarly, isTrue);
    expect(s.returnPercent, closeTo(2, 1e-9));
  });

  test('old amount without a start date gives no yearly rate', () async {
    final store = FinanceStore.memory();
    final inv = await store.addInvestment(
      'PPF',
      InvestmentType.ppf,
      invested: 10000000,
    );
    await store.updateInvestmentValue(inv, 15000000, DateTime.utc(2026, 11, 1));
    final s = store.ledger.investmentSummary(
      store.ledger.investments.single,
      DateTime.utc(2026, 11, 1),
    );
    expect(s.xirr, isNull);
    expect(s.returnPercent, closeTo(50, 1e-9));
  });
}
