import 'models.dart';
import 'money.dart';

/// A loan repaid in equal monthly instalments (EMI): home, car, personal,
/// education, gold, or a "no-cost EMI" purchase.
///
/// Each EMI paid is an expense [Txn] with category `EMI` and
/// [Txn.loanId] set, so it reduces the paying account like any other
/// expense; the loan's progress is derived from those entries.
class Loan {
  const Loan({
    required this.id,
    required this.name,
    required this.emi,
    required this.tenureMonths,
    required this.firstEmiDate,
    this.lender = '',
    this.principal = 0,
    this.interestRate,
    this.paidBefore = 0,
    this.accountId,
    this.closed = false,
  });

  final int id;
  final String name;
  final String lender;

  /// Amount borrowed (optional; 0 when unknown).
  final Paise principal;
  final Paise emi;

  /// Yearly interest rate in percent, for display only.
  final double? interestRate;
  final int tenureMonths;

  /// Date of the first instalment; later ones fall on the same day of the
  /// month.
  final DateTime firstEmiDate;

  /// Instalments already paid before the loan was added to the app.
  final int paidBefore;

  /// Account the EMI is usually paid from.
  final int? accountId;

  /// Closed early (prepaid) or finished.
  final bool closed;

  /// Date of instalment number [n] (0-based).
  DateTime emiDate(int n) {
    final first = DateTime.utc(firstEmiDate.year, firstEmiDate.month + n);
    final length = DateTime.utc(first.year, first.month + 1, 0).day;
    final day = firstEmiDate.day > length ? length : firstEmiDate.day;
    return DateTime.utc(first.year, first.month, day);
  }

  DateTime get lastEmiDate => emiDate(tenureMonths - 1);

  Paise get totalPayable => emi * tenureMonths;

  Loan copyWith({bool? closed}) => Loan(
    id: id,
    name: name,
    lender: lender,
    principal: principal,
    emi: emi,
    interestRate: interestRate,
    tenureMonths: tenureMonths,
    firstEmiDate: firstEmiDate,
    paidBefore: paidBefore,
    accountId: accountId,
    closed: closed ?? this.closed,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (lender.isNotEmpty) 'lender': lender,
    if (principal != 0) 'principal': principal,
    'emi': emi,
    if (interestRate != null) 'rate': interestRate,
    'tenure': tenureMonths,
    'first': isoDate(firstEmiDate),
    if (paidBefore != 0) 'paidBefore': paidBefore,
    if (accountId != null) 'account': accountId,
    if (closed) 'closed': true,
  };

  factory Loan.fromJson(Map<String, dynamic> j) => Loan(
    id: j['id'] as int,
    name: j['name'] as String,
    lender: (j['lender'] as String?) ?? '',
    principal: (j['principal'] as int?) ?? 0,
    emi: j['emi'] as int,
    interestRate: (j['rate'] as num?)?.toDouble(),
    tenureMonths: j['tenure'] as int,
    firstEmiDate: parseIsoDate(j['first'] as String),
    paidBefore: (j['paidBefore'] as int?) ?? 0,
    accountId: j['account'] as int?,
    closed: (j['closed'] as bool?) ?? false,
  );
}

/// Money put aside (or taken back) for a [SavingsGoal].
class GoalEntry {
  const GoalEntry(this.date, this.amount);
  final DateTime date;

  /// Positive when adding, negative when taking money out.
  final Paise amount;

  Map<String, Object?> toJson() => {'date': isoDate(date), 'amount': amount};

  factory GoalEntry.fromJson(Map<String, dynamic> j) =>
      GoalEntry(parseIsoDate(j['date'] as String), j['amount'] as int);
}

/// Something to save up for (emergency fund, phone, bike, trip). Saving is
/// an earmark: it does not move money between accounts.
class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.name,
    required this.target,
    this.targetDate,
    this.entries = const [],
  });

  final int id;
  final String name;
  final Paise target;
  final DateTime? targetDate;
  final List<GoalEntry> entries;

  Paise get saved => entries.fold(0, (a, e) => a + e.amount);
  Paise get remaining => target - saved < 0 ? 0 : target - saved;
  bool get reached => saved >= target;
  double get progress =>
      target <= 0 ? 0 : (saved / target).clamp(0, 1).toDouble();

  /// How much to put aside each month to reach the target on time, or null
  /// without a target date.
  Paise? monthlyNeeded(DateTime today) {
    final d = targetDate;
    if (d == null || reached) return null;
    final months = (d.year - today.year) * 12 + d.month - today.month;
    return months <= 0 ? remaining : (remaining / months).ceil();
  }

  SavingsGoal copyWith({
    String? name,
    Paise? target,
    DateTime? targetDate,
    bool clearDate = false,
    List<GoalEntry>? entries,
  }) => SavingsGoal(
    id: id,
    name: name ?? this.name,
    target: target ?? this.target,
    targetDate: clearDate ? null : targetDate ?? this.targetDate,
    entries: entries ?? this.entries,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'target': target,
    if (targetDate != null) 'date': isoDate(targetDate!),
    'entries': entries.map((e) => e.toJson()).toList(),
  };

  factory SavingsGoal.fromJson(Map<String, dynamic> j) => SavingsGoal(
    id: j['id'] as int,
    name: j['name'] as String,
    target: j['target'] as int,
    targetDate: j['date'] == null ? null : parseIsoDate(j['date'] as String),
    entries: ((j['entries'] as List?) ?? const [])
        .map((e) => GoalEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
