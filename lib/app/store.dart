import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';
import '../ledger/ledger.dart';
import '../models/goals.dart';
import '../models/models.dart';
import '../data/amfi.dart';
import '../models/money.dart';
import '../models/planning.dart';
import '../sync/sync.dart';

/// Where the quick-add form takes money from: an account or a card.
class Source {
  const Source.account(int id) : accountId = id, cardId = null;
  const Source.card(int id) : cardId = id, accountId = null;

  final int? accountId;
  final int? cardId;

  String get key => accountId != null ? 'a$accountId' : 'c$cardId';

  static Source? parse(String? key) {
    if (key == null || key.length < 2) return null;
    final id = int.tryParse(key.substring(1));
    if (id == null) return null;
    return switch (key[0]) {
      'a' => Source.account(id),
      'c' => Source.card(id),
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is Source && other.accountId == accountId && other.cardId == cardId;

  @override
  int get hashCode => Object.hash(accountId, cardId);
}

/// All of the user's data, persisted as JSON in shared_preferences. Every
/// change rebuilds [ledger], from which all balances and reports are derived.
class FinanceStore extends ChangeNotifier {
  FinanceStore._(this._prefs);

  final SharedPreferences? _prefs;

  /// In-memory store (tests, previews).
  FinanceStore.memory() : _prefs = null {
    setCurrentLanguage(language);
  }

  static const _dataKey = 'rupeetrack.data.v1';

  static Future<FinanceStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return FinanceStore._(prefs).._read();
  }

  final List<Account> _accounts = [];
  final List<CreditCard> _cards = [];
  final List<Investment> _investments = [];
  final List<Txn> _txns = [];
  final List<Budget> _budgets = [];
  final List<Recurring> _recurring = [];
  final List<Loan> _loans = [];
  final List<SavingsGoal> _goals = [];
  int _nextId = 1;

  /// Interface language code ('en', 'hi', 'kn', …).
  String language = 'en';

  /// The first-run feature tour has been seen (or skipped).
  bool onboarded = false;

  /// The swipe-left-to-delete hint has been shown once.
  bool swipeHintSeen = false;

  /// Black theme by default.
  ThemeMode themeMode = ThemeMode.dark;

  /// Card due-date and recurring-entry reminders.
  bool notifications = true;

  /// Daily "add today's expenses" nudge, as minutes after midnight; null
  /// when off.
  int? dailyReminder;

  /// Read bank SMS to detect transactions (Android permission also needed).
  bool smsSync = false;
  DateTime? lastSync;

  /// Imported entries the user deleted; never imported again.
  final Set<String> _ignoredKeys = {};
  Set<String> get ignoredKeys => Set.unmodifiable(_ignoredKeys);

  /// Cards and accounts found in messages that are not in the app yet, and
  /// the latest bank balance per account, from the last sync.
  Map<String, DetectedHolding> detected = const {};
  Map<int, BalanceHint> balanceHints = const {};

  /// Remembered so that the next quick entry is one tap shorter.
  String lastCategory = expenseCategories.first;
  Source? lastSource;

  Ledger _ledger = Ledger();
  Ledger get ledger => _ledger;

  bool get isEmpty => _accounts.isEmpty && _cards.isEmpty;

  void _read() {
    final raw = _prefs!.getString(_dataKey);
    if (raw == null) {
      // First start: use the phone's language when the app has it.
      final phone = ui.PlatformDispatcher.instance.locale.languageCode;
      language = availableLanguages.any((l) => l.code == phone) ? phone : 'en';
      setCurrentLanguage(language);
      return;
    }
    try {
      _loadJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Rupio: could not read saved data: $e');
    }
    _rebuild();
  }

  void _loadJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) =>
        ((j[key] as List?) ?? const [])
            .map((e) => f(e as Map<String, dynamic>))
            .toList();
    // Parse everything first so that a bad file leaves the data untouched.
    final accounts = list('accounts', Account.fromJson);
    final cards = list('cards', CreditCard.fromJson);
    final investments = list('investments', Investment.fromJson);
    final txns = list('txns', Txn.fromJson);
    final budgets = list('budgets', Budget.fromJson);
    final recurring = list('recurring', Recurring.fromJson);
    final loans = list('loans', Loan.fromJson);
    final goals = list('goals', SavingsGoal.fromJson);
    _accounts
      ..clear()
      ..addAll(accounts);
    _cards
      ..clear()
      ..addAll(cards);
    _investments
      ..clear()
      ..addAll(investments);
    _txns
      ..clear()
      ..addAll(txns);
    _budgets
      ..clear()
      ..addAll(budgets);
    _recurring
      ..clear()
      ..addAll(recurring);
    _loans
      ..clear()
      ..addAll(loans);
    _goals
      ..clear()
      ..addAll(goals);
    language = (j['language'] as String?) ?? language;
    // People who already use the app never see the tour.
    onboarded =
        (j['onboarded'] as bool?) ?? (accounts.isNotEmpty || cards.isNotEmpty);
    swipeHintSeen = (j['swipeHintSeen'] as bool?) ?? false;
    setCurrentLanguage(language);
    _nextId = (j['nextId'] as int?) ?? 1;
    // Before v2 the theme was never chosen explicitly ('system' was the
    // default); move those users to the black theme once.
    final theme = j['themeV2'] == true
        ? j['theme']
        : (j['theme'] == 'light' ? 'light' : 'dark');
    themeMode = ThemeMode.values.asNameMap()[theme] ?? ThemeMode.dark;
    notifications = (j['notifications'] as bool?) ?? true;
    dailyReminder = j['dailyReminder'] as int?;
    smsSync = (j['smsSync'] as bool?) ?? false;
    lastSync = j['lastSync'] == null
        ? null
        : DateTime.tryParse(j['lastSync'] as String);
    _ignoredKeys
      ..clear()
      ..addAll(((j['ignored'] as List?) ?? const []).cast<String>());
    lastCategory = (j['lastCategory'] as String?) ?? expenseCategories.first;
    lastSource = Source.parse(j['lastSource'] as String?);
  }

  Map<String, Object?> toJson() => {
    'accounts': _accounts.map((e) => e.toJson()).toList(),
    'cards': _cards.map((e) => e.toJson()).toList(),
    'investments': _investments.map((e) => e.toJson()).toList(),
    'txns': _txns.map((e) => e.toJson()).toList(),
    'budgets': _budgets.map((e) => e.toJson()).toList(),
    'recurring': _recurring.map((e) => e.toJson()).toList(),
    'loans': _loans.map((e) => e.toJson()).toList(),
    'goals': _goals.map((e) => e.toJson()).toList(),
    'language': language,
    'onboarded': onboarded,
    if (swipeHintSeen) 'swipeHintSeen': true,
    'nextId': _nextId,
    'theme': themeMode.name,
    'themeV2': true,
    'notifications': notifications,
    if (dailyReminder != null) 'dailyReminder': dailyReminder,
    'smsSync': smsSync,
    if (lastSync != null) 'lastSync': lastSync!.toIso8601String(),
    'ignored': _ignoredKeys.toList(),
    'lastCategory': lastCategory,
    'lastSource': lastSource?.key,
  };

  void _rebuild() {
    _ledger = Ledger(
      accounts: List.unmodifiable(_accounts),
      cards: List.unmodifiable(_cards),
      investments: List.unmodifiable(_investments),
      budgets: List.unmodifiable(_budgets),
      recurring: List.unmodifiable(_recurring),
      loans: List.unmodifiable(_loans),
      goals: List.unmodifiable(_goals),
      txns: _txns,
    );
  }

  Future<void> _save() async {
    _rebuild();
    notifyListeners();
    await _prefs?.setString(_dataKey, jsonEncode(toJson()));
  }

  int _newId() => _nextId++;

  static void _upsert<T>(List<T> items, T item, int Function(T) idOf) {
    final i = items.indexWhere((e) => idOf(e) == idOf(item));
    if (i >= 0) {
      items[i] = item;
    } else {
      items.add(item);
    }
  }

  // ---- Accounts, cards, investments --------------------------------------

  Future<Account> addAccount(
    String name,
    AccountKind kind,
    int openingBalance, {
    String lastFour = '',
  }) async {
    final a = Account(
      id: _newId(),
      name: name,
      kind: kind,
      openingBalance: openingBalance,
      lastFour: lastFour,
      since: dateOnly(DateTime.now()),
    );
    _accounts.add(a);
    await _save();
    return a;
  }

  Future<CreditCard> addCard({
    required String name,
    required String lastFour,
    required int creditLimit,
    required int statementDay,
    required int dueDay,
    int openingOutstanding = 0,
  }) async {
    final c = CreditCard(
      id: _newId(),
      name: name,
      lastFour: lastFour,
      creditLimit: creditLimit,
      statementDay: statementDay,
      dueDay: dueDay,
      openingOutstanding: openingOutstanding,
      since: dateOnly(DateTime.now()),
    );
    _cards.add(c);
    await _save();
    return c;
  }

  /// [invested] is money already put in before adding it here; [value] is
  /// what it is worth today. Both are optional.
  Future<Investment> addInvestment(
    String name,
    InvestmentType type, {
    Paise invested = 0,
    Paise? value,
    DateTime? investedOn,
  }) async {
    final now = dateOnly(DateTime.now());
    var inv = Investment(
      id: _newId(),
      name: name,
      type: type,
      openingInvested: invested,
      since: now,
      openingDate: investedOn == null ? null : dateOnly(investedOn),
    );
    if (value != null) inv = inv.withValue(value, now);
    _investments.add(inv);
    await _save();
    return inv;
  }

  Future<void> updateInvestmentValue(Investment inv, int value, DateTime on) {
    _upsert(_investments, inv.withValue(value, on), (e) => e.id);
    return _save();
  }

  bool isInUse({int? accountId, int? cardId, int? investmentId}) =>
      [..._txns, for (final r in _recurring) r.template].any(
        (t) =>
            (accountId != null &&
                (t.fromAccountId == accountId || t.toAccountId == accountId)) ||
            (cardId != null &&
                (t.fromCardId == cardId || t.toCardId == cardId)) ||
            (investmentId != null && t.investmentId == investmentId),
      );

  /// Links a mutual fund to an AMFI scheme and the units held; null code
  /// unlinks it.
  Future<void> linkScheme(Investment inv, String? code, double? units) {
    _upsert(_investments, inv.withScheme(code, units), (e) => e.id);
    return _save();
  }

  /// Revalues every linked fund from [navs] (scheme code -> quote). Returns
  /// how many holdings were updated.
  Future<int> applyNavs(Map<String, NavQuote> navs) async {
    var updated = 0;
    for (final inv in [..._investments]) {
      final quote = navs[inv.schemeCode];
      if (!inv.isLinked || quote == null) continue;
      final value = (_ledger.unitsHeld(inv) * quote.nav * 100).round();
      _upsert(
        _investments,
        inv.withValue(
          value,
          quote.date,
          source: 'AMFI NAV ${formatRupees((quote.nav * 100).round())}',
          nav: quote.nav,
        ),
        (e) => e.id,
      );
      updated++;
    }
    if (updated > 0) await _save();
    return updated;
  }

  /// Edits an account. [currentBalance] is today's balance as the user sees
  /// it; the opening balance is shifted so that the transactions add up to it.
  Future<void> updateAccount(
    Account a, {
    required String name,
    required AccountKind kind,
    required String lastFour,
    required Paise currentBalance,
  }) {
    final shift = currentBalance - ledger.accountBalance(a.id);
    _upsert(
      _accounts,
      a.copyWith(
        name: name,
        kind: kind,
        lastFour: lastFour,
        openingBalance: a.openingBalance + shift,
      ),
      (e) => e.id,
    );
    return _save();
  }

  /// Edits a card; [currentOutstanding] works like the account balance.
  Future<void> updateCard(
    CreditCard c, {
    required String name,
    required String lastFour,
    required Paise creditLimit,
    required int statementDay,
    required int dueDay,
    required Paise currentOutstanding,
  }) {
    final shift = currentOutstanding - ledger.cardOutstanding(c.id);
    _upsert(
      _cards,
      c.copyWith(
        name: name,
        lastFour: lastFour,
        creditLimit: creditLimit,
        statementDay: statementDay,
        dueDay: dueDay,
        openingOutstanding: c.openingOutstanding + shift,
      ),
      (e) => e.id,
    );
    return _save();
  }

  /// Edits an investment. A changed [value] becomes today's value.
  Future<void> updateInvestment(
    Investment inv,
    String name,
    InvestmentType type, {
    Paise? invested,
    Paise? value,
    DateTime? investedOn,
  }) {
    var updated = inv.renamed(
      name,
      type,
      openingInvested: invested,
      openingDate: investedOn,
    );
    if (value != null && value != inv.currentValue) {
      updated = updated.withValue(value, DateTime.now());
    }
    _upsert(_investments, updated, (e) => e.id);
    return _save();
  }

  /// Number of transactions and recurring rules that use the holding.
  int usageCount({int? accountId, int? cardId, int? investmentId}) =>
      [..._txns, for (final r in _recurring) r.template]
          .where(
            (t) => _touches(
              t,
              accountId: accountId,
              cardId: cardId,
              investmentId: investmentId,
            ),
          )
          .length;

  static bool _touches(
    Txn t, {
    int? accountId,
    int? cardId,
    int? investmentId,
  }) =>
      (accountId != null &&
          (t.fromAccountId == accountId || t.toAccountId == accountId)) ||
      (cardId != null && (t.fromCardId == cardId || t.toCardId == cardId)) ||
      (investmentId != null && t.investmentId == investmentId);

  /// Deletes an account, card or investment together with every transaction
  /// and recurring rule that uses it. Returns the receipt photos of the
  /// deleted transactions so the caller can remove the files.
  Future<List<String>> deleteHolding({
    int? accountId,
    int? cardId,
    int? investmentId,
  }) async {
    bool uses(Txn t) => _touches(
      t,
      accountId: accountId,
      cardId: cardId,
      investmentId: investmentId,
    );
    final receipts = [
      for (final t in _txns)
        if (uses(t) && t.receiptPath != null) t.receiptPath!,
    ];
    _txns.removeWhere(uses);
    _recurring.removeWhere((r) => uses(r.template));
    _accounts.removeWhere((a) => a.id == accountId);
    _cards.removeWhere((c) => c.id == cardId);
    _investments.removeWhere((i) => i.id == investmentId);
    if (lastSource == Source.account(accountId ?? -1) ||
        lastSource == Source.card(cardId ?? -1)) {
      lastSource = null;
    }
    await _save();
    return receipts;
  }

  // ---- Transactions -------------------------------------------------------

  /// Saves [t] (a new one when its id is 0). Returns validation errors, or an
  /// empty list on success.
  ///
  /// With [repeat], a new entry also becomes a [Recurring] rule whose later
  /// copies are posted automatically.
  /// Money into or out of a NAV-linked fund buys or sells units at the
  /// latest NAV, so the fund's value keeps up with every SIP instalment.
  Txn _withUnits(Txn t) {
    if (t.units != null || t.investmentId == null) return t;
    if (t.type != TxnType.invest && t.type != TxnType.investWithdrawal) {
      return t;
    }
    final inv = _ledger.investment(t.investmentId);
    final nav = inv?.lastNav;
    if (inv == null || !inv.isLinked || nav == null || nav <= 0) return t;
    return t.copyWith(units: t.amount / 100 / nav);
  }

  Future<List<String>> saveTxn(Txn t, {Frequency? repeat}) async {
    final errors = validate(t);
    if (errors.isNotEmpty) return errors;
    t = _withUnits(t);
    var saved = t.id == 0 ? t.copyWith(id: _newId()) : t;
    if (repeat != null && t.recurringId == null) {
      final rule = Recurring(
        id: _newId(),
        template: Txn.fromJson(
          {...t.toJson(), 'id': 0}
            ..remove('receipt')
            ..remove('src'),
        ),
        frequency: repeat,
        nextDate: dateOnly(t.date),
      );
      _recurring.add(rule.copyWith(nextDate: rule.after(t.date)));
      saved = saved.copyWith(recurringId: rule.id);
    }
    _upsert(_txns, saved, (e) => e.id);
    if (t.type == TxnType.expense) {
      lastCategory = t.category ?? lastCategory;
      lastSource = t.fromAccountId != null
          ? Source.account(t.fromAccountId!)
          : Source.card(t.fromCardId!);
    }
    await _save();
    return const [];
  }

  Future<void> deleteTxn(int id) {
    for (final t in _txns.where((t) => t.id == id)) {
      // Deleting an imported entry means "not this one": keep it out.
      if (t.sourceKey != null) _ignoredKeys.add(t.sourceKey!);
    }
    _txns.removeWhere((t) => t.id == id);
    return _save();
  }

  /// Adds [t] back after an undo.
  Future<void> restoreTxn(Txn t) {
    if (t.sourceKey != null) _ignoredKeys.remove(t.sourceKey);
    _upsert(_txns, t, (e) => e.id);
    return _save();
  }

  // ---- Bank message sync ---------------------------------------------------

  /// Plans a sync of [events] against the current data (nothing is saved).
  SyncResult planEvents(List<SourcedEvent> events, {String source = 'SMS'}) =>
      planSync(events, ledger, ignoredKeys: _ignoredKeys, sourceLabel: source);

  /// Saves a planned sync: new and linked entries, bank bills (which also
  /// set the card's due day), and the detected cards/accounts and balances
  /// for the UI.
  Future<void> applySync(SyncResult r, {bool remember = true}) async {
    for (final t in r.added) {
      _txns.add(t.copyWith(id: _newId()));
    }
    for (final t in r.updated) {
      _upsert(_txns, t, (e) => e.id);
    }
    for (final MapEntry(key: cardId, value: bill) in r.bills.entries) {
      final c = ledger.card(cardId);
      if (c == null) continue;
      _upsert(
        _cards,
        c.copyWith(
          bill: bill,
          dueDay: bill.dueDate.day,
          statementDay: bill.statementDate?.day,
        ),
        (e) => e.id,
      );
    }
    if (remember) {
      detected = {
        for (final e in r.unknown.entries)
          if (!_isTracked(e.value)) e.key: e.value,
      };
      balanceHints = r.balances;
      lastSync = DateTime.now();
    }
    await _save();
  }

  bool _isTracked(DetectedHolding h) => h.isCard
      ? ledger.cards.any((c) => c.lastFour == h.digits)
      : ledger.accounts.any((a) => a.lastFour == h.digits);

  /// Adds cards/accounts found in a statement to [detected].
  void mergeDetected(Map<String, DetectedHolding> found) {
    if (found.isEmpty) return;
    detected = {...detected, ...found};
    notifyListeners();
  }

  /// Forgets a detected card/account (e.g. after adding it, or dismissing).
  void dismissDetected(String key) {
    detected = {...detected}..remove(key);
    notifyListeners();
  }

  /// Sets the account's balance to what the bank reported.
  Future<void> acceptBankBalance(int accountId) async {
    final hint = balanceHints[accountId];
    final a = ledger.account(accountId);
    if (hint == null || a == null) return;
    final shift =
        hint.balance - ledger.accountBalance(accountId, asOf: hint.date);
    _upsert(
      _accounts,
      a.copyWith(openingBalance: a.openingBalance + shift),
      (e) => e.id,
    );
    balanceHints = {...balanceHints}..remove(accountId);
    await _save();
  }

  Future<void> setSmsSync(bool on) {
    smsSync = on;
    return _save();
  }

  // ---- Recurring entries -------------------------------------------------

  /// Posts every recurring entry that has fallen due up to [today]. Rules
  /// whose account, card or investment no longer exists are paused. Returns
  /// the number of entries posted.
  Future<int> postDueRecurring(DateTime today) async {
    var posted = 0;
    var changed = false;
    for (var i = 0; i < _recurring.length; i++) {
      final r = _recurring[i];
      final dates = r.dueDates(today);
      if (dates.isEmpty) continue;
      changed = true;
      final t = r.template;
      final valid =
          validate(t).isEmpty &&
          (t.fromAccountId == null ||
              ledger.account(t.fromAccountId) != null) &&
          (t.toAccountId == null || ledger.account(t.toAccountId) != null) &&
          (t.fromCardId == null || ledger.card(t.fromCardId) != null) &&
          (t.toCardId == null || ledger.card(t.toCardId) != null) &&
          (t.investmentId == null || ledger.investment(t.investmentId) != null);
      if (!valid) {
        _recurring[i] = r.copyWith(active: false);
        continue;
      }
      for (final d in dates) {
        _txns.add(t.copyWith(id: _newId(), date: d, recurringId: r.id));
        posted++;
      }
      _recurring[i] = r.copyWith(nextDate: r.after(dates.last));
    }
    if (changed) await _save();
    return posted;
  }

  Future<void> setRecurringActive(Recurring r, bool active) {
    _upsert(
      _recurring,
      r.copyWith(
        active: active,
        // Resuming starts from the next date after today, not the backlog.
        nextDate: active && r.nextDate.isBefore(dateOnly(DateTime.now()))
            ? _nextFrom(r, dateOnly(DateTime.now()))
            : null,
      ),
      (e) => e.id,
    );
    return _save();
  }

  static DateTime _nextFrom(Recurring r, DateTime day) {
    var d = r.nextDate;
    while (d.isBefore(day)) {
      d = r.after(d);
    }
    return d;
  }

  /// Deletes the rule; entries it already posted stay.
  Future<void> deleteRecurring(int id) {
    _recurring.removeWhere((r) => r.id == id);
    return _save();
  }

  // ---- Budgets ------------------------------------------------------------

  /// Sets the monthly budget for [category]; zero removes it.
  Future<void> setBudget(String category, Paise monthlyLimit) {
    _budgets.removeWhere((b) => b.category == category);
    if (monthlyLimit > 0) {
      _budgets.add(Budget(category: category, monthlyLimit: monthlyLimit));
    }
    return _save();
  }

  // ---- Import / backup ----------------------------------------------------

  /// Adds already-validated imported entries (ids are assigned here).
  Future<void> addImported(List<Txn> txns) {
    for (final t in txns) {
      _txns.add(t.copyWith(id: _newId()));
    }
    return _save();
  }

  /// Full backup of all data as JSON.
  String backupJson() =>
      const JsonEncoder.withIndent(' ')
          .convert({'app': 'rupeetrack', 'version': 1, ...toJson()});

  /// Replaces all data with a backup made by [backupJson]. Throws
  /// [FormatException] if the file is not a Rupio backup; the current
  /// data is kept in that case.
  Future<void> restoreBackup(String json) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw FormatException(tr('This file is not a Rupio backup'));
    }
    if (decoded is! Map<String, dynamic> || decoded['app'] != 'rupeetrack') {
      throw FormatException(tr('This file is not a Rupio backup'));
    }
    try {
      _loadJson(decoded);
    } catch (_) {
      throw FormatException(tr('The backup file is damaged'));
    }
    await _save();
  }

  Future<void> setNotifications(bool on) {
    notifications = on;
    return _save();
  }

  Future<void> setDailyReminder(int? minutes) {
    dailyReminder = minutes;
    return _save();
  }

  Future<void> setThemeMode(ThemeMode mode) {
    themeMode = mode;
    return _save();
  }

  Future<void> markSwipeHintSeen() {
    swipeHintSeen = true;
    return _save();
  }

  Future<void> finishOnboarding() {
    onboarded = true;
    return _save();
  }

  Future<void> setLanguage(String code) {
    language = code;
    setCurrentLanguage(code);
    return _save();
  }

  // ---- Loans and savings goals -------------------------------------------

  /// Adds [loan] (id 0) or replaces the loan with the same id.
  Future<Loan> saveLoan(Loan loan) async {
    final l = loan.id == 0
        ? Loan(
            id: _newId(),
            name: loan.name,
            lender: loan.lender,
            principal: loan.principal,
            emi: loan.emi,
            interestRate: loan.interestRate,
            tenureMonths: loan.tenureMonths,
            firstEmiDate: loan.firstEmiDate,
            paidBefore: loan.paidBefore,
            accountId: loan.accountId,
            closed: loan.closed,
          )
        : loan;
    _upsert(_loans, l, (e) => e.id);
    await _save();
    return l;
  }

  /// Deletes the loan; EMIs already recorded stay as expenses.
  Future<void> deleteLoan(int id) {
    _loans.removeWhere((l) => l.id == id);
    return _save();
  }

  /// Records one EMI on [loan] as an expense from [accountId].
  Future<List<String>> payEmi(
    Loan loan, {
    required int accountId,
    required DateTime date,
    Paise? amount,
  }) => saveTxn(
    Txn(
      id: 0,
      type: TxnType.expense,
      amount: amount ?? loan.emi,
      date: date,
      category: 'EMI',
      note: loan.name,
      fromAccountId: accountId,
      loanId: loan.id,
    ),
  );

  Future<SavingsGoal> saveGoal(SavingsGoal goal) async {
    final g = goal.id == 0
        ? SavingsGoal(
            id: _newId(),
            name: goal.name,
            target: goal.target,
            targetDate: goal.targetDate,
            entries: goal.entries,
          )
        : goal;
    _upsert(_goals, g, (e) => e.id);
    await _save();
    return g;
  }

  Future<void> deleteGoal(int id) {
    _goals.removeWhere((g) => g.id == id);
    return _save();
  }

  /// Puts [amount] aside for [goal] (negative to take money out).
  Future<void> addToGoal(SavingsGoal goal, Paise amount, DateTime date) =>
      saveGoal(
        goal.copyWith(entries: [...goal.entries, GoalEntry(date, amount)]),
      );
}
