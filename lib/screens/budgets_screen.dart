import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../ledger/ledger.dart';
import '../models/models.dart';
import '../models/money.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import 'home_screen.dart' show BudgetRow;
import '../l10n/strings.dart';

/// Monthly limits per spending category, with this month's progress.
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    String category,
    int? current,
  ) async {
    final controller = TextEditingController(
      text: current == null ? '' : (current ~/ 100).toString(),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('{0} budget', [tr(category)])),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AmountField(
              controller: controller,
              label: tr('Monthly limit'),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Text(
              tr('You will be warned at 80% and when it is crossed.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (current != null)
            TextButton(
              onPressed: () => Navigator.pop(context, 0),
              child: Text(tr('Remove')),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final v = parseRupees(controller.text);
              if (v != null && v > 0) Navigator.pop(context, v);
            },
            child: Text(tr('Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null && context.mounted) {
      await context.store.setBudget(category, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.ledger;
    final now = today();
    final statuses = l.budgetStatuses(now);
    final withBudget = {for (final s in statuses) s.budget.category};
    final spent = l.spendingByCategory(monthStart(now), monthEnd(now));
    final others = {
      ...expenseCategories,
      ...spent.keys,
    }.where((c) => !withBudget.contains(c)).toList();
    final totalLimit = statuses.fold(0, (s, b) => s + b.budget.monthlyLimit);
    final totalSpent = statuses.fold(0, (s, b) => s + b.spent);

    return Scaffold(
      appBar: AppBar(title: Text(tr('Budgets'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (statuses.isNotEmpty)
            HeroPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HeroFigure(
                    tr('{0} · left to spend', [monthLabel(now)]),
                    formatRupees(totalLimit - totalSpent),
                    big: true,
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: totalLimit == 0
                          ? 0
                          : (totalSpent / totalLimit).clamp(0.0, 1.0),
                      minHeight: 8,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('{0} of {1} used', [
                      formatRupees(totalSpent),
                      formatRupees(totalLimit),
                    ]),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          if (statuses.isNotEmpty) ...[
            SectionHeader(tr('Your budgets')),
            Panel(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  for (final s in statuses)
                    InkWell(
                      onTap: () => _edit(
                        context,
                        s.budget.category,
                        s.budget.monthlyLimit,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: BudgetRow(status: s),
                      ),
                    ),
                ],
              ),
            ),
          ],
          SectionHeader(
            statuses.isEmpty ? tr('Pick a category') : tr('Add budget'),
          ),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final c in others)
                  ListTile(
                    leading: IconBadge(iconForCategory(c), size: 40),
                    title: Text(tr(c)),
                    subtitle: (spent[c] ?? 0) > 0
                        ? Text(tr('{0} this month', [formatRupees(spent[c]!)]))
                        : null,
                    trailing: const Icon(Icons.add),
                    onTap: () => _edit(context, c, null),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
