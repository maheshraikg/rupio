import '../models/goals.dart';
import '../models/models.dart';
import '../models/money.dart';
import '../models/planning.dart';
import 'billing_cycle.dart';
import 'returns.dart';
import '../l10n/strings.dart';

/// Where a credit card stands on a given day.
class CardStatus {
  const CardStatus({
    required this.card,
    required this.outstanding,
    required this.cycleSpend,
    required this.lastStatementDate,
    required this.statementBalance,
    required this.amountDue,
    required this.dueDate,
    required this.overdue,
    this.minDue,
    this.fromBank = false,
  });

  final CreditCard card;

  /// Minimum amount due still unpaid, when the bank reported one.
  final Paise? minDue;

  /// True when the bill figures come from the bank (SMS, email or PDF)
  /// rather than being worked out from the entries in the app.
  final bool fromBank;

  /// Everything currently owed, including purchases after the statement.
  final Paise outstanding;

  /// Purchases since the last statement (they go on the next bill).
  final Paise cycleSpend;
  final DateTime lastStatementDate;

  /// What the last statement said was owed.
  final Paise statementBalance;

  /// Unpaid part of the bill that [dueDate] applies to.
  final Paise amountDue;
  final DateTime dueDate;
  final bool overdue;

  Paise get availableCredit {
    final available = card.creditLimit - outstanding;
    return available < 0 ? 0 : available;
  }

  double get utilisationPercent => card.creditLimit <= 0
      ? 0
      : (outstanding < 0 ? 0 : outstanding) * 100 / card.creditLimit;
}

class NetWorth {
  const NetWorth({
    required this.cash,
    required this.investments,
    required this.liabilities,
    required this.hasUnvaluedInvestments,
  });

  /// Money in accounts, cash and wallets.
  final Paise cash;

  /// Current value of investments (amount invested where no value has been
  /// entered yet; see [hasUnvaluedInvestments]).
  final Paise investments;

  /// Credit card outstanding.
  final Paise liabilities;
  final bool hasUnvaluedInvestments;

  Paise get total => cash + investments - liabilities;
}

enum AlertKind {
  overdue,
  dueSoon,
  overBudget,
  highUtilisation,
  nearBudget,
  emiDue,
}

/// Where a [Loan] stands on a given day.
class LoanStatus {
  const LoanStatus({
    required this.loan,
    required this.emisPaid,
    required this.amountPaid,
    required this.nextDue,
    required this.paidThisMonth,
  });

  final Loan loan;

  /// Instalments paid, including those paid before the loan was added.
  final int emisPaid;
  final Paise amountPaid;

  /// Date of the next unpaid instalment, or null once all are paid.
  final DateTime? nextDue;

  /// True when an EMI was recorded in the current month.
  final bool paidThisMonth;

  int get emisLeft {
    final left = loan.tenureMonths - emisPaid;
    return left < 0 ? 0 : left;
  }

  bool get finished => loan.closed || emisLeft == 0;

  /// What is still to be paid at the current EMI (interest included).
  Paise get remaining => finished ? 0 : emisLeft * loan.emi;

  double get progress => loan.tenureMonths <= 0
      ? 1
      : (emisPaid / loan.tenureMonths).clamp(0, 1).toDouble();
}

class FinanceAlert {
  const FinanceAlert(
    this.kind,
    this.message, {
    this.card,
    this.category,
    this.loan,
  });
  final AlertKind kind;
  final String message;

  /// The loan an EMI alert is about.
  final Loan? loan;

  /// The card a due-date or utilisation alert is about.
  final CreditCard? card;

  /// The category a budget alert is about.
  final String? category;
}

/// How a category is doing against its monthly [Budget].
class BudgetStatus {
  const BudgetStatus(this.budget, this.spent);
  final Budget budget;
  final Paise spent;

  Paise get remaining => budget.monthlyLimit - spent;
  double get percent =>
      budget.monthlyLimit <= 0 ? 0 : spent * 100 / budget.monthlyLimit;
}

/// Read-only view over all accounts, cards, investments and transactions that
/// derives every balance and report. Nothing here is stored, so editing or
/// deleting a transaction automatically fixes every number.
class Ledger {
  Ledger({
    this.accounts = const [],
    this.cards = const [],
    this.investments = const [],
    this.budgets = const [],
    this.recurring = const [],
    this.loans = const [],
    this.goals = const [],
    List<Txn> txns = const [],
  }) : txns = List.unmodifiable(
         [...txns]..sort((a, b) {
           final byDate = b.date.compareTo(a.date);
           return byDate != 0 ? byDate : b.id.compareTo(a.id);
         }),
       );

  final List<Account> accounts;
  final List<CreditCard> cards;
  final List<Investment> investments;
  final List<Budget> budgets;
  final List<Recurring> recurring;
  final List<Loan> loans;
  final List<SavingsGoal> goals;

  Loan? loan(int id) {
    for (final l in loans) {
      if (l.id == id) return l;
    }
    return null;
  }

  LoanStatus loanStatus(Loan loan, DateTime today) {
    final t = dateOnly(today);
    var count = loan.paidBefore;
    var paid = loan.paidBefore * loan.emi;
    var thisMonth = false;
    for (final x in txns) {
      if (x.loanId != loan.id) continue;
      count++;
      paid += x.amount;
      if (x.date.year == t.year && x.date.month == t.month) thisMonth = true;
    }
    final next = count >= loan.tenureMonths || loan.closed
        ? null
        : loan.emiDate(count);
    return LoanStatus(
      loan: loan,
      emisPaid: count,
      amountPaid: paid,
      nextDue: next,
      paidThisMonth: thisMonth,
    );
  }

  /// Total of the EMIs still running.
  Paise monthlyEmi(DateTime today) => loans
      .map((l) => loanStatus(l, today))
      .where((s) => !s.finished)
      .fold(0, (a, s) => a + s.loan.emi);

  /// What is left to pay on all running loans.
  Paise loansRemaining(DateTime today) =>
      loans.map((l) => loanStatus(l, today)).fold(0, (a, s) => a + s.remaining);

  Paise get goalsSaved => goals.fold(0, (a, g) => a + g.saved);

  /// What is still to be paid on running loans at the start of each month,
  /// from this month until the last EMI (the month after it is 0).
  List<(DateTime, Paise)> loanPayoff(DateTime today) {
    final t = dateOnly(today);
    final dates = <(DateTime, Paise)>[]; // every unpaid EMI
    for (final loan in loans) {
      final s = loanStatus(loan, t);
      if (s.finished) continue;
      for (var n = s.emisPaid; n < loan.tenureMonths; n++) {
        dates.add((loan.emiDate(n), loan.emi));
      }
    }
    if (dates.isEmpty) return const [];
    final last = dates.map((d) => d.$1).reduce((a, b) => a.isAfter(b) ? a : b);
    final result = <(DateTime, Paise)>[];
    var m = DateTime.utc(t.year, t.month);
    final end = DateTime.utc(last.year, last.month + 1);
    while (!m.isAfter(end)) {
      final left = dates
          .where((d) => !d.$1.isBefore(m))
          .fold(0, (a, d) => a + d.$2);
      // Overdue EMIs still count in the current month.
      final overdue = result.isEmpty
          ? dates.where((d) => d.$1.isBefore(m)).fold(0, (a, d) => a + d.$2)
          : 0;
      result.add((m, left + overdue));
      m = DateTime.utc(m.year, m.month + 1);
    }
    return result;
  }

  /// Month of the last EMI on running loans, or null.
  DateTime? debtFreeMonth(DateTime today) {
    final p = loanPayoff(today);
    return p.length < 2 ? null : p[p.length - 2].$1;
  }

  /// Newest first.
  final List<Txn> txns;

  Account? account(int? id) => _find(accounts, id, (a) => a.id);
  CreditCard? card(int? id) => _find(cards, id, (c) => c.id);
  Investment? investment(int? id) => _find(investments, id, (i) => i.id);

  static T? _find<T>(List<T> items, int? id, int Function(T) idOf) {
    if (id == null) return null;
    for (final item in items) {
      if (idOf(item) == id) return item;
    }
    return null;
  }

  Iterable<Txn> _upTo(DateTime? asOf) =>
      asOf == null ? txns : txns.where((t) => !t.date.isAfter(dateOnly(asOf)));

  Iterable<Txn> _between(DateTime from, DateTime to) {
    final f = dateOnly(from);
    final l = dateOnly(to);
    return txns.where((t) => !t.date.isBefore(f) && !t.date.isAfter(l));
  }

  // ---- Accounts -----------------------------------------------------------

  Paise accountBalance(int accountId, {DateTime? asOf}) {
    final a = account(accountId);
    var balance = a?.openingBalance ?? 0;
    final since = a?.since;
    for (final t in _upTo(asOf)) {
      if (_isHistory(t, since)) continue;
      if (t.fromAccountId == accountId) balance -= t.amount;
      if (t.toAccountId == accountId) balance += t.amount;
    }
    return balance;
  }

  /// Imported entries dated before an account's or card's opening balance
  /// are already part of that balance: shown in history, not counted again.
  /// Entries typed in by hand always count.
  static bool _isHistory(Txn t, DateTime? since) =>
      since != null && t.sourceKey != null && t.date.isBefore(since);

  Paise get totalCash =>
      accounts.fold(0, (sum, a) => sum + accountBalance(a.id));

  /// Balance of an account ([accountId]) or amount owed on a card
  /// ([cardId]) right after each of its entries, keyed by transaction id,
  /// like the balance column of a bank statement. History entries (see
  /// [Account.since]) have no balance.
  Map<int, Paise> runningBalances({int? accountId, int? cardId}) {
    final a = account(accountId);
    final c = card(cardId);
    var balance = a?.openingBalance ?? c?.openingOutstanding ?? 0;
    final since = a?.since ?? c?.since;
    final result = <int, Paise>{};
    for (final t in txns.reversed) {
      if (_isHistory(t, since)) continue;
      var delta = 0;
      if (accountId != null) {
        if (t.fromAccountId == accountId) delta -= t.amount;
        if (t.toAccountId == accountId) delta += t.amount;
      } else {
        if (t.fromCardId == cardId) delta += t.amount;
        if (t.toCardId == cardId) delta -= t.amount;
      }
      if (delta == 0) continue;
      balance += delta;
      result[t.id] = balance;
    }
    return result;
  }

  /// Transactions touching [accountId], newest first.
  List<Txn> accountTxns(int accountId) => txns
      .where((t) => t.fromAccountId == accountId || t.toAccountId == accountId)
      .toList();

  // ---- Credit cards -------------------------------------------------------

  Paise cardOutstanding(int cardId, {DateTime? asOf}) {
    final c = card(cardId);
    var owed = c?.openingOutstanding ?? 0;
    final since = c?.since;
    for (final t in _upTo(asOf)) {
      if (_isHistory(t, since)) continue;
      // A card purchase (expense or investment) adds to what is owed; a bill
      // payment or a refund to the card reduces it.
      if (t.fromCardId == cardId) owed += t.amount;
      if (t.toCardId == cardId) owed -= t.amount;
    }
    return owed;
  }

  Paise get totalCardOutstanding => cards.fold(0, (sum, c) {
    final owed = cardOutstanding(c.id);
    return sum + (owed > 0 ? owed : 0);
  });

  List<Txn> cardTxns(int cardId) => txns
      .where((t) => t.fromCardId == cardId || t.toCardId == cardId)
      .toList();

  CardStatus cardStatus(CreditCard c, DateTime today) {
    final t = dateOnly(today);
    final statement = BillingCycle.lastStatementDate(c, t);
    final owedAtStatement = cardOutstanding(c.id, asOf: statement);
    final statementBalance = owedAtStatement > 0 ? owedAtStatement : 0;

    var creditsSince = 0;
    var cycleSpend = 0;
    for (final x in txns) {
      if (!x.date.isAfter(statement) || x.date.isAfter(t)) continue;
      if (x.toCardId == c.id) creditsSince += x.amount;
      if (x.fromCardId == c.id) cycleSpend += x.amount;
    }
    final remaining = statementBalance - creditsSince;
    final amountDue = remaining > 0 ? remaining : 0;

    final statementDue = BillingCycle.dueDateFor(c, statement);
    final DateTime dueDate;
    final bool overdue;
    if (!statementDue.isBefore(t)) {
      dueDate = statementDue;
      overdue = false;
    } else if (amountDue > 0) {
      dueDate = statementDue;
      overdue = true;
    } else {
      // Last bill is settled; the next one has not been generated yet.
      dueDate = BillingCycle.dueDateFor(
        c,
        BillingCycle.nextStatementDate(c, statement),
      );
      overdue = false;
    }

    final fromBank = _bankBillStatus(c, t, cycleSpend);
    if (fromBank != null) return fromBank;

    return CardStatus(
      card: c,
      outstanding: cardOutstanding(c.id),
      cycleSpend: cycleSpend,
      lastStatementDate: statement,
      statementBalance: statementBalance,
      amountDue: amountDue,
      dueDate: dueDate,
      overdue: overdue,
    );
  }

  /// The bank's own bill for [c], while it is current: not yet due, or due
  /// within the last 60 days and still unpaid.
  CardStatus? _bankBillStatus(CreditCard c, DateTime t, Paise cycleSpend) {
    final bill = c.bill;
    if (bill == null) return null;
    final from =
        bill.statementDate ?? bill.dueDate.subtract(const Duration(days: 20));
    var paid = 0;
    for (final x in txns) {
      if (x.toCardId == c.id && x.date.isAfter(from) && !x.date.isAfter(t)) {
        paid += x.amount;
      }
    }
    final remaining = bill.totalDue - paid;
    final amountDue = remaining > 0 ? remaining : 0;
    final pastDue = bill.dueDate.isBefore(t);
    if (pastDue && (amountDue == 0 || t.difference(bill.dueDate).inDays > 60)) {
      return null;
    }
    final minLeft = bill.minDue == null ? null : bill.minDue! - paid;
    return CardStatus(
      card: c,
      outstanding: cardOutstanding(c.id),
      cycleSpend: cycleSpend,
      lastStatementDate: bill.statementDate ?? from,
      statementBalance: bill.totalDue,
      amountDue: amountDue,
      dueDate: bill.dueDate,
      overdue: pastDue && amountDue > 0,
      minDue: minLeft == null || minLeft <= 0 ? null : minLeft,
      fromBank: true,
    );
  }

  /// Due-date reminders ([reminderDays] before the due date), utilisation
  /// warnings (highest of [utilisationThresholds] crossed) and budgets that
  /// are over or past [nearBudgetPercent] this month. Most urgent first.
  List<FinanceAlert> alerts(
    DateTime today, {
    int reminderDays = 7,
    List<int> utilisationThresholds = const [30, 50, 75],
    double nearBudgetPercent = 80,
  }) {
    final t = dateOnly(today);
    final result = <FinanceAlert>[];
    for (final c in cards) {
      final s = cardStatus(c, t);
      final daysLeft = s.dueDate.difference(t).inDays;
      if (s.overdue) {
        result.add(
          FinanceAlert(
            AlertKind.overdue,
            card: c,
            tr('{0}: {1} was due {2} ago', [
              c.displayName,
              formatRupees(s.amountDue),
              _daysText(-daysLeft),
            ]),
          ),
        );
      } else if (s.amountDue > 0 && daysLeft <= reminderDays) {
        result.add(
          FinanceAlert(
            AlertKind.dueSoon,
            card: c,
            daysLeft == 0
                ? tr('{0}: {1} is due today', [
                    c.displayName,
                    formatRupees(s.amountDue),
                  ])
                : tr('{0}: {1} due in {2}', [
                    c.displayName,
                    formatRupees(s.amountDue),
                    _daysText(daysLeft),
                  ]),
          ),
        );
      }
      final crossed = [...utilisationThresholds]..sort();
      final hit = crossed.lastWhere(
        (p) => s.utilisationPercent >= p,
        orElse: () => -1,
      );
      if (hit >= 0) {
        result.add(
          FinanceAlert(
            AlertKind.highUtilisation,
            card: c,
            tr('{0}: {1}% of the limit used (over {2}%)', [
              c.displayName,
              s.utilisationPercent.toStringAsFixed(0),
              hit,
            ]),
          ),
        );
      }
    }
    for (final l in loans) {
      final st = loanStatus(l, t);
      final due = st.nextDue;
      if (due == null) continue;
      final days = due.difference(t).inDays;
      if (days <= 3) {
        result.add(
          FinanceAlert(
            AlertKind.emiDue,
            days < 0
                ? tr('{0}: EMI of {1} was due {2} ago', [
                    l.name,
                    formatRupees(l.emi),
                    _daysText(-days),
                  ])
                : days == 0
                ? tr('{0}: EMI of {1} is due today', [
                    l.name,
                    formatRupees(l.emi),
                  ])
                : tr('{0}: EMI of {1} due in {2}', [
                    l.name,
                    formatRupees(l.emi),
                    _daysText(days),
                  ]),
            loan: l,
          ),
        );
      }
    }
    for (final b in budgetStatuses(t)) {
      if (b.percent >= 100) {
        result.add(
          FinanceAlert(
            AlertKind.overBudget,
            category: b.budget.category,
            tr('{0}: {1} over the {2} budget', [
              tr(b.budget.category),
              formatRupees(-b.remaining),
              formatRupees(b.budget.monthlyLimit),
            ]),
          ),
        );
      } else if (b.percent >= nearBudgetPercent) {
        result.add(
          FinanceAlert(
            AlertKind.nearBudget,
            category: b.budget.category,
            tr('{0}: {1}% of the budget used, {2} left', [
              tr(b.budget.category),
              b.percent.toStringAsFixed(0),
              formatRupees(b.remaining),
            ]),
          ),
        );
      }
    }
    final order = AlertKind.values;
    result.sort(
      (a, b) => order.indexOf(a.kind).compareTo(order.indexOf(b.kind)),
    );
    return result;
  }

  static String _daysText(int days) =>
      days == 1 ? tr('1 day') : tr('{0} days', [days]);

  // ---- Spending & income --------------------------------------------------

  /// Expenses minus refunds between [from] and [to] (inclusive). Transfers,
  /// card bill payments and investments are never counted.
  Paise spending(DateTime from, DateTime to) =>
      spendingByCategory(from, to).values.fold(0, (a, b) => a + b);

  /// Spending per category, largest first.
  Map<String, Paise> spendingByCategory(DateTime from, DateTime to) {
    final totals = <String, Paise>{};
    for (final t in _between(from, to)) {
      final category = t.category ?? 'Other';
      if (t.type == TxnType.expense) {
        totals[category] = (totals[category] ?? 0) + t.amount;
      } else if (t.type == TxnType.refund) {
        totals[category] = (totals[category] ?? 0) - t.amount;
      }
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries);
  }

  Paise income(DateTime from, DateTime to) => _between(
    from,
    to,
  ).where((t) => t.type == TxnType.income).fold(0, (sum, t) => sum + t.amount);

  /// New money put into investments between [from] and [to].
  Paise invested(DateTime from, DateTime to) => _between(
    from,
    to,
  ).where((t) => t.type == TxnType.invest).fold(0, (sum, t) => sum + t.amount);

  /// Share of income not spent, as a percentage; null without income.
  double? savingsRate(DateTime from, DateTime to) {
    final earned = income(from, to);
    if (earned <= 0) return null;
    return (earned - spending(from, to)) * 100 / earned;
  }

  /// Spending against each budget in the month containing [day].
  List<BudgetStatus> budgetStatuses(DateTime day) {
    if (budgets.isEmpty) return const [];
    final spent = spendingByCategory(monthStart(day), monthEnd(day));
    return [for (final b in budgets) BudgetStatus(b, spent[b.category] ?? 0)];
  }

  // ---- Insights -----------------------------------------------------------

  /// Days in a row without any spending, ending yesterday. Today is left
  /// out: it is not over yet, so a streak is neither lost nor grown by it.
  int noSpendStreak(DateTime today) {
    final t = dateOnly(today);
    final spentDays = {
      for (final x in txns)
        if (x.type == TxnType.expense) x.date,
    };
    if (spentDays.isEmpty) return 0;
    final first = spentDays.reduce((a, b) => a.isBefore(b) ? a : b);
    var day = t.subtract(const Duration(days: 1));
    var n = 0;
    while (!day.isBefore(first) && !spentDays.contains(day)) {
      n++;
      day = day.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// Change in spending from the 1st to [today] versus the same days last
  /// month, as a percentage (−12 = 12% less). Null without last month data.
  double? spendingChangeVsLastMonth(DateTime today) {
    final t = dateOnly(today);
    final thisMonth = spending(monthStart(t), t);
    final lastStart = DateTime.utc(t.year, t.month - 1);
    final lastEnd = monthEnd(lastStart);
    final sameDay = DateTime.utc(
      lastStart.year,
      lastStart.month,
      t.day > lastEnd.day ? lastEnd.day : t.day,
    );
    final last = spending(lastStart, sameDay);
    if (last <= 0) return null;
    return (thisMonth - last) * 100 / last;
  }

  /// Running total of spending for each day of the month containing [day]
  /// (index 0 = the 1st), up to [upTo] when given.
  List<Paise> cumulativeSpending(DateTime day, {DateTime? upTo}) {
    final from = monthStart(day);
    final last = upTo != null ? dateOnly(upTo) : monthEnd(day);
    final perDay = List<Paise>.filled(last.day, 0);
    for (final t in _between(from, last)) {
      final i = t.date.day - 1;
      if (t.type == TxnType.expense) perDay[i] += t.amount;
      if (t.type == TxnType.refund) perDay[i] -= t.amount;
    }
    var run = 0;
    return [for (final v in perDay) run += v];
  }

  /// Average spending per day so far this month.
  Paise dailyAverage(DateTime today) {
    final t = dateOnly(today);
    return spending(monthStart(t), t) ~/ t.day;
  }

  // ---- Investments --------------------------------------------------------

  /// Units held in a NAV-linked fund: the units entered when it was linked
  /// plus units bought, minus units sold, by entries recorded since.
  double unitsHeld(Investment inv) {
    var units = inv.units ?? 0;
    for (final t in txns) {
      if (t.investmentId != inv.id || t.units == null) continue;
      if (t.type == TxnType.invest) units += t.units!;
      if (t.type == TxnType.investWithdrawal) units -= t.units!;
    }
    return units;
  }

  /// Current value: units × latest NAV for linked funds, otherwise the value
  /// the user entered (null if none yet).
  Paise? valueOf(Investment inv) {
    if (inv.isLinked && inv.lastNav != null) {
      return (unitsHeld(inv) * inv.lastNav! * 100).round();
    }
    return inv.currentValue;
  }

  InvestmentSummary investmentSummary(Investment inv, DateTime today) {
    var contributed = inv.openingInvested;
    var withdrawn = 0;
    var paidOut = 0;
    // Money put in before the holding was added counts from the date it was
    // invested; without that date no yearly return can be worked out.
    final openingDate = inv.openingDate;
    var datesKnown = inv.openingInvested <= 0 || openingDate != null;
    final flows = <CashFlow>[
      if (inv.openingInvested > 0 && openingDate != null)
        CashFlow(openingDate, -inv.openingInvested),
    ];
    DateTime? lastFlow;
    for (final t in txns.where((t) => t.investmentId == inv.id)) {
      switch (t.type) {
        case TxnType.invest:
          contributed += t.amount;
          flows.add(CashFlow(t.date, -t.amount));
        case TxnType.investWithdrawal:
          withdrawn += t.amount;
          flows.add(CashFlow(t.date, t.amount));
        case TxnType.investIncome when t.toAccountId != null:
          paidOut += t.amount;
          flows.add(CashFlow(t.date, t.amount));
        default:
          continue;
      }
      if (lastFlow == null || t.date.isAfter(lastFlow)) lastFlow = t.date;
    }
    final value = valueOf(inv);
    double? rate;
    var tooEarly = false;
    if (value != null && datesKnown && flows.isNotEmpty) {
      // Value it on its own date, but never before the last entry.
      var on = inv.valueUpdatedOn ?? dateOnly(today);
      if (lastFlow != null && lastFlow.isAfter(on)) on = lastFlow;
      final first = flows
          .map((f) => f.date)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      if (on.difference(first).inDays < 365) {
        tooEarly = true;
      } else {
        rate = xirr([...flows, CashFlow(on, value)]);
      }
    }
    return InvestmentSummary(
      investment: inv,
      contributed: contributed,
      withdrawn: withdrawn,
      incomePaidOut: paidOut,
      value: value,
      xirr: rate,
      xirrTooEarly: tooEarly,
    );
  }

  List<Txn> investmentTxns(int investmentId) =>
      txns.where((t) => t.investmentId == investmentId).toList();

  // ---- Net worth ----------------------------------------------------------

  NetWorth netWorth(DateTime today) {
    var investmentsValue = 0;
    var unvalued = false;
    for (final inv in investments) {
      final s = investmentSummary(inv, today);
      if (s.currentValue != null) {
        investmentsValue += s.currentValue!;
      } else {
        unvalued = unvalued || s.netInvested > 0;
        investmentsValue += s.netInvested > 0 ? s.netInvested : 0;
      }
    }
    return NetWorth(
      cash: totalCash,
      investments: investmentsValue,
      liabilities: totalCardOutstanding,
      hasUnvaluedInvestments: unvalued,
    );
  }
}

DateTime monthStart(DateTime d) => DateTime.utc(d.year, d.month);
DateTime monthEnd(DateTime d) => DateTime.utc(d.year, d.month + 1, 0);
