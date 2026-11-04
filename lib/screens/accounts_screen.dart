import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../ledger/ledger.dart';
import '../models/models.dart';
import '../models/money.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import 'forms.dart';
import 'holding_detail_screen.dart';
import 'quick_add_sheet.dart';
import '../l10n/strings.dart';

/// Bank accounts, cash and wallets with their balances.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.ledger;
    final now = today();
    final rate = l.savingsRate(monthStart(now), monthEnd(now));

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Accounts')),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: tr('Transfer between accounts'),
            onPressed: l.accounts.length < 2
                ? null
                : () => showQuickAdd(context, type: TxnType.transfer),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: tr('Add account'),
            onPressed: () => showAddAccountDialog(context),
          ),
        ],
      ),
      body: l.accounts.isEmpty
          ? EmptyState(
              icon: Icons.account_balance,
              message: tr(
                'Add your savings accounts (SBI, Canara Bank, …), cash in hand and UPI wallets.',
              ),
              actionLabel: tr('Add account'),
              onAction: () => showAddAccountDialog(context),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                HeroPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HeroFigure(
                        tr('Total balance'),
                        formatRupees(l.totalCash),
                        big: true,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: HeroFigure(
                              tr('Accounts'),
                              '${l.accounts.length}',
                            ),
                          ),
                          if (rate != null)
                            Expanded(
                              child: HeroFigure(
                                tr('Saved this month'),
                                '${rate.toStringAsFixed(0)}%',
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Panel(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      for (final a in l.accounts)
                        ListTile(
                          leading: IconBadge(iconForAccount(a.kind)),
                          title: Text(a.name),
                          subtitle: Text(a.kind.label),
                          trailing: Text(
                            formatRupees(l.accountBalance(a.id)),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          onLongPress: () => showEditAccountDialog(context, a),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => HoldingDetailScreen.account(a.id),
                            ),
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
