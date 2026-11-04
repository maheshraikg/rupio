import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:rupeetrack/app/notifications.dart';
import 'package:rupeetrack/app/store.dart';
import 'package:rupeetrack/data/amfi.dart';
import 'package:rupeetrack/data/csv.dart';
import 'package:rupeetrack/data/reports.dart';
import 'package:rupeetrack/ledger/ledger.dart';
import 'package:rupeetrack/models/models.dart';
import 'package:rupeetrack/models/planning.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

Txn expense(int rupees, DateTime date, {String category = 'Food'}) => Txn(
  id: 0,
  type: TxnType.expense,
  amount: rupees * 100,
  date: date,
  category: category,
  fromAccountId: 1,
);

const sbi = Account(
  id: 1,
  name: 'SBI',
  kind: AccountKind.savings,
  openingBalance: 1000000,
);

void main() {
  group('budgets', () {
    test('status and alerts at 80% and over the limit', () {
      Ledger ledger(int spent) => Ledger(
        accounts: [sbi],
        budgets: const [Budget(category: 'Food', monthlyLimit: 500000)],
        txns: [expense(spent, d(2026, 10, 5)).copyWith(id: 1)],
      );
      final ok = ledger(1000);
      expect(ok.budgetStatuses(d(2026, 10, 30)).single.remaining, 400000);
      expect(ok.alerts(d(2026, 10, 30)), isEmpty);

      final near = ledger(4200).alerts(d(2026, 10, 30)).single;
      expect(near.kind, AlertKind.nearBudget);
      expect(near.category, 'Food');
      expect(near.message, contains('84%'));

      final over = ledger(5500).alerts(d(2026, 10, 30)).single;
      expect(over.kind, AlertKind.overBudget);
      expect(over.message, contains('₹500 over'));

      // A new month starts fresh.
      expect(ledger(5500).alerts(d(2026, 11, 1)), isEmpty);
    });
  });

  group('recurring', () {
    test('monthly keeps the day, clamped in short months', () {
      final r = Recurring(
        id: 1,
        template: expense(15000, d(2026, 1, 31), category: 'Rent'),
        frequency: Frequency.monthly,
        nextDate: d(2026, 1, 31),
      );
      expect(r.dueDates(d(2026, 4, 30)), [
        d(2026, 1, 31),
        d(2026, 2, 28),
        d(2026, 3, 31),
        d(2026, 4, 30),
      ]);
    });

    test('weekly and yearly', () {
      final w = Recurring(
        id: 1,
        template: expense(100, d(2026, 10, 1)),
        frequency: Frequency.weekly,
        nextDate: d(2026, 10, 1),
      );
      expect(w.dueDates(d(2026, 10, 20)).length, 3);
      final y = Recurring(
        id: 2,
        template: expense(100, d(2024, 2, 29)),
        frequency: Frequency.yearly,
        nextDate: d(2024, 2, 29),
      );
      expect(y.after(d(2024, 2, 29)), d(2025, 2, 28));
    });

    test('saving with repeat posts later copies once', () async {
      final store = FinanceStore.memory();
      await store.addAccount('SBI', AccountKind.savings, 10000000);
      final account = store.ledger.accounts.single.id;
      await store.saveTxn(
        Txn(
          id: 0,
          type: TxnType.expense,
          amount: 1500000,
          date: d(2026, 8, 5),
          category: 'Rent',
          fromAccountId: account,
        ),
        repeat: Frequency.monthly,
      );
      expect(store.ledger.recurring.single.nextDate, d(2026, 9, 5));
      expect(await store.postDueRecurring(d(2026, 10, 30)), 2);
      expect(await store.postDueRecurring(d(2026, 10, 30)), 0);
      final dates = store.ledger.txns.map((t) => t.date).toList();
      expect(dates, [d(2026, 10, 5), d(2026, 9, 5), d(2026, 8, 5)]);
      expect(store.ledger.txns.every((t) => t.recurringId != null), isTrue);
      expect(store.ledger.accountBalance(account), 10000000 - 3 * 1500000);
    });

    test('a rule whose account was removed is paused', () async {
      final store = FinanceStore.memory();
      await store.restoreBackup(
        jsonEncode({
          'app': 'rupeetrack',
          'recurring': [
            Recurring(
              id: 5,
              template: expense(10, d(2026, 1, 1)).copyWith(),
              frequency: Frequency.monthly,
              nextDate: d(2026, 2, 1),
            ).toJson(),
          ],
        }),
      );
      expect(await store.postDueRecurring(d(2026, 3, 1)), 0);
      expect(store.ledger.recurring.single.active, isFalse);
    });
  });

  group('backup', () {
    test('round trip keeps everything', () async {
      final a = FinanceStore.memory();
      await a.addAccount('SBI', AccountKind.savings, 100);
      await a.setBudget('Food', 500000);
      final b = FinanceStore.memory();
      await b.restoreBackup(a.backupJson());
      expect(jsonEncode(b.toJson()), jsonEncode(a.toJson()));
    });

    test('rejects other files and keeps current data', () async {
      final s = FinanceStore.memory();
      await s.addAccount('SBI', AccountKind.savings, 100);
      expect(() => s.restoreBackup('not json'), throwsFormatException);
      expect(() => s.restoreBackup('{"a":1}'), throwsFormatException);
      expect(s.ledger.accounts, hasLength(1));
    });
  });

  group('csv', () {
    test('parse handles quotes, commas and CRLF', () {
      expect(parseCsv('a,"b,c","d ""e"""\r\n1,2,3\n\n'), [
        ['a', 'b,c', 'd "e"'],
        ['1', '2', '3'],
      ]);
    });

    test('export round-trips through the parser', () {
      final l = Ledger(
        accounts: [sbi],
        txns: [
          withNote(
            expense(250, d(2026, 10, 3)).copyWith(id: 1),
            note: 'Lunch, with "team"',
          ),
        ],
      );
      final rows = parseCsv(exportTransactionsCsv(l));
      expect(rows.first.first, 'Date');
      expect(rows[1], [
        '2026-10-03',
        'Expense',
        '250.00',
        'Food',
        'Lunch, with "team"',
        'SBI',
        '',
        '',
      ]);
    });

    test('statement dates and amounts', () {
      expect(parseStatementDate('05/10/2026'), d(2026, 10, 5));
      expect(parseStatementDate('05-10-26'), d(2026, 10, 5));
      expect(parseStatementDate('2026-10-05'), d(2026, 10, 5));
      expect(parseStatementDate('05-Oct-2026'), d(2026, 10, 5));
      expect(parseStatementDate('5 Oct 26'), d(2026, 10, 5));
      expect(parseStatementDate('31/02/2026'), isNull);
      expect(parseStatementAmount('1,234.50'), 123450);
      expect(parseStatementAmount('250.00 Dr'), -25000);
      expect(parseStatementAmount('(99)'), -9900);
      expect(parseStatementAmount(''), isNull);
    });

    test('bank statement with Debit/Credit columns and a preamble', () {
      const csv = '''
Account Statement,SBI
Name,Test User

Txn Date,Value Date,Description,Ref No,Debit,Credit,Balance
01/10/2026,01/10/2026,SALARY OCT,,,"50,000.00","60,000.00"
03/10/2026,03/10/2026,UPI-SWIGGY-123,,250.00,,"59,750.00"
04/10/2026,04/10/2026,HPCL PETROL PUMP,,"1,000.00",,"58,750.00"
,,Closing balance,,,,"58,750.00"
''';
      final existing = Ledger(
        accounts: [sbi],
        txns: [expense(250, d(2026, 10, 3)).copyWith(id: 9)],
      );
      final r = importStatement(csv, accountId: 1, existing: existing);
      expect(r.duplicates, 1); // the Swiggy order is already in the app
      expect(r.skipped, 1); // closing balance line
      expect(r.txns, hasLength(2));
      final salary = r.txns.firstWhere((t) => t.type == TxnType.income);
      expect(salary.amount, 5000000);
      expect(salary.category, 'Salary');
      final fuel = r.txns.firstWhere((t) => t.type == TxnType.expense);
      expect(fuel.category, 'Fuel');
      expect(fuel.fromAccountId, 1);
    });

    test('card statement with one Amount column and Dr/Cr', () {
      const csv = '''
Date,Transaction Details,Amount,Dr/Cr
02/10/2026,AMAZON PAY,"2,499.00",Dr
10/10/2026,PAYMENT RECEIVED - THANK YOU,"5,000.00",Cr
12/10/2026,AMAZON REFUND,499.00,Cr
''';
      final r = importStatement(csv, cardId: 7, existing: Ledger());
      expect(r.skipped, 1); // the bill payment is recorded from the bank side
      expect(r.txns.map((t) => t.type), [TxnType.expense, TxnType.refund]);
      expect(r.txns.first.fromCardId, 7);
      expect(r.txns.first.category, 'Shopping');
      expect(r.txns.last.toCardId, 7);
    });

    test('file without recognisable headings', () {
      expect(
        () => importStatement('a,b\n1,2', accountId: 1, existing: Ledger()),
        throwsFormatException,
      );
    });
  });

  group('AMFI NAV', () {
    const sample = '''
Scheme Code;ISIN Div Payout/ ISIN Growth;ISIN Div Reinvestment;Scheme Name;Net Asset Value;Date

Open Ended Schemes(Equity Scheme - Large Cap Fund)

Example Mutual Fund

120503;INF0001;-;Example Nifty 50 Index Fund - Direct Plan - Growth;245.6789;29-Oct-2026
120504;INF0002;-;Example Bluechip Fund - Regular - IDCW;N.A.;29-Oct-2026
''';

    test('parses quotes and skips headings and N.A.', () {
      final navs = parseAmfiNavs(sample);
      expect(navs.keys, ['120503']);
      expect(navs['120503']!.nav, 245.6789);
      expect(navs['120503']!.date, d(2026, 10, 29));
      expect(searchSchemes(navs, 'nifty direct').single.code, '120503');
      expect(searchSchemes(navs, '120503').single.code, '120503');
    });

    test('linked fund value = units × NAV', () async {
      final store = FinanceStore.memory();
      final inv = await store.addInvestment('Index', InvestmentType.mutualFund);
      await store.linkScheme(inv, '120503', 100.5);
      expect(await store.applyNavs(parseAmfiNavs(sample)), 1);
      final updated = store.ledger.investments.single;
      expect(updated.currentValue, 2469073); // 100.5 × 245.6789 = 24,690.73
      expect(updated.valueUpdatedOn, d(2026, 10, 29));
      expect(updated.valueSource, contains('AMFI NAV'));
    });
  });

  group('reminders', () {
    test('card dues 7, 3 and 0 days before; recurring on its date', () {
      const card = CreditCard(
        id: 2,
        name: 'HDFC',
        lastFour: '',
        creditLimit: 10000000,
        statementDay: 15,
        dueDay: 5,
      );
      final l = Ledger(
        accounts: [sbi],
        cards: [card],
        txns: [
          Txn(
            id: 1,
            type: TxnType.expense,
            amount: 100000,
            date: d(2026, 10, 1),
            fromCardId: 2,
          ),
        ],
        recurring: [
          Recurring(
            id: 3,
            template: expense(15000, d(2026, 10, 7), category: 'Rent'),
            frequency: Frequency.monthly,
            nextDate: d(2026, 11, 7),
          ),
        ],
      );
      final plan = planReminders(
        l,
        DateTime(2026, 10, 25, 12),
        horizonDays: 20,
      );
      expect(plan.map((r) => r.when), [
        DateTime(2026, 10, 29, 9),
        DateTime(2026, 11, 2, 9),
        DateTime(2026, 11, 5, 9),
        DateTime(2026, 11, 7, 9),
      ]);
      expect(plan.first.title, 'HDFC bill due in 7 days');
      expect(plan[2].title, 'HDFC bill due today');
      expect(plan.last.title, contains('Rent'));
    });
  });

  group('edit, delete and statement view', () {
    test('editing the balance keeps entries and shifts the opening', () async {
      final store = FinanceStore.memory();
      final a = await store.addAccount('SBI', AccountKind.savings, 1000000);
      await store.saveTxn(
        expense(250, d(2026, 10, 3)).copyWith().withFrom(a.id),
      );
      expect(store.ledger.accountBalance(a.id), 975000);
      await store.updateAccount(
        store.ledger.account(a.id)!,
        name: 'SBI Salary',
        kind: AccountKind.savings,
        lastFour: '1234',
        currentBalance: 1200000,
      );
      final edited = store.ledger.account(a.id)!;
      expect(edited.name, 'SBI Salary');
      expect(edited.lastFour, '1234');
      expect(store.ledger.accountBalance(a.id), 1200000);
      expect(store.ledger.txns, hasLength(1));
    });

    test('deleting an account removes its entries and rules', () async {
      final store = FinanceStore.memory();
      final a = await store.addAccount('SBI', AccountKind.savings, 0);
      final b = await store.addAccount('Cash', AccountKind.cash, 0);
      await store.saveTxn(
        expense(100, d(2026, 10, 3)).withFrom(a.id),
        repeat: Frequency.monthly,
      );
      await store.saveTxn(expense(50, d(2026, 10, 4)).withFrom(b.id));
      expect(store.usageCount(accountId: a.id), 2); // entry + rule
      await store.deleteHolding(accountId: a.id);
      expect(store.ledger.accounts.map((x) => x.id), [b.id]);
      expect(store.ledger.txns.single.fromAccountId, b.id);
      expect(store.ledger.recurring, isEmpty);
    });

    test('running balance after each entry, like a bank statement', () {
      final l = Ledger(
        accounts: [sbi],
        txns: [
          expense(100, d(2026, 10, 1)).copyWith(id: 1),
          Txn(
            id: 2,
            type: TxnType.income,
            amount: 500000,
            date: d(2026, 10, 2),
            toAccountId: 1,
          ),
          expense(250, d(2026, 10, 2)).copyWith(id: 3),
        ],
      );
      expect(l.runningBalances(accountId: 1), {
        1: 990000,
        2: 1490000,
        3: 1465000,
      });
    });
  });

  group('investments added with an existing balance', () {
    test(
      'amount invested so far and current value give returns at once',
      () async {
        final store = FinanceStore.memory();
        final inv = await store.addInvestment(
          'PPF',
          InvestmentType.ppf,
          invested: 15000000, // ₹1,50,000 put in over the years
          value: 18000000, // worth ₹1,80,000 today
        );
        final s = store.ledger.investmentSummary(inv, DateTime.now());
        expect(s.contributed, 15000000);
        expect(s.currentValue, 18000000);
        expect(s.absoluteReturn, 3000000);
        expect(s.returnPercent, closeTo(20, 1e-9));
        // No bank account is touched by money invested before the app.
        expect(store.ledger.totalCash, 0);
        expect(store.ledger.netWorth(DateTime.now()).investments, 18000000);
      },
    );

    test('editing keeps both figures', () async {
      final store = FinanceStore.memory();
      final inv = await store.addInvestment('FD', InvestmentType.fixedDeposit);
      await store.updateInvestment(
        inv,
        'SBI FD',
        InvestmentType.fixedDeposit,
        invested: 5000000,
        value: 5200000,
      );
      final e = store.ledger.investments.single;
      expect(e.name, 'SBI FD');
      expect(e.openingInvested, 5000000);
      expect(e.currentValue, 5200000);
      final copy = FinanceStore.memory();
      await copy.restoreBackup(store.backupJson());
      expect(copy.ledger.investments.single.openingInvested, 5000000);
    });
  });

  group('reports', () {
    Ledger sample() => Ledger(
      accounts: [sbi],
      budgets: const [Budget(category: 'Food', monthlyLimit: 500000)],
      txns: [
        expense(250, d(2026, 10, 3)).copyWith(id: 1),
        withNote(
          expense(99, d(2026, 10, 4)).copyWith(id: 2),
          note: 'Tea & <snacks>',
        ),
      ],
    );

    test('Excel workbook has all sheets and escapes text', () {
      final bytes = buildExcelReport(sample(), d(2026, 10, 30));
      final zip = ZipDecoder().decodeBytes(bytes);
      final names = zip.files.map((f) => f.name).toSet();
      expect(
        names,
        containsAll([
          '[Content_Types].xml',
          'xl/workbook.xml',
          'xl/styles.xml',
          for (var i = 1; i <= 6; i++) 'xl/worksheets/sheet$i.xml',
        ]),
      );
      String text(String name) =>
          utf8.decode(zip.files.firstWhere((f) => f.name == name).content);
      expect(text('xl/workbook.xml'), contains('name="Transactions"'));
      final txns = text('xl/worksheets/sheet2.xml');
      expect(txns, contains('Tea &amp; &lt;snacks&gt;'));
      expect(txns, contains('<v>250.00</v>'));
      final out = Platform.environment['RT_XLSX_OUT'];
      if (out != null) File(out).writeAsBytesSync(bytes);
    });

    test('PDF report renders', () async {
      ByteData font(String f) =>
          ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync());
      final pdf = await buildPdfReport(
        sample(),
        d(2026, 10, 30),
        regular: font('Carlito-Regular.ttf'),
        bold: font('Carlito-Bold.ttf'),
      );
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      expect(pdf.length, greaterThan(5000));
      final out = Platform.environment['RT_PDF_OUT'];
      if (out != null) File(out).writeAsBytesSync(pdf);
    });
  });

  group('insights', () {
    Ledger withSpends(List<DateTime> days) => Ledger(
      accounts: [sbi],
      txns: [
        for (var i = 0; i < days.length; i++)
          expense(100, days[i]).copyWith(id: i + 1),
      ],
    );

    test('no-spend streak', () {
      final l = withSpends([d(2026, 10, 20), d(2026, 10, 25)]);
      // 26th..29th without spending; today (30th) not over yet but clean.
      expect(l.noSpendStreak(d(2026, 10, 30)), 4);
      // Spent today: the streak shown is the one that ended yesterday.
      final l2 = withSpends([d(2026, 10, 25), d(2026, 10, 30)]);
      expect(l2.noSpendStreak(d(2026, 10, 30)), 4);
      expect(withSpends([d(2026, 10, 29)]).noSpendStreak(d(2026, 10, 30)), 0);
      expect(Ledger().noSpendStreak(d(2026, 10, 30)), 0);
    });

    test('vs last month and daily average', () {
      final l = Ledger(
        accounts: [sbi],
        txns: [
          expense(1000, d(2026, 9, 5)).copyWith(id: 1),
          expense(5000, d(2026, 9, 20)).copyWith(id: 2), // after the 10th
          expense(800, d(2026, 10, 4)).copyWith(id: 3),
        ],
      );
      expect(l.spendingChangeVsLastMonth(d(2026, 10, 10)), closeTo(-20, 1e-9));
      expect(l.dailyAverage(d(2026, 10, 10)), 8000);
    });
  });
}

extension on Txn {
  Txn withFrom(int accountId) =>
      Txn.fromJson({...toJson(), 'fromAccount': accountId});
}

Txn withNote(Txn t, {String? note}) =>
    Txn.fromJson({...t.toJson(), 'note': ?note});
