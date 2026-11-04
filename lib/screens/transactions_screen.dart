import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../ledger/ledger.dart';
import '../models/models.dart';
import '../models/money.dart';
import '../widgets/common.dart';
import '../widgets/swipe_delete.dart';
import 'quick_add_sheet.dart';
import '../l10n/strings.dart';

enum _Filter {
  all('All'),
  spending('Spending'),
  income('Income'),
  moves('Transfers & bills'),
  investments('Investments');

  const _Filter(this.label);
  final String label;

  bool matches(Txn t) => switch (this) {
    _Filter.all => true,
    _Filter.spending => t.type == TxnType.expense || t.type == TxnType.refund,
    _Filter.income => t.type == TxnType.income,
    _Filter.moves =>
      t.type == TxnType.transfer || t.type == TxnType.cardPayment,
    _Filter.investments =>
      t.type == TxnType.invest ||
          t.type == TxnType.investWithdrawal ||
          t.type == TxnType.investIncome,
  };
}

/// Searchable list of every transaction, grouped by day. Tap to edit, swipe
/// to delete (with undo).
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matchesSearch(Txn t, Ledger l, String q) {
    if (q.isEmpty) return true;
    final haystack = [
      txnTitle(t, l),
      txnRoute(t, l),
      t.category ?? '',
      t.note ?? '',
      t.type.label,
      formatRupees(t.amount),
      (t.amount ~/ 100).toString(),
    ].join(' ').toLowerCase();
    return q.split(RegExp(r'\s+')).every(haystack.contains);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final l = store.ledger;
    final q = _search.text.trim().toLowerCase();
    final items = l.txns
        .where((t) => _filter.matches(t) && _matchesSearch(t, l, q))
        .toList();

    final children = <Widget>[];
    DateTime? day;
    for (final t in items) {
      if (t.date != day) {
        day = t.date;
        final sameDay = items.where((x) => x.date == t.date);
        final spent = sameDay.fold(
          0,
          (s, x) => s + (txnDirection(x) < 0 ? x.amount : 0),
        );
        final scheme = Theme.of(context).colorScheme;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    relativeDate(t.date),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (spent > 0)
                  Text(
                    tr('Spent {0}', [formatRupees(spent)]),
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        );
      }
      children.add(
        SwipeToDelete(
          txn: t,
          hint: children.length == 1 && !store.swipeHintSeen,
          child: TxnTile(
            t,
            showDate: false,
            onTap: () => showQuickAdd(context, initial: t),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('Activity'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              controller: _search,
              hintText: tr('Search: petrol, 250, SBI…'),
              elevation: const WidgetStatePropertyAll(0),
              backgroundColor: WidgetStatePropertyAll(
                Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
              leading: const Icon(Icons.search),
              trailing: [
                if (q.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: tr('Clear'),
                    onPressed: () => setState(_search.clear),
                  ),
              ],
              onChanged: (_) => setState(() {}),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final f in _Filter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? EmptyState(
                    icon: Icons.search_off,
                    message: l.txns.isEmpty
                        ? tr('No transactions yet. Tap + to add one.')
                        : tr('Nothing matches.'),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 96),
                    children: children,
                  ),
          ),
        ],
      ),
    );
  }
}
