import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../models/money.dart';
import '../models/planning.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import '../l10n/strings.dart';

/// Rent, SIPs, subscriptions and salary that are recorded automatically.
class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final l = store.ledger;
    final rules = [...l.recurring]
      ..sort((a, b) {
        if (a.active != b.active) return a.active ? -1 : 1;
        return a.nextDate.compareTo(b.nextDate);
      });
    final monthlyOut = rules
        .where(
          (r) =>
              r.active &&
              r.frequency == Frequency.monthly &&
              txnDirection(r.template) <= 0,
        )
        .fold(0, (s, r) => s + r.template.amount);

    return Scaffold(
      appBar: AppBar(title: Text(tr('Recurring'))),
      body: rules.isEmpty
          ? EmptyState(
              icon: Icons.event_repeat,
              message: tr(
                'Nothing repeats yet. When you add rent, a SIP, a subscription or salary, turn on "Repeat" and it will be recorded for you on each due date.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                HeroPanel(
                  child: HeroFigure(
                    tr('Fixed monthly outgoings'),
                    formatRupees(monthlyOut),
                    big: true,
                  ),
                ),
                Panel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [for (final r in rules) _RuleTile(rule: r)],
                  ),
                ),
                Padding(
                  padding: kPagePadding,
                  child: Text(
                    tr(
                      'Entries are added automatically when you open the app on or after the due date. Deleting a rule keeps entries already recorded.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({required this.rule});
  final Recurring rule;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final t = rule.template;
    final l = store.ledger;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: IconBadge(
        iconForTxn(t),
        color: rule.active ? null : scheme.outline,
        size: 40,
      ),
      title: Text(txnTitle(t, l)),
      subtitle: Text(
        rule.active
            ? tr('{0} · next {1}', [
                rule.frequency.label,
                shortDate(rule.nextDate),
              ])
            : tr('Paused'),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatRupees(t.amount),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'toggle') {
                await store.setRecurringActive(rule, !rule.active);
              } else if (v == 'delete') {
                await store.deleteRecurring(rule.id);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'toggle',
                child: Text(rule.active ? tr('Pause') : tr('Resume')),
              ),
              PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
            ],
          ),
        ],
      ),
    );
  }
}
