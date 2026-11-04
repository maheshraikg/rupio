import 'package:flutter/material.dart';

import '../app/native.dart';
import '../app/scope.dart';
import '../models/models.dart';
import '../models/money.dart';
import '../widgets/design.dart';
import 'quick_add_sheet.dart';
import '../l10n/strings.dart';

class PaymentApp {
  const PaymentApp(this.name, this.package, this.icon, this.color);
  final String name;
  final String package;
  final IconData icon;
  final Color color;
}

/// Apps people in India commonly pay card bills with.
const paymentApps = [
  PaymentApp(
    'CRED',
    'com.dreamplug.androidapp',
    Icons.diamond_outlined,
    Color(0xFF1C1C1C),
  ),
  PaymentApp(
    'PhonePe',
    'com.phonepe.app',
    Icons.phone_android,
    Color(0xFF5F259F),
  ),
  PaymentApp(
    'Google Pay',
    'com.google.android.apps.nbu.paisa.user',
    Icons.g_mobiledata,
    Color(0xFF1A73E8),
  ),
  PaymentApp(
    'Paytm',
    'net.one97.paytm',
    Icons.account_balance_wallet,
    Color(0xFF00B9F1),
  ),
  PaymentApp(
    'Amazon Pay',
    'in.amazon.mShop.android.shopping',
    Icons.shopping_cart_outlined,
    Color(0xFFFF9900),
  ),
  PaymentApp(
    'BHIM',
    'in.org.npci.upiapp',
    Icons.currency_rupee,
    Color(0xFF00897B),
  ),
  PaymentApp('MobiKwik', 'com.mobikwik_new', Icons.wallet, Color(0xFF2B6CB0)),
];

/// "Pay bill": open a payment app of the user's choice, then record the
/// payment here when they come back.
Future<void> showPayBillSheet(BuildContext context, CreditCard card) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PayBillSheet(card: card),
  );
}

class _PayBillSheet extends StatefulWidget {
  const _PayBillSheet({required this.card});
  final CreditCard card;

  @override
  State<_PayBillSheet> createState() => _PayBillSheetState();
}

class _PayBillSheetState extends State<_PayBillSheet> {
  Set<String> _installed = const {};
  PaymentApp? _opened;

  @override
  void initState() {
    super.initState();
    _checkInstalled();
  }

  Future<void> _checkInstalled() async {
    final found = <String>{};
    for (final a in paymentApps) {
      if (await Native.isInstalled(a.package)) found.add(a.package);
    }
    if (mounted) setState(() => _installed = found);
  }

  Future<void> _open(PaymentApp app) async {
    final launched = await Native.openApp(app.package);
    if (!mounted) return;
    if (launched) setState(() => _opened = app);
  }

  void _record(Paise? amount) {
    final card = widget.card;
    Navigator.pop(context);
    showQuickAdd(
      context,
      type: TxnType.cardPayment,
      toCardId: card.id,
      amount: amount,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.ledger;
    final card = l.card(widget.card.id) ?? widget.card;
    final s = l.cardStatus(card, today());
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final apps = [...paymentApps]
      ..sort((a, b) {
        final ai = _installed.contains(a.package) ? 0 : 1;
        final bi = _installed.contains(b.package) ? 0 : 1;
        return ai.compareTo(bi);
      });

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Pay {0}', [card.displayName]), style: t.titleLarge),
          const SizedBox(height: 12),
          Panel(
            margin: EdgeInsets.zero,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Amount(
                    tr('Bill to pay'),
                    formatRupees(s.amountDue),
                    sub: s.amountDue > 0
                        ? tr('Due {0}', [dayMonth(s.dueDate)])
                        : null,
                  ),
                ),
                if (s.minDue != null)
                  Expanded(
                    child: _Amount(tr('Minimum due'), formatRupees(s.minDue!)),
                  ),
                Expanded(
                  child: _Amount(tr('Total owed'), formatRupees(s.outstanding)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(tr('Pay using'), style: t.titleSmall),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.82,
            children: [
              for (final app in apps)
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _open(app),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconBadge(app.icon, color: app.color, size: 48),
                      const SizedBox(height: 6),
                      Text(
                        app.name,
                        style: t.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _installed.contains(app.package) ? '' : tr('Get app'),
                        style: t.labelSmall?.copyWith(color: scheme.outline),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_opened != null)
            Panel(
              margin: const EdgeInsets.only(bottom: 12),
              color: scheme.primaryContainer,
              child: Text(
                tr(
                  'Paid in {0}? Record the payment so your card balance stays correct.',
                  [_opened!.name],
                ),
              ),
            ),
          FilledButton.icon(
            onPressed: () => _record(s.amountDue > 0 ? s.amountDue : null),
            icon: const Icon(Icons.check),
            label: Text(
              s.amountDue > 0
                  ? tr('Record {0} payment', [formatRupees(s.amountDue)])
                  : tr('Record a payment'),
            ),
          ),
          if (s.minDue != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _record(s.minDue),
              child: Text(tr('Record minimum {0}', [formatRupees(s.minDue!)])),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _record(null),
            child: Text(tr('Record a different amount')),
          ),
        ],
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount(this.label, this.value, {this.sub});
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.labelMedium),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (sub != null) Text(sub!, style: t.labelSmall),
      ],
    );
  }
}
