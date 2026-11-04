import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../ledger/ledger.dart';
import '../models/money.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import 'home_screen.dart';
import '../l10n/strings.dart';

/// Trends and habits: spending pace, income vs spending, where the money
/// went, and short insights.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.ledger;
    final now = today();
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final from = monthStart(now), to = monthEnd(now);
    final byCategory = l.spendingByCategory(from, to);
    final streak = l.noSpendStreak(now);
    final change = l.spendingChangeVsLastMonth(now);
    final avg = l.dailyAverage(now);

    final facts = <(String, String)>[
      if (streak > 0)
        (
          streak == 1 ? tr('1 day') : tr('{0} days', [streak]),
          tr('without spending'),
        ),
      if (change != null)
        (
          change <= 0
              ? tr('{0}% less', [change.abs().toStringAsFixed(0)])
              : tr('{0}% more', [change.abs().toStringAsFixed(0)]),
          tr('than this time last month'),
        ),
      if (avg > 0) (formatRupees(avg), tr('average spend per day')),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(tr('Insights'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          IncomeSplitCard(now: now),
          if (facts.isNotEmpty)
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Column(
                children: [
                  for (var i = 0; i < facts.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                    Padding(
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
                          Text(facts[i].$1, style: t.titleMedium),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              facts[i].$2,
                              style: t.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Spending pace'), style: t.titleMedium),
                const SizedBox(height: 2),
                Text(
                  tr('Total spent so far in {0}, day by day', [
                    tr(monthsLong[now.month - 1]),
                  ]),
                  style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                SpendingPaceChart(ledger: l, today: now),
                const SizedBox(height: 10),
                ChartLegend([
                  (tr('This month'), scheme.onSurface, false),
                  (tr('Last month'), scheme.outline, true),
                ]),
              ],
            ),
          ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Income vs spending'), style: t.titleMedium),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Figure(
                        tr('Income'),
                        formatRupeesCompact(l.income(from, to)),
                        color: scheme.moneyIn,
                      ),
                    ),
                    Expanded(
                      child: Figure(
                        tr('Spent'),
                        formatRupeesCompact(l.spending(from, to)),
                      ),
                    ),
                    Expanded(
                      child: Figure(
                        tr('Invested'),
                        formatRupeesCompact(l.invested(from, to)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                IncomeSpendBars(ledger: l, today: now),
                const SizedBox(height: 10),
                ChartLegend([
                  (tr('Income'), scheme.moneyIn, false),
                  (tr('Spent'), scheme.onSurface, false),
                ]),
              ],
            ),
          ),
          if (byCategory.values.any((v) => v > 0))
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Where it went'), style: t.titleMedium),
                  const SizedBox(height: 8),
                  CategoryBreakdown(byCategory: byCategory),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Where this month's income went: EMIs, other spending, investments and
/// what is left, as one stacked bar with plain-language labels.
class IncomeSplitCard extends StatelessWidget {
  const IncomeSplitCard({super.key, required this.now});
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l = context.ledger;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final from = monthStart(now), to = monthEnd(now);
    final income = l.income(from, to);
    final byCategory = l.spendingByCategory(from, to);
    final emi = (byCategory['EMI'] ?? 0).clamp(0, 1 << 52);
    final spent = (l.spending(from, to) - emi).clamp(0, 1 << 52);
    final invested = l.invested(from, to);
    final left = income - emi - spent - invested;
    if (income <= 0) {
      return Panel(
        child: Row(
          children: [
            IconBadge(Icons.pie_chart_outline_rounded, color: scheme.moneyIn),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                tr('Add this month\'s salary or income to see where it goes.'),
                style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }
    int pct(int v) => (v * 100 / income).round();
    final parts = <(String, int, Color)>[
      if (emi > 0) (tr('EMIs'), emi, kCoral),
      if (spent > 0) (tr('Spending'), spent, scheme.onSurface),
      if (invested > 0) (tr('Invested'), invested, kViolet),
      if (left > 0) (tr('Left'), left, scheme.moneyIn),
    ];
    final headline = emi > 0
        ? tr('{0}% of your income goes to EMIs', [pct(emi)])
        : tr('{0}% of your income is spent', [pct(spent)]);
    final perHundred = left > 0
        ? tr('Out of every ₹100 you earned this month, ₹{0} is left.', [
            pct(left),
          ])
        : tr('You spent more than you earned this month.');
    final total = parts.fold(0, (a, p) => a + p.$2);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Where your income goes'),
            style: t.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(headline, style: t.titleLarge),
          const SizedBox(height: 4),
          Text(
            perHundred,
            style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < parts.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: (parts[i].$2 * 1000 / total).round().clamp(1, 1000),
                      child: ColoredBox(color: parts[i].$3),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (final (label, v, color) in parts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label)),
                  Text(formatRupees(v), style: t.titleSmall),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${pct(v)}%',
                      textAlign: TextAlign.right,
                      style: t.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              tr('Income this month: {0}', [formatRupees(income)]),
              style: t.bodySmall?.copyWith(color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}
