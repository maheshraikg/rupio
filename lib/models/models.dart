import 'money.dart';
import '../l10n/strings.dart';

/// Strips the time from [d], as a UTC date so day arithmetic is DST-proof.
DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime parseIsoDate(String s) => dateOnly(DateTime.parse(s));

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.asNameMap()[name] ?? fallback;

enum AccountKind {
  savings('Savings account'),
  cash('Cash in hand'),
  wallet('UPI / wallet');

  const AccountKind(this.labelEn);

  /// English name (exports, reports).
  final String labelEn;

  /// Name in the interface language.
  String get label => tr(labelEn);
}

/// A bank account, cash in hand or wallet. Its balance is never stored: it is
/// always recalculated from [openingBalance] and the recorded transactions.
class Account {
  const Account({
    required this.id,
    required this.name,
    required this.kind,
    required this.openingBalance,
    this.lastFour = '',
    this.since,
  });

  final int id;
  final String name;
  final AccountKind kind;

  /// Balance on [since] (or before any transaction when [since] is null).
  final Paise openingBalance;

  /// Last digits of the account number, used to match bank SMS and emails.
  final String lastFour;

  /// Day the opening balance applies to. Older entries (e.g. imported
  /// history) appear in reports but do not change the balance.
  final DateTime? since;

  Account copyWith({
    String? name,
    AccountKind? kind,
    Paise? openingBalance,
    String? lastFour,
  }) => Account(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    openingBalance: openingBalance ?? this.openingBalance,
    lastFour: lastFour ?? this.lastFour,
    since: since,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'opening': openingBalance,
    if (lastFour.isNotEmpty) 'last4': lastFour,
    if (since != null) 'since': isoDate(since!),
  };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    id: j['id'] as int,
    name: j['name'] as String,
    kind: _enum(AccountKind.values, j['kind'], AccountKind.savings),
    openingBalance: j['opening'] as int,
    lastFour: (j['last4'] as String?) ?? '',
    since: j['since'] == null ? null : parseIsoDate(j['since'] as String),
  );
}

/// A bill as reported by the bank (statement SMS, email or PDF). When
/// present it is shown instead of the bill the app works out itself.
class BankBill {
  const BankBill({
    required this.totalDue,
    required this.dueDate,
    this.minDue,
    this.statementDate,
    required this.source,
  });

  final Paise totalDue;
  final Paise? minDue;
  final DateTime dueDate;
  final DateTime? statementDate;

  /// "SMS", "email" or "statement PDF".
  final String source;

  Map<String, Object?> toJson() => {
    'total': totalDue,
    if (minDue != null) 'min': minDue,
    'due': isoDate(dueDate),
    if (statementDate != null) 'stmt': isoDate(statementDate!),
    'source': source,
  };

  factory BankBill.fromJson(Map<String, dynamic> j) => BankBill(
    totalDue: j['total'] as int,
    minDue: j['min'] as int?,
    dueDate: parseIsoDate(j['due'] as String),
    statementDate: j['stmt'] == null ? null : parseIsoDate(j['stmt'] as String),
    source: (j['source'] as String?) ?? 'SMS',
  );
}

/// A credit card. [statementDay] and [dueDay] are days of the month (1-31);
/// a day past the end of a short month means its last day.
class CreditCard {
  const CreditCard({
    required this.id,
    required this.name,
    required this.lastFour,
    required this.creditLimit,
    required this.statementDay,
    required this.dueDay,
    this.openingOutstanding = 0,
    this.since,
    this.bill,
  }) : assert(statementDay >= 1 && statementDay <= 31),
       assert(dueDay >= 1 && dueDay <= 31);

  final int id;
  final String name;
  final String lastFour;
  final Paise creditLimit;
  final int statementDay;
  final int dueDay;

  /// Amount owed on [since] (or before any transaction when null).
  final Paise openingOutstanding;

  /// Day [openingOutstanding] applies to; older entries are history only.
  final DateTime? since;

  /// Latest bill reported by the bank, if any.
  final BankBill? bill;

  String get displayName => lastFour.isEmpty ? name : '$name ••$lastFour';

  CreditCard copyWith({
    String? name,
    String? lastFour,
    BankBill? bill,
    int? statementDay,
    int? dueDay,
    Paise? creditLimit,
    Paise? openingOutstanding,
  }) => CreditCard(
    id: id,
    name: name ?? this.name,
    lastFour: lastFour ?? this.lastFour,
    creditLimit: creditLimit ?? this.creditLimit,
    statementDay: statementDay ?? this.statementDay,
    dueDay: dueDay ?? this.dueDay,
    openingOutstanding: openingOutstanding ?? this.openingOutstanding,
    since: since,
    bill: bill ?? this.bill,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'last4': lastFour,
    'limit': creditLimit,
    'statementDay': statementDay,
    'dueDay': dueDay,
    'opening': openingOutstanding,
    if (since != null) 'since': isoDate(since!),
    if (bill != null) 'bill': bill!.toJson(),
  };

  factory CreditCard.fromJson(Map<String, dynamic> j) => CreditCard(
    id: j['id'] as int,
    name: j['name'] as String,
    lastFour: (j['last4'] as String?) ?? '',
    creditLimit: j['limit'] as int,
    statementDay: j['statementDay'] as int,
    dueDay: j['dueDay'] as int,
    openingOutstanding: (j['opening'] as int?) ?? 0,
    since: j['since'] == null ? null : parseIsoDate(j['since'] as String),
    bill: j['bill'] == null
        ? null
        : BankBill.fromJson(j['bill'] as Map<String, dynamic>),
  );
}

enum InvestmentType {
  mutualFund('Mutual fund / SIP'),
  stock('Stocks'),
  ppf('PPF'),
  nsc('NSC'),
  fixedDeposit('Fixed deposit'),
  recurringDeposit('Recurring deposit'),
  postOffice('Post Office scheme'),
  nps('NPS'),
  gold('Gold / SGB'),
  other('Other');

  const InvestmentType(this.labelEn);

  /// English name (exports, reports).
  final String labelEn;

  /// Name in the interface language.
  String get label => tr(labelEn);
}

/// An investment holding. [currentValue] is either entered by the user or,
/// for a mutual fund linked to an AMFI [schemeCode], units × the latest NAV.
/// Null means it has not been valued yet, so returns are not shown rather
/// than guessed.
class Investment {
  const Investment({
    required this.id,
    required this.name,
    required this.type,
    this.currentValue,
    this.valueUpdatedOn,
    this.valueSource,
    this.schemeCode,
    this.units,
    this.openingInvested = 0,
    this.since,
    this.openingDate,
    this.lastNav,
  });

  final int id;
  final String name;
  final InvestmentType type;
  final Paise? currentValue;
  final DateTime? valueUpdatedOn;

  /// Where [currentValue] came from, e.g. "AMFI NAV ₹123.45"; null when the
  /// user typed it.
  final String? valueSource;

  /// AMFI scheme code for automatic NAV updates (mutual funds only).
  final String? schemeCode;

  /// Units held, used with [schemeCode].
  final double? units;

  /// Money already put in before the holding was added to the app (e.g.
  /// years of PPF deposits), so returns are right without entering each one.
  final Paise openingInvested;

  /// Day the holding was added to the app.
  final DateTime? since;

  /// When the money in [openingInvested] was invested (the start of the
  /// investment). Yearly return (XIRR) counts from this date.
  final DateTime? openingDate;

  /// Latest NAV per unit for a linked fund (from AMFI).
  final double? lastNav;

  bool get isLinked => schemeCode != null && units != null;

  Investment withValue(
    Paise value,
    DateTime on, {
    String? source,
    double? nav,
  }) => Investment(
    id: id,
    name: name,
    type: type,
    currentValue: value,
    valueUpdatedOn: dateOnly(on),
    valueSource: source,
    schemeCode: schemeCode,
    units: units,
    openingInvested: openingInvested,
    since: since,
    openingDate: openingDate,
    lastNav: nav ?? lastNav,
  );

  Investment renamed(
    String newName,
    InvestmentType newType, {
    Paise? openingInvested,
    DateTime? openingDate,
  }) => Investment(
    id: id,
    name: newName,
    type: newType,
    currentValue: currentValue,
    valueUpdatedOn: valueUpdatedOn,
    valueSource: valueSource,
    schemeCode: schemeCode,
    units: units,
    openingInvested: openingInvested ?? this.openingInvested,
    since: since,
  );

  /// Links (or with nulls, unlinks) this holding to an AMFI scheme.
  Investment withScheme(String? code, double? heldUnits) => Investment(
    id: id,
    name: name,
    type: type,
    currentValue: currentValue,
    valueUpdatedOn: valueUpdatedOn,
    valueSource: valueSource,
    schemeCode: code,
    units: heldUnits,
    openingInvested: openingInvested,
    since: since,
    openingDate: openingDate,
    lastNav: lastNav,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'value': currentValue,
    'valuedOn': valueUpdatedOn == null ? null : isoDate(valueUpdatedOn!),
    if (valueSource != null) 'valueSource': valueSource,
    if (schemeCode != null) 'scheme': schemeCode,
    if (units != null) 'units': units,
    if (openingInvested != 0) 'openingInvested': openingInvested,
    if (since != null) 'since': isoDate(since!),
    if (openingDate != null) 'openingDate': isoDate(openingDate!),
    if (lastNav != null) 'nav': lastNav,
  };

  factory Investment.fromJson(Map<String, dynamic> j) => Investment(
    id: j['id'] as int,
    name: j['name'] as String,
    type: _enum(InvestmentType.values, j['type'], InvestmentType.other),
    currentValue: j['value'] as int?,
    valueUpdatedOn: j['valuedOn'] == null
        ? null
        : parseIsoDate(j['valuedOn'] as String),
    valueSource: j['valueSource'] as String?,
    schemeCode: j['scheme'] as String?,
    units: (j['units'] as num?)?.toDouble(),
    openingInvested: (j['openingInvested'] as int?) ?? 0,
    since: j['since'] == null ? null : parseIsoDate(j['since'] as String),
    openingDate: j['openingDate'] == null
        ? null
        : parseIsoDate(j['openingDate'] as String),
    lastNav: (j['nav'] as num?)?.toDouble(),
  );
}

enum TxnType {
  /// Spending from an account or a credit card.
  expense('Expense'),

  /// Money received into an account (salary, bank interest, ...).
  income('Income'),

  /// Money moved between two of the user's own accounts. Not income or
  /// expense.
  transfer('Transfer'),

  /// Paying a credit card bill from an account: debt repayment, not a second
  /// expense.
  cardPayment('Card bill'),

  /// Money returned against an earlier expense, to an account or a card.
  refund('Refund'),

  /// Contribution to an investment from an account or a card. Never counted
  /// as spending.
  invest('Invest'),

  /// Redemption / withdrawal from an investment into an account.
  investWithdrawal('Withdraw'),

  /// Dividend or interest from an investment. Paid out to an account when
  /// [Txn.toAccountId] is set, otherwise reinvested (already in the value).
  investIncome('Dividend / interest');

  const TxnType(this.labelEn);

  /// English name (exports, reports).
  final String labelEn;

  /// Name in the interface language.
  String get label => tr(labelEn);
}

/// One ledger entry. Which of the from/to fields are used depends on [type];
/// see [validate].
class Txn {
  const Txn({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    this.category,
    this.note,
    this.fromAccountId,
    this.fromCardId,
    this.toAccountId,
    this.toCardId,
    this.investmentId,
    this.receiptPath,
    this.recurringId,
    this.sourceKey,
    this.loanId,
    this.units,
  });

  final int id;
  final TxnType type;
  final Paise amount;
  final DateTime date;
  final String? category;
  final String? note;
  final int? fromAccountId;
  final int? fromCardId;
  final int? toAccountId;
  final int? toCardId;
  final int? investmentId;

  /// Photo of the receipt, stored in the app's documents folder.
  final String? receiptPath;

  /// The [Recurring] rule that created this entry, if any.
  final int? recurringId;

  /// Set on entries read from an SMS, email or statement ("sms:…"), so the
  /// same message is never imported twice.
  final String? sourceKey;

  /// The [Loan] this entry pays an EMI on.
  final int? loanId;

  /// Mutual fund units bought (invest) or sold (withdraw) by this entry,
  /// for NAV-linked funds.
  final double? units;

  /// Where an automatically detected entry came from, for display.
  String? get sourceLabel => switch (sourceKey?.split(':').first) {
    'sms' => tr('SMS'),
    'mail' => tr('Email'),
    'pdf' => tr('Statement'),
    _ => null,
  };

  Txn copyWith({int? id, DateTime? date, int? recurringId, double? units}) =>
      Txn(
        id: id ?? this.id,
        type: type,
        amount: amount,
        date: date ?? this.date,
        category: category,
        note: note,
        fromAccountId: fromAccountId,
        fromCardId: fromCardId,
        toAccountId: toAccountId,
        toCardId: toCardId,
        investmentId: investmentId,
        receiptPath: receiptPath,
        recurringId: recurringId ?? this.recurringId,
        sourceKey: sourceKey,
        loanId: loanId,
        units: units ?? this.units,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'amount': amount,
    'date': isoDate(date),
    if (category != null) 'category': category,
    if (note != null) 'note': note,
    if (fromAccountId != null) 'fromAccount': fromAccountId,
    if (fromCardId != null) 'fromCard': fromCardId,
    if (toAccountId != null) 'toAccount': toAccountId,
    if (toCardId != null) 'toCard': toCardId,
    if (investmentId != null) 'investment': investmentId,
    if (receiptPath != null) 'receipt': receiptPath,
    if (recurringId != null) 'recurring': recurringId,
    if (sourceKey != null) 'src': sourceKey,
    if (loanId != null) 'loan': loanId,
    if (units != null) 'units': units,
  };

  factory Txn.fromJson(Map<String, dynamic> j) => Txn(
    id: j['id'] as int,
    type: _enum(TxnType.values, j['type'], TxnType.expense),
    amount: j['amount'] as int,
    date: parseIsoDate(j['date'] as String),
    category: j['category'] as String?,
    note: j['note'] as String?,
    fromAccountId: j['fromAccount'] as int?,
    fromCardId: j['fromCard'] as int?,
    toAccountId: j['toAccount'] as int?,
    toCardId: j['toCard'] as int?,
    investmentId: j['investment'] as int?,
    receiptPath: j['receipt'] as String?,
    recurringId: j['recurring'] as int?,
    sourceKey: j['src'] as String?,
    loanId: j['loan'] as int?,
    units: (j['units'] as num?)?.toDouble(),
  );
}

/// Problems that stop [t] from being saved; empty when it is valid.
List<String> validate(Txn t) {
  final errors = <String>[];
  if (t.amount <= 0) errors.add(tr('Enter an amount greater than zero'));
  final oneSource = (t.fromAccountId != null) != (t.fromCardId != null);
  switch (t.type) {
    case TxnType.expense:
      if (!oneSource) {
        errors.add(tr('Choose the account or card you paid from'));
      }
    case TxnType.invest:
      if (!oneSource) {
        errors.add(tr('Choose the account or card you paid from'));
      }
      if (t.investmentId == null) errors.add(tr('Choose an investment'));
    case TxnType.income:
      if (t.toAccountId == null) {
        errors.add(tr('Choose the account that received the money'));
      }
    case TxnType.transfer:
      if (t.fromAccountId == null || t.toAccountId == null) {
        errors.add(tr('Choose both accounts'));
      } else if (t.fromAccountId == t.toAccountId) {
        errors.add(tr('Choose two different accounts'));
      }
    case TxnType.cardPayment:
      // The paying account is optional: a payment detected from the card's
      // SMS may have come from an account that is not tracked here.
      if (t.toCardId == null) errors.add(tr('Choose the card that was paid'));
    case TxnType.refund:
      if ((t.toAccountId != null) == (t.toCardId != null)) {
        errors.add(tr('Choose the account or card that got the refund'));
      }
    case TxnType.investWithdrawal:
      if (t.investmentId == null) errors.add(tr('Choose an investment'));
      if (t.toAccountId == null) {
        errors.add(tr('Choose the account that received the money'));
      }
    case TxnType.investIncome:
      if (t.investmentId == null) errors.add(tr('Choose an investment'));
  }
  return errors;
}

/// Built-in spending categories; users can type their own as well.
const expenseCategories = [
  'Food',
  'Groceries',
  'Transport',
  'Fuel',
  'Shopping',
  'Bills',
  'Rent',
  'Health',
  'Entertainment',
  'Travel',
  'Education',
  'EMI',
  'Other',
];

const incomeCategories = ['Salary', 'Interest', 'Business', 'Gift', 'Other'];
