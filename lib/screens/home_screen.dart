import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../ledger/ledger.dart';
import '../models/models.dart';
import '../models/money.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import '../widgets/swipe_delete.dart';
import 'accounts_screen.dart';
import 'auto_detect_screen.dart';
import 'budgets_screen.dart';
import 'forms.dart';
import 'goals_screen.dart';
import 'insights_screen.dart';
import 'investments_screen.dart';
import 'loans_screen.dart';
import 'onboarding_screen.dart';
import 'pay_bill_sheet.dart';
import 'quick_add_sheet.dart';
import 'settings_screen.dart';
import '../l10n/strings.dart';

const monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _monthLetters = [
  'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D', //
];

enum HomeRange { month, year, all }

void push(BuildContext context, Widget screen) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));

/// Home: one big number for the chosen period (expense or income), a bar
/// chart, a short overview of everything else, and that period's entries.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenTab});

  /// Switches the bottom navigation to another tab.
  final ValueChanged<int> onOpenTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _income = false;
  HomeRange _range = HomeRange.month;

  /// Month shown in 1M (null: this month) and year shown in 1Y.
  DateTime? _month;
  int? _year;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    if (store.isEmpty) {
      if (!store.onboarded) {
        return OnboardingScreen(onDone: store.finishOnboarding);
      }
      return const Scaffold(body: SafeArea(child: _Welcome()));
    }
    final l = store.ledger;
    final now = today();
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    Paise total(DateTime from, DateTime to) =>
        _income ? l.income(from, to) : l.spending(from, to);

    // Period, bars and labels.
    final month = _month ?? monthStart(now);
    final year = _year ?? now.year;
    final firstYear = l.txns.isEmpty ? now.year : l.txns.last.date.year;
    late DateTime from, to;
    late String periodLabel;
    late String caption;
    final values = <int>[];
    final labels = <String>[];
    final tips = <String>[];
    int? highlight;
    var every = 1;
    var canPrev = false, canNext = false;
    VoidCallback? onPrev, onNext;
    final rows = <(String, Paise, VoidCallback)>[];
    switch (_range) {
      case HomeRange.month:
        from = monthStart(month);
        to = monthEnd(month);
        periodLabel = month.year == now.year
            ? tr(monthsLong[month.month - 1])
            : '${tr(monthsLong[month.month - 1])} ${month.year}';
        for (var d = 1; d <= to.day; d++) {
          final day = DateTime.utc(month.year, month.month, d);
          values.add(total(day, day));
          labels.add('$d');
          tips.add(shortDate(day));
        }
        if (from == monthStart(now)) highlight = now.day - 1;
        every = 4;
        caption = tr('Each bar is one day. Tap a bar to see the amount.');
        canPrev =
            month.year > firstYear - 1 &&
            month.isAfter(DateTime.utc(firstYear - 1, 12));
        canNext = from.isBefore(monthStart(now));
        onPrev = () =>
            setState(() => _month = DateTime.utc(month.year, month.month - 1));
        onNext = () =>
            setState(() => _month = DateTime.utc(month.year, month.month + 1));
      case HomeRange.year:
        from = DateTime.utc(year);
        to = DateTime.utc(year, 12, 31);
        periodLabel = '$year';
        final english = currentLanguage == 'en';
        for (var m = 1; m <= 12; m++) {
          final ms = DateTime.utc(year, m);
          final v = total(ms, monthEnd(ms));
          values.add(v);
          labels.add(english ? _monthLetters[m - 1] : '$m');
          tips.add('${tr(monthsLong[m - 1])} $year');
          final inPast = !ms.isAfter(monthStart(now));
          if (inPast && (v > 0 || ms == monthStart(now))) {
            rows.add((
              tr(monthsLong[m - 1]),
              v,
              () => setState(() {
                _range = HomeRange.month;
                _month = ms;
              }),
            ));
          }
        }
        if (year == now.year) highlight = now.month - 1;
        caption = tr(
          'Each bar is one month. Tap a month below to see its days.',
        );
        canPrev = year > firstYear;
        canNext = year < now.year;
        onPrev = () => setState(() => _year = year - 1);
        onNext = () => setState(() => _year = year + 1);
      case HomeRange.all:
        final start = firstYear < now.year - 4 ? firstYear : now.year - 4;
        from = DateTime.utc(start);
        to = DateTime.utc(now.year, 12, 31);
        periodLabel = tr('All time');
        for (var y = start; y <= now.year; y++) {
          final v = total(DateTime.utc(y), DateTime.utc(y, 12, 31));
          values.add(v);
          labels.add('$y');
          tips.add('$y');
          if (v > 0 || y == now.year) {
            rows.add((
              '$y',
              v,
              () => setState(() {
                _range = HomeRange.year;
                _year = y;
              }),
            ));
          }
        }
        highlight = values.length - 1;
        caption = tr(
          'Each bar is one year. Tap a year below to see its months.',
        );
    }
    final sum = total(from, to);
    final seriesColor = _income ? scheme.moneyIn : kCoral;
    final entries = l.txns
        .where(
          (x) =>
              (_income
                  ? x.type == TxnType.income
                  : x.type == TxnType.expense) &&
              !x.date.isBefore(from) &&
              !x.date.isAfter(to),
        )
        .take(60)
        .toList();
    final isCurrentMonth = _range == HomeRange.month && from == monthStart(now);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.insights_outlined),
                    tooltip: tr('Insights'),
                    onPressed: () => push(context, const InsightsScreen()),
                  ),
                  Expanded(
                    child: Center(
                      child: Toggle(
                        options: [tr('Expense'), tr('Income')],
                        selected: _income ? 1 : 0,
                        onChanged: (i) => setState(() => _income = i == 1),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: tr('Settings'),
                    onPressed: () => push(context, const SettingsScreen()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (onPrev != null)
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: tr('Previous'),
                    onPressed: canPrev ? onPrev : null,
                  ),
                Text(
                  periodLabel,
                  style: t.titleMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (onNext != null)
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: tr('Next'),
                    onPressed: canNext ? onNext : null,
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  formatRupees(sum),
                  style: t.displayMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _income && sum > 0 ? scheme.moneyIn : null,
                  ),
                ),
              ),
            ),
            Center(
              child: Text(
                _income ? tr('earned') : tr('spent'),
                style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 6),
            if (isCurrentMonth)
              Center(
                child: _Subline(income: _income, range: _range, now: now),
              ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: PeriodBars(
                values: values,
                labels: labels,
                tooltipLabels: tips,
                highlight: highlight,
                labelEvery: every,
                color: seriesColor,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(
                caption,
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: scheme.outline),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Wrap(
                spacing: 8,
                children: [
                  for (final (r, label) in [
                    (HomeRange.month, '1M'),
                    (HomeRange.year, '1Y'),
                    (HomeRange.all, tr('All')),
                  ])
                    RangeChip(
                      label: label,
                      selected: _range == r,
                      onTap: () => setState(() {
                        _range = r;
                        _month = null;
                        _year = null;
                      }),
                    ),
                ],
              ),
            ),
            if (rows.isNotEmpty)
              Panel(
                margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final (label, v, open) in rows.reversed)
                      ListTile(
                        onTap: open,
                        title: Text(label),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formatRupees(v),
                              style: t.titleSmall?.copyWith(
                                color: _income && v > 0 ? scheme.moneyIn : null,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right, color: scheme.outline),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            if (store.detected.isNotEmpty)
              _Notice(
                icon: Icons.auto_awesome_outlined,
                color: scheme.primary,
                text: tr('Found {0} in your bank messages', [
                  store.detected.values.map((h) => h.label).join(', '),
                ]),
                onTap: () => push(context, const AutoDetectScreen()),
              ),
            for (final a in l.alerts(now))
              _AlertNotice(alert: a, onOpenTab: widget.onOpenTab),
            _Overview(now: now, onOpenTab: widget.onOpenTab),
            if (isCurrentMonth) IncomeSplitCard(now: now),
            if (_range == HomeRange.month) ...[
              SectionHeader(
                _income ? tr('Income') : tr('Expenses'),
                action: TextButton(
                  onPressed: () => widget.onOpenTab(1),
                  child: Text(tr('See all')),
                ),
              ),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Column(
                    children: [
                      Text(
                        _income ? tr('No income yet') : tr('No expenses yet'),
                        style: t.titleMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tr('Tap + to add one'),
                        style: t.bodyMedium?.copyWith(color: scheme.outline),
                      ),
                    ],
                  ),
                )
              else
                for (final (i, group) in groupByDay(entries).indexed)
                  _DayGroup(
                    day: group.$1,
                    txns: group.$2,
                    hintFirst: i == 0 && !context.store.swipeHintSeen,
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Entries grouped by date, newest first.
List<(DateTime, List<Txn>)> groupByDay(List<Txn> txns) {
  final groups = <(DateTime, List<Txn>)>[];
  for (final x in txns) {
    if (groups.isEmpty || groups.last.$1 != x.date) {
      groups.add((x.date, [x]));
    } else {
      groups.last.$2.add(x);
    }
  }
  return groups;
}

class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.day,
    required this.txns,
    this.hintFirst = false,
  });
  final DateTime day;
  final List<Txn> txns;

  /// Show the swipe-to-delete hint on the first entry.
  final bool hintFirst;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final total = txns.fold(0, (a, x) => a + x.amount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  relativeDate(day),
                  style: t.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              Text(
                formatRupees(total),
                style: t.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        for (final (i, x) in txns.indexed)
          SwipeToDelete(
            txn: x,
            hint: hintFirst && i == 0,
            child: TxnTile(
              x,
              showDate: false,
              onTap: () => showQuickAdd(context, initial: x),
            ),
          ),
      ],
    );
  }
}

/// Budget left, or how this month compares with last month.
class _Subline extends StatelessWidget {
  const _Subline({
    required this.income,
    required this.range,
    required this.now,
  });
  final bool income;
  final HomeRange range;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l = context.ledger;
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: scheme.onSurfaceVariant);
    if (income || range != HomeRange.month) {
      if (!income) return const SizedBox(height: 20);
      final spent = range == HomeRange.month
          ? l.spending(monthStart(now), monthEnd(now))
          : null;
      final earned = l.income(monthStart(now), monthEnd(now));
      if (spent == null || earned <= 0) return const SizedBox(height: 20);
      final saved = earned - spent;
      return Text(
        saved >= 0
            ? tr('{0} left after spending', [formatRupees(saved)])
            : tr('{0} more spent than earned', [formatRupees(-saved)]),
        style: style,
      );
    }
    final budgets = l.budgetStatuses(now);
    if (budgets.isEmpty) {
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => push(context, const BudgetsScreen()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(tr('Set a budget ›'), style: style),
        ),
      );
    }
    final limit = budgets.fold(0, (a, b) => a + b.budget.monthlyLimit);
    final spent = budgets.fold(0, (a, b) => a + b.spent);
    final left = limit - spent;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => push(context, const BudgetsScreen()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          left >= 0
              ? tr('{0} left of {1} budget', [
                  formatRupees(left),
                  formatRupees(limit),
                ])
              : tr('{0} over budget', [formatRupees(-left)]),
          style: style?.copyWith(color: left < 0 ? scheme.error : null),
        ),
      ),
    );
  }
}

/// Net worth and one row per area of the app, each opening its screen.
class _Overview extends StatelessWidget {
  const _Overview({required this.now, required this.onOpenTab});
  final DateTime now;
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final l = context.ledger;
    final scheme = Theme.of(context).colorScheme;
    final worth = l.netWorth(now);
    final emi = l.monthlyEmi(now);
    final saved = l.goalsSaved;
    Widget row(
      IconData icon,
      String label,
      String value,
      VoidCallback onTap, {
      Color? color,
    }) => ListTile(
      onTap: onTap,
      leading: IconBadge(icon, size: 38),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: scheme.outline, size: 20),
        ],
      ),
    );
    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Net worth'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  formatRupees(worth.total),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          row(
            Icons.account_balance_outlined,
            tr('Accounts'),
            formatRupees(worth.cash),
            () => push(context, const AccountsScreen()),
          ),
          row(
            Icons.credit_card_outlined,
            tr('Cards owed'),
            formatRupees(worth.liabilities),
            () => onOpenTab(2),
            color: worth.liabilities > 0 ? scheme.error : null,
          ),
          row(
            Icons.trending_up_rounded,
            tr('Investments'),
            formatRupees(worth.investments),
            () => push(context, const InvestmentsScreen()),
          ),
          row(
            Icons.event_repeat_outlined,
            tr('EMIs per month'),
            l.loans.isEmpty ? tr('Add') : formatRupees(emi),
            () => push(context, const LoansScreen()),
            color: l.loans.isEmpty ? scheme.onSurfaceVariant : kCoral,
          ),
          row(
            Icons.savings_outlined,
            tr('Savings goals'),
            l.goals.isEmpty ? tr('Add') : formatRupees(saved),
            () => push(context, const GoalsScreen()),
            color: l.goals.isEmpty ? scheme.onSurfaceVariant : scheme.moneyIn,
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.text,
    this.onTap,
    this.action,
  });
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback? onTap;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
          ?action,
        ],
      ),
    );
  }
}

class _AlertNotice extends StatelessWidget {
  const _AlertNotice({required this.alert, required this.onOpenTab});
  final FinanceAlert alert;
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (alert.kind) {
      AlertKind.overdue => (Icons.error_outline, scheme.error),
      AlertKind.dueSoon => (Icons.event_outlined, kOrange),
      AlertKind.overBudget => (Icons.money_off_outlined, scheme.error),
      AlertKind.highUtilisation => (Icons.speed_outlined, kOrange),
      AlertKind.nearBudget => (Icons.pie_chart_outline, kOrange),
      AlertKind.emiDue => (Icons.event_repeat_outlined, kCoral),
    };
    final card = alert.card;
    final payable =
        card != null &&
        (alert.kind == AlertKind.overdue || alert.kind == AlertKind.dueSoon);
    return _Notice(
      icon: icon,
      color: color,
      text: alert.message,
      onTap: () {
        if (alert.category != null) {
          push(context, const BudgetsScreen());
        } else if (alert.loan != null) {
          push(context, const LoansScreen());
        } else {
          onOpenTab(2);
        }
      },
      action: payable
          ? TextButton(
              onPressed: () => showPayBillSheet(context, card),
              child: Text(tr('Pay')),
            )
          : null,
    );
  }
}

class RangeChip extends StatelessWidget {
  const RangeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.surfaceContainerLow : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget point(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/brand/icon.png',
                  width: 48,
                  height: 48,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rupio',
                      style: t.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      tr('Expense Tracker'),
                      style: t.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => showLanguagePicker(context),
                icon: const Icon(Icons.translate, size: 18),
                label: Text(currentLanguageName()),
              ),
            ],
          ),
          const Spacer(),
          Text.rich(
            TextSpan(
              text: tr('Know where every\n'),
              children: [
                TextSpan(
                  text: tr('rupee goes.'),
                  style: TextStyle(color: scheme.primary),
                ),
              ],
            ),
            textAlign: TextAlign.center,
            style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                point(tr('Log a spend in seconds')),
                Divider(height: 1, color: scheme.outlineVariant),
                point(tr('Card bills, EMIs and goals in one place')),
                Divider(height: 1, color: scheme.outlineVariant),
                point(tr('Private and offline. No sign-up')),
              ],
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => showAddAccountDialog(context),
            child: Text(tr('Add bank account or cash')),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => showAddCardDialog(context),
            child: Text(tr('Add credit card')),
          ),
        ],
      ),
    );
  }
}

/// Category, spent / limit and a meter that turns amber then red.
class BudgetRow extends StatelessWidget {
  const BudgetRow({super.key, required this.status});
  final BudgetStatus status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final scheme = Theme.of(context).colorScheme;
    final color = s.percent >= 100
        ? scheme.error
        : s.percent >= 80
        ? kOrange
        : scheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              iconForCategory(s.budget.category),
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(tr(s.budget.category))),
            Text(
              '${formatRupees(s.spent)} / ${formatRupees(s.budget.monthlyLimit)}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Meter(value: s.percent / 100, color: color, height: 8),
      ],
    );
  }
}
