import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../ledger/ledger.dart';
import '../models/goals.dart';
import '../models/models.dart';
import '../models/money.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import '../l10n/strings.dart';

/// Home, car, personal and other loans paid back in EMIs.
class LoansScreen extends StatelessWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.ledger;
    final now = today();
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final statuses = [for (final x in l.loans) l.loanStatus(x, now)]
      ..sort((a, b) => a.finished == b.finished ? 0 : (a.finished ? 1 : -1));

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Loans & EMIs')),
        actions: [
          if (statuses.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: tr('Add loan'),
              onPressed: () => showLoanForm(context),
            ),
        ],
      ),
      body: statuses.isEmpty
          ? IntroState(
              title: tr('Every EMI,'),
              accent: tr('tracked.'),
              accentColor: kCoral,
              points: [
                tr('See what you pay in EMIs each month'),
                tr('Know how many EMIs are left'),
                tr('Get a reminder before each due date'),
              ],
              actionLabel: tr('Add a loan'),
              onAction: () => showLoanForm(context),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    tr('EMIs per month'),
                    style: t.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    formatRupees(l.monthlyEmi(now)),
                    style: t.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: kCoral,
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    tr('{0} left to pay', [
                      formatRupees(l.loansRemaining(now)),
                    ]),
                    style: t.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _PayoffPanel(now: now),
                for (final s in statuses) _LoanCard(status: s),
              ],
            ),
    );
  }
}

String monthYear(DateTime d) {
  final m = [
    tr('Jan'), tr('Feb'), tr('Mar'), tr('Apr'), tr('May'), tr('Jun'), //
    tr('Jul'), tr('Aug'), tr('Sep'), tr('Oct'), tr('Nov'), tr('Dec'),
  ];
  return '${tr(m[d.month - 1])} ${d.year}';
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({required this.status});
  final LoanStatus status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final loan = s.loan;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = t.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final next = s.nextDue;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loan.name, style: t.titleMedium),
                    if (loan.lender.isNotEmpty) Text(loan.lender, style: muted),
                  ],
                ),
              ),
              Text(
                formatRupees(loan.emi),
                style: t.titleMedium?.copyWith(
                  color: s.finished ? scheme.onSurfaceVariant : kCoral,
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  final store = context.store;
                  switch (v) {
                    case 'edit':
                      await showLoanForm(context, edit: loan);
                    case 'close':
                      await store.saveLoan(loan.copyWith(closed: !loan.closed));
                    case 'delete':
                      final ok = await confirmDelete(
                        context,
                        tr('Delete {0}?', [loan.name]),
                        tr('EMIs already recorded stay in your expenses.'),
                      );
                      if (ok) await store.deleteLoan(loan.id);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(tr('Edit'))),
                  PopupMenuItem(
                    value: 'close',
                    child: Text(
                      loan.closed ? tr('Reopen') : tr('Mark as closed'),
                    ),
                  ),
                  PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Meter(value: s.progress, color: scheme.moneyIn, height: 8),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                tr('{0}% paid', [(s.progress * 100).round()]),
                style: muted?.copyWith(color: scheme.moneyIn),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('{0} of {1} EMIs paid', [s.emisPaid, loan.tenureMonths]),
                  style: muted,
                ),
              ),
              Text(
                s.finished
                    ? tr('Closed')
                    : tr('Ends {0}', [monthYear(loan.lastEmiDate)]),
                style: muted,
              ),
            ],
          ),
          if (!s.finished && next != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Next EMI'), style: muted),
                      Text(
                        s.paidThisMonth
                            ? tr('{0} · paid this month', [shortDate(next)])
                            : shortDate(next),
                        style: t.titleSmall,
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () => showPayEmi(context, loan),
                  child: Text(tr('Pay EMI')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

Future<bool> confirmDelete(
  BuildContext context,
  String title,
  String message,
) async =>
    (await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    )) ??
    false;

/// Records one EMI from an account.
Future<void> showPayEmi(BuildContext context, Loan loan) =>
    showDialog<void>(context: context, builder: (_) => _PayEmiDialog(loan));

class _PayEmiDialog extends StatefulWidget {
  const _PayEmiDialog(this.loan);
  final Loan loan;

  @override
  State<_PayEmiDialog> createState() => _PayEmiDialogState();
}

class _PayEmiDialogState extends State<_PayEmiDialog> {
  final _amount = TextEditingController();
  int? _account;
  DateTime _date = today();
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount.text = amountText(widget.loan.emi);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final accounts = context.ledger.accounts;
    _account ??= accounts.any((a) => a.id == widget.loan.accountId)
        ? widget.loan.accountId
        : accounts.isEmpty
        ? null
        : accounts.first.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseRupees(_amount.text);
    if (amount == null || amount <= 0) {
      return setState(() => _error = tr('Enter a valid amount'));
    }
    if (_account == null) {
      return setState(() => _error = tr('Add a bank account first'));
    }
    final errors = await context.store.payEmi(
      widget.loan,
      accountId: _account!,
      date: _date,
      amount: amount,
    );
    if (errors.isNotEmpty) return setState(() => _error = errors.first);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.ledger.accounts;
    return AlertDialog(
      title: Text(tr('Pay EMI · {0}', [widget.loan.name])),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AmountField(controller: _amount, label: tr('Amount')),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _account,
            decoration: InputDecoration(labelText: tr('Paid from')),
            items: [
              for (final a in accounts)
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => setState(() => _account = v),
          ),
          const SizedBox(height: 12),
          DateButton(
            label: tr('Date'),
            date: _date,
            onChanged: (d) => setState(() => _date = d),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancel')),
        ),
        FilledButton(onPressed: _save, child: Text(tr('Record'))),
      ],
    );
  }
}

/// Outlined row that opens a date picker.
class DateButton extends StatelessWidget {
  const DateButton({
    super.key,
    required this.label,
    required this.date,
    required this.onChanged,
    this.optional = false,
  });
  final String label;
  final DateTime? date;
  final ValueChanged<DateTime> onChanged;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        final now = today();
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? now,
          firstDate: DateTime(now.year - 30),
          lastDate: DateTime(now.year + 40),
        );
        if (picked != null) onChanged(dateOnly(picked));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(
          date == null ? (optional ? tr('None') : '') : shortDate(date!),
        ),
      ),
    );
  }
}

Future<void> showLoanForm(BuildContext context, {Loan? edit}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _LoanForm(edit: edit),
    );

class _LoanForm extends StatefulWidget {
  const _LoanForm({this.edit});
  final Loan? edit;

  @override
  State<_LoanForm> createState() => _LoanFormState();
}

class _LoanFormState extends State<_LoanForm> {
  final _name = TextEditingController();
  final _lender = TextEditingController();
  final _emi = TextEditingController();
  final _tenure = TextEditingController();
  final _paid = TextEditingController();
  final _principal = TextEditingController();
  final _rate = TextEditingController();
  DateTime _first = today();
  int? _account;
  bool _paidEdited = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    if (e != null) {
      _name.text = e.name;
      _lender.text = e.lender;
      _emi.text = amountText(e.emi);
      _tenure.text = '${e.tenureMonths}';
      _paid.text = '${e.paidBefore}';
      if (e.principal > 0) _principal.text = amountText(e.principal);
      if (e.interestRate != null) _rate.text = '${e.interestRate}';
      _first = e.firstEmiDate;
      _account = e.accountId;
      _paidEdited = true;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _lender, _emi, _tenure, _paid, _principal, _rate]) {
      c.dispose();
    }
    super.dispose();
  }

  /// EMIs whose date is already past, as a starting guess for "already paid".
  void _suggestPaid() {
    if (_paidEdited) return;
    final probe = Loan(
      id: 0,
      name: '',
      emi: 0,
      tenureMonths: int.tryParse(_tenure.text) ?? 0,
      firstEmiDate: _first,
    );
    final t = today();
    var n = 0;
    while (n < probe.tenureMonths && probe.emiDate(n).isBefore(t)) {
      n++;
    }
    _paid.text = n == 0 ? '' : '$n';
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final emi = parseRupees(_emi.text);
    final tenure = int.tryParse(_tenure.text.trim());
    final paid = _paid.text.trim().isEmpty
        ? 0
        : int.tryParse(_paid.text.trim());
    final principal = _principal.text.trim().isEmpty
        ? 0
        : parseRupees(_principal.text);
    final rate = _rate.text.trim().isEmpty
        ? null
        : double.tryParse(_rate.text.trim());
    if (name.isEmpty) return setState(() => _error = tr('Enter a name'));
    if (emi == null || emi <= 0) {
      return setState(() => _error = tr('Enter the EMI amount'));
    }
    if (tenure == null || tenure <= 0 || tenure > 600) {
      return setState(() => _error = tr('Enter the number of EMIs'));
    }
    if (paid == null || paid < 0 || paid > tenure) {
      return setState(() => _error = tr('EMIs already paid is not valid'));
    }
    if (principal == null) {
      return setState(() => _error = tr('Enter a valid loan amount'));
    }
    await context.store.saveLoan(
      Loan(
        id: widget.edit?.id ?? 0,
        name: name,
        lender: _lender.text.trim(),
        principal: principal,
        emi: emi,
        interestRate: rate,
        tenureMonths: tenure,
        firstEmiDate: _first,
        paidBefore: paid,
        accountId: _account,
        closed: widget.edit?.closed ?? false,
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.ledger.accounts;
    Widget gap() => const SizedBox(height: 12);
    return AlertDialog(
      title: Text(widget.edit == null ? tr('Add loan') : tr('Edit loan')),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: widget.edit == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tr('Name'),
              hintText: tr('e.g. Home loan, Bike, Phone EMI'),
            ),
          ),
          gap(),
          TextField(
            controller: _lender,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: tr('Bank or lender (optional)'),
            ),
          ),
          gap(),
          AmountField(controller: _emi, label: tr('EMI per month')),
          gap(),
          TextField(
            controller: _tenure,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(_suggestPaid),
            decoration: InputDecoration(
              labelText: tr('Total number of EMIs'),
              hintText: tr('e.g. 36'),
            ),
          ),
          gap(),
          DateButton(
            label: tr('First EMI date'),
            date: _first,
            onChanged: (d) => setState(() {
              _first = d;
              _suggestPaid();
            }),
          ),
          gap(),
          TextField(
            controller: _paid,
            keyboardType: TextInputType.number,
            onChanged: (_) => _paidEdited = true,
            decoration: InputDecoration(
              labelText: tr('EMIs already paid'),
              hintText: '0',
            ),
          ),
          gap(),
          DropdownButtonFormField<int?>(
            initialValue: accounts.any((a) => a.id == _account)
                ? _account
                : null,
            decoration: InputDecoration(labelText: tr('Usually paid from')),
            items: [
              DropdownMenuItem<int?>(
                value: null,
                child: Text(tr('Choose later')),
              ),
              for (final a in accounts)
                DropdownMenuItem<int?>(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => setState(() => _account = v),
          ),
          gap(),
          AmountField(
            controller: _principal,
            label: tr('Loan amount (optional)'),
          ),
          gap(),
          TextField(
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: tr('Interest rate % (optional)'),
            ),
          ),
          if (_error != null) ...[
            gap(),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancel')),
        ),
        FilledButton(onPressed: _save, child: Text(tr('Save'))),
      ],
    );
  }
}

/// Empty-screen introduction: a two-line headline with an accent word, a
/// short list of what the screen does, and one action.
class IntroState extends StatelessWidget {
  const IntroState({
    super.key,
    required this.title,
    required this.accent,
    required this.accentColor,
    required this.points,
    required this.actionLabel,
    required this.onAction,
    this.note,
  });

  final String title;
  final String accent;
  final Color accentColor;
  final List<String> points;
  final String actionLabel;
  final VoidCallback onAction;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
      children: [
        Text.rich(
          TextSpan(
            text: '$title\n',
            children: [
              TextSpan(
                text: accent,
                style: TextStyle(color: accentColor),
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              for (var i = 0; i < points.length; i++) ...[
                if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          points[i],
                          style: t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w400,
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
        if (note != null) ...[
          const SizedBox(height: 20),
          Text(
            note!,
            textAlign: TextAlign.center,
            style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 24),
        Center(
          child: TextButton.icon(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: accentColor),
            icon: const Icon(Icons.add),
            label: Text(
              actionLabel,
              style: t.titleMedium?.copyWith(color: accentColor),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bars of what is left to pay, month by month (or year by year for long
/// loans), ending on the debt-free date.
class _PayoffPanel extends StatelessWidget {
  const _PayoffPanel({required this.now});
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l = context.ledger;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final payoff = l.loanPayoff(now);
    final free = l.debtFreeMonth(now);
    if (payoff.length < 2 || free == null) return const SizedBox.shrink();
    final yearly = payoff.length > 36;
    final points = yearly
        ? [
            payoff.first,
            for (final p in payoff.skip(1))
              if (p.$1.month == 1) p,
          ]
        : payoff;
    final english = currentLanguage == 'en';
    const letters = [
      'J',
      'F',
      'M',
      'A',
      'M',
      'J',
      'J',
      'A',
      'S',
      'O',
      'N',
      'D',
    ];
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Debt-free by {0}', [monthYear(free)]), style: t.titleMedium),
          const SizedBox(height: 2),
          Text(
            yearly
                ? tr('Each bar is what is left to pay at the start of a year.')
                : tr(
                    'Each bar is what is left to pay at the start of a month.',
                  ),
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          PeriodBars(
            values: [for (final p in points) p.$2],
            labels: [
              for (final p in points)
                yearly
                    ? "'${'${p.$1.year}'.substring(2)}"
                    : (english ? letters[p.$1.month - 1] : '${p.$1.month}'),
            ],
            tooltipLabels: [for (final p in points) monthYear(p.$1)],
            highlight: 0,
            labelEvery: points.length > 18 ? 3 : (points.length > 8 ? 2 : 1),
            color: kCoral,
            height: 150,
          ),
        ],
      ),
    );
  }
}
