import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rupeetrack/app/scope.dart';
import 'package:rupeetrack/app/store.dart';
import 'package:rupeetrack/l10n/strings.dart';
import 'package:rupeetrack/main.dart';
import 'package:rupeetrack/models/models.dart';
import 'package:rupeetrack/screens/quick_add_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => clock = () => DateTime(2026, 10, 30));

  testWidgets('first open: feature tour, then welcome', (tester) async {
    final store = FinanceStore.memory();
    await tester.pumpWidget(RupeeTrackApp(store: store, background: false));
    expect(find.text('Skip'), findsOneWidget);
    // Swipe through two pages, then skip the rest.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(store.onboarded, isTrue);
    expect(
      find.textContaining('rupee goes.', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('quick add: amount, category, source, save', (tester) async {
    final store = FinanceStore.memory();
    await store.addAccount('SBI Savings', AccountKind.savings, 1000000);
    await tester.pumpWidget(RupeeTrackApp(store: store, background: false));
    expect(find.text('October'), findsOneWidget);
    expect(find.text('₹10,000'), findsNWidgets(2)); // net worth + accounts

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '250');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Food'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(store.ledger.txns, hasLength(1));
    final t = store.ledger.txns.single;
    expect(t.type, TxnType.expense);
    expect(t.amount, 25000);
    expect(t.category, 'Food');
    expect(t.fromAccountId, store.ledger.accounts.single.id);
    expect(store.ledger.accountBalance(t.fromAccountId!), 975000);
    expect(find.text('₹250'), findsWidgets); // spent this month (hero)
    expect(find.text('₹9,750'), findsNWidgets(2)); // net worth + accounts
    expect(store.lastCategory, 'Food');
  });

  testWidgets('an entry can be deleted from its edit screen, with undo', (
    tester,
  ) async {
    final store = FinanceStore.memory();
    await store.addAccount('SBI Savings', AccountKind.savings, 1000000);
    await tester.pumpWidget(RupeeTrackApp(store: store, background: false));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '250');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final t = store.ledger.txns.single;

    await tester.pumpWidget(
      AppScope(
        store: store,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showQuickAdd(context, initial: t),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this entry?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(store.ledger.txns, isEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.ledger.txns.single.id, t.id);
  });

  testWidgets('home shows the swipe hint once, and swiping deletes', (
    tester,
  ) async {
    final store = FinanceStore.memory();
    await store.addAccount('SBI Savings', AccountKind.savings, 1000000);
    await tester.pumpWidget(RupeeTrackApp(store: store, background: false));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '250');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Food'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(store.swipeHintSeen, isTrue);
    // The tip waits for the "saved" message to go away.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Tip: swipe an entry left to delete it'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    // The entries are at the bottom of Home.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    final row = find.byType(Dismissible).first;
    await tester.fling(row, const Offset(-500, 0), 2000);
    await tester.pumpAndSettle();
    expect(store.ledger.txns, isEmpty);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('quick add rejects an empty amount', (tester) async {
    final store = FinanceStore.memory();
    await store.addAccount('Cash', AccountKind.cash, 0);
    await tester.pumpWidget(RupeeTrackApp(store: store, background: false));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.textContaining('Enter a valid amount'), findsOneWidget);
    expect(store.ledger.txns, isEmpty);
  });

  testWidgets('all tabs render with data', (tester) async {
    final store = FinanceStore.memory();
    await store.addAccount('SBI', AccountKind.savings, 1000000);
    await store.addCard(
      name: 'HDFC',
      lastFour: '1234',
      creditLimit: 10000000,
      statementDay: 15,
      dueDay: 5,
      openingOutstanding: 500000,
    );
    final inv = await store.addInvestment(
      'Index fund',
      InvestmentType.mutualFund,
    );
    await store.saveTxn(
      Txn(
        id: 0,
        type: TxnType.invest,
        amount: 200000,
        date: DateTime.utc(2026, 10, 5),
        fromAccountId: store.ledger.accounts.single.id,
        investmentId: inv.id,
      ),
    );
    await tester.pumpWidget(RupeeTrackApp(store: store, background: false));
    for (final tab in ['Activity', 'Cards', 'More', 'Home']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    for (final range in ['1Y', 'All', '1M']) {
      await tester.tap(find.text(range));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cards').last);
    await tester.pumpAndSettle();
    expect(find.text('HDFC'), findsOneWidget);
    expect(find.text('•••• 1234'), findsOneWidget);
    expect(find.text('Pay bill'), findsOneWidget);
  });

  for (final lang in ['kn', 'hi', 'ml', 'ta', 'te']) {
    testWidgets('every screen renders in $lang', (tester) async {
      final store = FinanceStore.memory();
      await store.addAccount('SBI', AccountKind.savings, 1000000);
      await store.addCard(
        name: 'HDFC',
        lastFour: '1234',
        creditLimit: 10000000,
        statementDay: 15,
        dueDay: 5,
        openingOutstanding: 500000,
      );
      await store.saveTxn(
        Txn(
          id: 0,
          type: TxnType.expense,
          amount: 25000,
          date: DateTime.utc(2026, 10, 30),
          category: 'Food',
          fromAccountId: store.ledger.accounts.single.id,
        ),
      );
      await store.setLanguage(lang);
      await tester.pumpWidget(RupeeTrackApp(store: store, background: false));
      await tester.pumpAndSettle();
      expect(find.text(tr('Home')), findsOneWidget);
      expect(tr('Home'), isNot('Home'));
      for (final tab in ['Activity', 'Cards', 'More', 'Home']) {
        await tester.tap(find.text(tr(tab)).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      for (final range in ['1Y', tr('All'), '1M']) {
        await tester.tap(find.text(range));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await store.setLanguage('en');
    });
  }

  test('data survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await FinanceStore.load();
    await store.addAccount('SBI', AccountKind.savings, 1000000);
    await store.saveTxn(
      Txn(
        id: 0,
        type: TxnType.expense,
        amount: 25000,
        date: DateTime.utc(2026, 10, 30),
        category: 'Food',
        fromAccountId: store.ledger.accounts.single.id,
      ),
    );
    final reloaded = await FinanceStore.load();
    expect(reloaded.ledger.totalCash, 975000);
    expect(reloaded.lastCategory, 'Food');
    expect(jsonEncode(reloaded.toJson()), jsonEncode(store.toJson()));
  });
}
