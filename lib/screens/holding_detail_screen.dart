import 'package:flutter/material.dart';

import '../app/files.dart';
import '../app/scope.dart';
import '../ledger/ledger.dart';
import '../models/models.dart';
import '../models/money.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import 'forms.dart';
import 'pay_bill_sheet.dart';
import 'quick_add_sheet.dart';
import '../l10n/strings.dart';

/// Statement-style view of one account, card or investment: entries grouped
/// by date with the balance after each one, plus edit and delete.
class HoldingDetailScreen extends StatelessWidget {
  const HoldingDetailScreen.account(int id, {super.key})
    : accountId = id,
      cardId = null,
      investmentId = null;
  const HoldingDetailScreen.card(int id, {super.key})
    : cardId = id,
      accountId = null,
      investmentId = null;
  const HoldingDetailScreen.investment(int id, {super.key})
    : investmentId = id,
      accountId = null,
      cardId = null;

  final int? accountId;
  final int? cardId;
  final int? investmentId;

  Future<void> _delete(BuildContext context, String title) async {
    final store = context.store;
    final count = store.usageCount(
      accountId: accountId,
      cardId: cardId,
      investmentId: investmentId,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete {0}?', [title])),
        content: Text(
          count == 0
              ? tr('This cannot be undone.')
              : count == 1
              ? tr(
                  'Its 1 entry will be deleted too, and every total will be recalculated. This cannot be undone.',
                )
              : tr(
                  'Its {0} entries will be deleted too, and every total will be recalculated. This cannot be undone.',
                  [count],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final receipts = await store.deleteHolding(
      accountId: accountId,
      cardId: cardId,
      investmentId: investmentId,
    );
    for (final r in receipts) {
      deleteReceipt(r);
    }
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(tr('{0} deleted', [title]))));
  }

  void _edit(BuildContext context) {
    final l = context.ledger;
    final a = l.account(accountId);
    final c = l.card(cardId);
    final i = l.investment(investmentId);
    if (a != null) showEditAccountDialog(context, a);
    if (c != null) showEditCardDialog(context, c);
    if (i != null) showEditInvestmentDialog(context, i);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.ledger;
    final account = l.account(accountId);
    final card = l.card(cardId);
    final investment = l.investment(investmentId);
    final title = account?.name ?? card?.displayName ?? investment?.name;
    if (title == null) {
      // Deleted while open.
      return Scaffold(appBar: AppBar());
    }

    final txns = accountId != null
        ? l.accountTxns(accountId!)
        : cardId != null
        ? l.cardTxns(cardId!)
        : l.investmentTxns(investmentId!);
    final balances = investment != null
        ? const <int, Paise>{}
        : l.runningBalances(accountId: accountId, cardId: cardId);

    final now = today();
    final from = monthStart(now), to = monthEnd(now);
    var inThisMonth = 0, outThisMonth = 0;
    for (final t in txns) {
      if (t.date.isBefore(from) || t.date.isAfter(to)) continue;
      final dir = account != null
          ? (t.toAccountId == account.id ? 1 : -1)
          : card != null
          ? (t.fromCardId == card.id ? -1 : 1)
          : (t.type == TxnType.invest ? 1 : -1);
      if (dir > 0) {
        inThisMonth += t.amount;
      } else {
        outThisMonth += t.amount;
      }
    }

    final Widget header;
    if (account != null) {
      header = HeroPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HeroFigure(
              tr('Balance'),
              formatRupees(l.accountBalance(account.id)),
              big: true,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: HeroFigure(
                    tr('In this month'),
                    formatRupees(inThisMonth),
                  ),
                ),
                Expanded(
                  child: HeroFigure(
                    tr('Out this month'),
                    formatRupees(outThisMonth),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else if (card != null) {
      final s = l.cardStatus(card, now);
      header = HeroPanel(
        colors: const [Color(0xFF111827), Color(0xFF374151)],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HeroFigure(
              tr('Outstanding'),
              formatRupees(s.outstanding),
              big: true,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: HeroFigure(
                    tr('Spent this month'),
                    formatRupees(outThisMonth),
                  ),
                ),
                Expanded(
                  child: HeroFigure(
                    s.amountDue > 0
                        ? tr('Due {0}', [dayMonth(s.dueDate)])
                        : tr('Bill'),
                    formatRupees(s.amountDue),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => showPayBillSheet(context, card),
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(tr('Pay bill')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    onPressed: () => showQuickAdd(context),
                    icon: const Icon(Icons.add),
                    label: Text(tr('Add spend')),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      final s = l.investmentSummary(investment!, now);
      header = HeroPanel(
        colors: const [Color(0xFF0F172A), Color(0xFF1E3A8A)],
        child: Row(
          children: [
            Expanded(
              child: HeroFigure(tr('Invested'), formatRupees(s.netInvested)),
            ),
            Expanded(
              child: HeroFigure(
                tr('Current value'),
                s.currentValue == null
                    ? tr('Not set')
                    : formatRupees(s.currentValue!),
              ),
            ),
          ],
        ),
      );
    }

    // Entries grouped by day, newest first.
    final children = <Widget>[];
    DateTime? day;
    for (final t in txns) {
      if (t.date != day) {
        day = t.date;
        children.add(_DayHeader(date: t.date));
      }
      children.add(
        TxnTile(
          t,
          showDate: false,
          balanceAfter: balances[t.id],
          balanceLabel: card != null ? 'Owed' : 'Bal',
          onTap: () => showQuickAdd(context, initial: t),
        ),
      );
    }
    final opening = account?.openingBalance ?? card?.openingOutstanding;
    final since = account?.since ?? card?.since;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: tr('Edit'),
            onPressed: () => _edit(context),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete(context, title);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text(tr('Delete')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          header,
          if (account != null)
            if (context.store.balanceHints[account.id] case final hint?)
              if (hint.balance != l.accountBalance(account.id, asOf: hint.date))
                Panel(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        tr(
                          'Your bank said the balance was {0} on {1}; Rupio shows {2}.',
                          [
                            formatRupees(hint.balance),
                            shortDate(hint.date),
                            formatRupees(
                              l.accountBalance(account.id, asOf: hint.date),
                            ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () =>
                              context.store.acceptBankBalance(account.id),
                          child: Text(tr('Use bank balance')),
                        ),
                      ),
                    ],
                  ),
                ),
          if (txns.isEmpty)
            EmptyState(
              icon: Icons.receipt_long,
              message: tr('No transactions yet.'),
            )
          else
            Panel(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...children,
                  if (opening != null)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.flag_outlined),
                      title: Text(
                        card != null
                            ? tr('Opening amount owed')
                            : tr('Opening balance'),
                      ),
                      subtitle: since == null ? null : Text(shortDate(since)),
                      trailing: Text(
                        formatRupees(opening),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        relativeDate(date) == shortDate(date)
            ? '${_weekday(date)}, ${shortDate(date)}'
            : '${relativeDate(date)} · ${shortDate(date)}',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String _weekday(DateTime d) => tr(_weekdays[d.weekday - 1]);
