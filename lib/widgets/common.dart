import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../ledger/ledger.dart';
import '../models/models.dart';
import '../models/money.dart';
import 'design.dart';
import '../l10n/strings.dart';

/// Colours used for money direction, tuned for both themes.
extension MoneyColors on ColorScheme {
  /// Money coming in.
  Color get moneyIn =>
      brightness == Brightness.light ? Color(0xFF15803D) : Color(0xFF4ADE80);

  /// Money going out: shown in the normal text colour, so lists stay calm.
  Color get moneyOut => onSurface;

  /// Over budget, overdue and other problems.
  Color get danger => error;
}

final categoryIcons = <String, IconData>{
  'Food': Icons.restaurant_rounded,
  'Groceries': Icons.local_grocery_store_rounded,
  'Transport': Icons.directions_car_rounded,
  'Fuel': Icons.local_gas_station_rounded,
  'Shopping': Icons.shopping_bag_rounded,
  'Bills': Icons.receipt_long_rounded,
  'Rent': Icons.home_rounded,
  'Health': Icons.favorite_rounded,
  'Entertainment': Icons.movie_rounded,
  'Travel': Icons.flight_rounded,
  'Education': Icons.school_rounded,
  'EMI': Icons.event_repeat_rounded,
  'Other': Icons.category_rounded,
  'Salary': Icons.work_rounded,
  'Interest': Icons.savings_rounded,
  'Business': Icons.storefront_rounded,
  'Gift': Icons.redeem_rounded,
};

/// One calm colour per category, used for its icon everywhere.
final categoryColors = <String, Color>{
  'Food': Color(0xFFD9A441),
  'Groceries': Color(0xFF3EA585),
  'Transport': Color(0xFF5B7FD6),
  'Fuel': Color(0xFFC9925A),
  'Shopping': Color(0xFFC77A9A),
  'Bills': Color(0xFF8B7FC9),
  'Rent': Color(0xFF7A8FB0),
  'Health': Color(0xFFD9695B),
  'Entertainment': Color(0xFFB07CC0),
  'Travel': Color(0xFF4CA3B3),
  'Education': Color(0xFF6C8FC7),
  'EMI': Color(0xFFE0604F),
  'Other': Color(0xFF8A94A6),
  'Salary': Color(0xFF22A06B),
  'Interest': Color(0xFF3E9A8A),
  'Business': Color(0xFF4C93A8),
  'Gift': Color(0xFFC77A9A),
};

IconData iconForCategory(String? c) =>
    categoryIcons[c] ?? Icons.category_rounded;

Color colorForCategory(String? c) => categoryColors[c] ?? Color(0xFF64748B);

IconData iconForTxn(Txn t) => switch (t.type) {
  TxnType.transfer => Icons.swap_horiz_rounded,
  TxnType.cardPayment => Icons.credit_score_rounded,
  TxnType.invest => Icons.trending_up_rounded,
  TxnType.investWithdrawal => Icons.account_balance_wallet_rounded,
  TxnType.investIncome => Icons.payments_rounded,
  TxnType.refund => Icons.undo_rounded,
  _ => iconForCategory(t.category),
};

IconData iconForAccount(AccountKind k) => switch (k) {
  AccountKind.savings => Icons.account_balance_rounded,
  AccountKind.cash => Icons.payments_rounded,
  AccountKind.wallet => Icons.account_balance_wallet_rounded,
};

/// Accent colour for a transaction's icon: its category's colour, or a
/// neutral tone for moves between the user's own money.
Color colorForTxn(Txn t) => switch (t.type) {
  TxnType.expense ||
  TxnType.refund ||
  TxnType.income => colorForCategory(t.category),
  TxnType.investIncome => Color(0xFF059669),
  TxnType.invest || TxnType.investWithdrawal => kViolet,
  TxnType.transfer || TxnType.cardPayment => Color(0xFF64748B),
};

/// Title shown for a transaction in lists.
String txnTitle(Txn t, Ledger l) {
  if (t.note != null && t.note!.isNotEmpty) return t.note!;
  return switch (t.type) {
    TxnType.expense ||
    TxnType.income => t.category != null ? tr(t.category!) : t.type.label,
    TxnType.refund => tr('Refund · {0}', [tr(t.category ?? 'Other')]),
    TxnType.transfer => tr('Transfer'),
    TxnType.cardPayment => tr('Bill paid · {0}', [
      l.card(t.toCardId)?.name ?? tr('card'),
    ]),
    TxnType.invest => l.investment(t.investmentId)?.name ?? tr('Investment'),
    TxnType.investWithdrawal => tr('Withdrawn · {0}', [
      l.investment(t.investmentId)?.name ?? '',
    ]),
    TxnType.investIncome => tr('Income · {0}', [
      l.investment(t.investmentId)?.name ?? '',
    ]),
  };
}

/// "SBI Savings → HDFC Regalia" style description of where money moved.
String txnRoute(Txn t, Ledger l) {
  String? name({int? accountId, int? cardId}) =>
      l.account(accountId)?.name ?? l.card(cardId)?.displayName;
  final from =
      name(accountId: t.fromAccountId, cardId: t.fromCardId) ??
      (t.type == TxnType.investWithdrawal || t.type == TxnType.investIncome
          ? l.investment(t.investmentId)?.name
          : null);
  final to =
      name(accountId: t.toAccountId, cardId: t.toCardId) ??
      (t.type == TxnType.invest ? l.investment(t.investmentId)?.name : null);
  if (from != null && to != null) return '$from → $to';
  return from ?? to ?? (t.type == TxnType.investIncome ? tr('Reinvested') : '');
}

/// +1 money in, -1 money out, 0 moved between the user's own holdings.
int txnDirection(Txn t) => switch (t.type) {
  TxnType.expense => -1,
  TxnType.income || TxnType.refund || TxnType.investIncome => 1,
  _ => 0,
};

class TxnTile extends StatelessWidget {
  const TxnTile(
    this.txn, {
    super.key,
    this.onTap,
    this.showDate = true,
    this.balanceAfter,
    this.balanceLabel = 'Bal',
  });

  final Txn txn;
  final VoidCallback? onTap;
  final bool showDate;

  /// Running balance after this entry, shown under the amount.
  final Paise? balanceAfter;
  final String balanceLabel;

  @override
  Widget build(BuildContext context) {
    final l = context.ledger;
    final scheme = Theme.of(context).colorScheme;
    final dir = txnDirection(txn);
    final color = switch (dir) {
      1 => scheme.moneyIn,
      -1 => scheme.moneyOut,
      _ => scheme.onSurfaceVariant,
    };
    final sign = switch (dir) {
      1 => '+',
      -1 => '−',
      _ => '',
    };
    final route = txnRoute(txn, l);
    final subtitle = [
      if (route.isNotEmpty) route,
      if (showDate) relativeDate(txn.date),
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: IconBadge(iconForTxn(txn)),
      title: Row(
        children: [
          Flexible(
            child: Text(
              txnTitle(txn, l),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (txn.recurringId != null) ...[
            SizedBox(width: 6),
            Icon(Icons.event_repeat, size: 14, color: scheme.outline),
          ],
          if (txn.sourceKey != null) ...[
            SizedBox(width: 6),
            Tooltip(
              message: tr('From {0}', [txn.sourceLabel]),
              child: Icon(
                txn.sourceKey!.startsWith('sms')
                    ? Icons.sms_outlined
                    : txn.sourceKey!.startsWith('mail')
                    ? Icons.mail_outline
                    : Icons.description_outlined,
                size: 14,
                color: scheme.outline,
              ),
            ),
          ],
          if (txn.receiptPath != null) ...[
            SizedBox(width: 6),
            Icon(Icons.receipt_long, size: 14, color: scheme.outline),
          ],
        ],
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$sign${formatRupees(txn.amount)}',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
          if (balanceAfter != null)
            Text(
              '${tr(balanceLabel)} ${formatRupees(balanceAfter!)}',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// Small labelled figure used in summary rows.
class Figure extends StatelessWidget {
  const Figure(
    this.label,
    this.value, {
    super.key,
    this.color,
    this.large = false,
  });

  final String label;
  final String value;
  final Color? color;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: t.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: (large ? t.headlineSmall : t.titleMedium)?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?action,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.outline),
          SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (actionLabel != null) ...[
            SizedBox(height: 16),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
          ],
          if (secondaryLabel != null) ...[
            SizedBox(height: 8),
            TextButton.icon(
              onPressed: onSecondary,
              icon: Icon(Icons.auto_awesome, size: 18),
              label: Text(secondaryLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Text field for rupee amounts.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.label = 'Amount',
    this.autofocus = false,
    this.large = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final bool large;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (large) {
      // The hero of the add screen: a huge amount, centred with its ₹.
      final scheme = Theme.of(context).colorScheme;
      final big = Theme.of(context).textTheme.displayMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -1.5,
        color: scheme.onSurface,
      );
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('₹', style: big?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(width: 4),
          Flexible(
            child: IntrinsicWidth(
              child: TextField(
                controller: controller,
                autofocus: autofocus,
                onChanged: onChanged,
                style: big,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: '0',
                  hintStyle: big?.copyWith(color: scheme.outline),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: tr(label), prefixText: '₹ '),
    );
  }
}
