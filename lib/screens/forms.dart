import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../models/models.dart';
import '../models/money.dart';
import '../widgets/common.dart';
import 'loans_screen.dart' show DateButton;
import '../l10n/strings.dart';

/// Asks for a single line of text.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(tr('Add')),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

Future<void> showAddAccountDialog(
  BuildContext context, {
  String? name,
  String? lastFour,
  Paise? balance,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _AccountForm(name: name, lastFour: lastFour, balance: balance),
);

Future<void> showEditAccountDialog(BuildContext context, Account a) =>
    showDialog<void>(
      context: context,
      builder: (_) => _AccountForm(edit: a),
    );

/// [availableLimit] (from a bank message) lets the form work out the amount
/// owed once the user enters the credit limit.
Future<void> showAddCardDialog(
  BuildContext context, {
  String? name,
  String? lastFour,
  Paise? availableLimit,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _CardForm(name: name, lastFour: lastFour, availableLimit: availableLimit),
);

Future<void> showEditCardDialog(BuildContext context, CreditCard c) =>
    showDialog<void>(
      context: context,
      builder: (_) => _CardForm(edit: c),
    );

Future<Investment?> showAddInvestmentDialog(BuildContext context) =>
    showDialog<Investment>(
      context: context,
      builder: (_) => const _InvestmentForm(),
    );

Future<void> showEditInvestmentDialog(BuildContext context, Investment inv) =>
    showDialog<void>(
      context: context,
      builder: (_) => _InvestmentForm(edit: inv),
    );

Future<void> showUpdateValueDialog(BuildContext context, Investment inv) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ValueForm(investment: inv),
    );

/// Shared dialog frame with Cancel / Save and an error line.
class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.title,
    required this.children,
    required this.onSave,
    this.error,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in children) ...[c, const SizedBox(height: 12)],
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancel')),
        ),
        FilledButton(onPressed: onSave, child: Text(tr('Save'))),
      ],
    );
  }
}

/// Parses an optional amount: empty means zero.
Paise? _optionalAmount(String text) =>
    text.trim().isEmpty ? 0 : parseRupees(text);

class _AccountForm extends StatefulWidget {
  const _AccountForm({this.edit, this.name, this.lastFour, this.balance});
  final Account? edit;
  final String? name;
  final String? lastFour;
  final Paise? balance;

  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  final _name = TextEditingController();
  final _opening = TextEditingController();
  final _last4 = TextEditingController();
  AccountKind _kind = AccountKind.savings;
  String? _error;

  @override
  void initState() {
    super.initState();
    final a = widget.edit;
    if (a != null) {
      _name.text = a.name;
      _kind = a.kind;
      _last4.text = a.lastFour;
    } else {
      _name.text = widget.name ?? '';
      _last4.text = widget.lastFour ?? '';
      if (widget.balance != null) _opening.text = amountText(widget.balance!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final a = widget.edit;
    if (a != null && _opening.text.isEmpty) {
      _opening.text = amountText(context.ledger.accountBalance(a.id));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    _last4.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final last4 = _last4.text.trim();
    final balance = _opening.text.trim().isEmpty
        ? 0
        : parseSignedRupees(_opening.text);
    if (name.isEmpty) return setState(() => _error = tr('Enter a name'));
    if (balance == null) {
      return setState(() => _error = tr('Enter a valid balance'));
    }
    if (last4.isNotEmpty && !RegExp(r'^\d{3,6}$').hasMatch(last4)) {
      return setState(
        () => _error = tr('Account digits must be 3 to 6 numbers'),
      );
    }
    final a = widget.edit;
    if (a == null) {
      await context.store.addAccount(name, _kind, balance, lastFour: last4);
    } else {
      await context.store.updateAccount(
        a,
        name: name,
        kind: _kind,
        lastFour: last4,
        currentBalance: balance,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: widget.edit == null ? tr('Add account') : tr('Edit account'),
      error: _error,
      onSave: _save,
      children: [
        SegmentedButton<AccountKind>(
          segments: [
            for (final k in AccountKind.values)
              ButtonSegment(
                value: k,
                icon: Icon(iconForAccount(k)),
                tooltip: k.label,
                label: Text(switch (k) {
                  AccountKind.savings => tr('Bank'),
                  AccountKind.cash => tr('Cash'),
                  AccountKind.wallet => tr('Wallet'),
                }),
              ),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: tr('Name'),
            hintText: switch (_kind) {
              AccountKind.savings => tr('e.g. SBI Savings'),
              AccountKind.cash => tr('e.g. Cash'),
              AccountKind.wallet => tr('e.g. Paytm wallet'),
            },
          ),
        ),
        AmountField(controller: _opening, label: tr('Current balance')),
        if (_kind == AccountKind.savings)
          TextField(
            controller: _last4,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: tr('Last 4 digits of account (optional)'),
              helperText: tr('Lets Rupio match bank SMS to this account'),
              counterText: '',
            ),
          ),
        if (widget.edit != null)
          Text(
            tr(
              'Changing the balance keeps all transactions; the starting balance is adjusted so the total matches.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _CardForm extends StatefulWidget {
  const _CardForm({this.edit, this.name, this.lastFour, this.availableLimit});
  final CreditCard? edit;
  final String? name;
  final String? lastFour;
  final Paise? availableLimit;

  @override
  State<_CardForm> createState() => _CardFormState();
}

class _CardFormState extends State<_CardForm> {
  final _name = TextEditingController();
  final _last4 = TextEditingController();
  final _limit = TextEditingController();
  final _outstanding = TextEditingController();
  int _statementDay = 15;
  int _dueDay = 5;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.edit;
    if (c != null) {
      _name.text = c.name;
      _last4.text = c.lastFour;
      _limit.text = amountText(c.creditLimit);
      _statementDay = c.statementDay;
      _dueDay = c.dueDay;
    } else {
      _name.text = widget.name ?? '';
      _last4.text = widget.lastFour ?? '';
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = widget.edit;
    if (c != null && _outstanding.text.isEmpty) {
      _outstanding.text = amountText(context.ledger.cardOutstanding(c.id));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _last4, _limit, _outstanding]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final last4 = _last4.text.trim();
    final limit = parseRupees(_limit.text);
    var outstanding = _optionalAmount(_outstanding.text);
    // Owed = limit − what the bank says is still available.
    final avl = widget.availableLimit;
    if (_outstanding.text.trim().isEmpty && avl != null && limit != null) {
      outstanding = limit > avl ? limit - avl : 0;
    }
    if (name.isEmpty) return setState(() => _error = tr('Enter the card name'));
    if (last4.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(last4)) {
      return setState(() => _error = tr('Last four digits must be 4 numbers'));
    }
    if (limit == null || limit <= 0) {
      return setState(() => _error = tr('Enter the credit limit'));
    }
    if (outstanding == null) {
      return setState(() => _error = tr('Enter a valid outstanding amount'));
    }
    final c = widget.edit;
    if (c == null) {
      await context.store.addCard(
        name: name,
        lastFour: last4,
        creditLimit: limit,
        statementDay: _statementDay,
        dueDay: _dueDay,
        openingOutstanding: outstanding,
      );
    } else {
      await context.store.updateCard(
        c,
        name: name,
        lastFour: last4,
        creditLimit: limit,
        statementDay: _statementDay,
        dueDay: _dueDay,
        currentOutstanding: outstanding,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Widget _dayPicker(String label, int value, ValueChanged<int> onChanged) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (var d = 1; d <= 31; d++)
          DropdownMenuItem(
            value: d,
            child: Text(d == 31 ? tr('31 / last') : '$d'),
          ),
      ],
      onChanged: (v) => setState(() => onChanged(v!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: widget.edit == null ? tr('Add credit card') : tr('Edit card'),
      error: _error,
      onSave: _save,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: tr('Card name'),
            hintText: tr('e.g. HDFC Millennia'),
          ),
        ),
        TextField(
          controller: _last4,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: InputDecoration(
            labelText: tr('Last 4 digits (optional)'),
            counterText: '',
          ),
        ),
        AmountField(controller: _limit, label: tr('Credit limit')),
        Row(
          children: [
            Expanded(
              child: _dayPicker(
                tr('Statement day'),
                _statementDay,
                (v) => _statementDay = v,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _dayPicker(tr('Due day'), _dueDay, (v) => _dueDay = v),
            ),
          ],
        ),
        AmountField(
          controller: _outstanding,
          label: widget.edit == null
              ? tr('Amount owed now (optional)')
              : tr('Amount owed now'),
        ),
        if (widget.availableLimit != null)
          Text(
            tr(
              'Your bank last reported {0} available. Leave "amount owed" empty and it is worked out from the limit.',
              [formatRupees(widget.availableLimit!)],
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _InvestmentForm extends StatefulWidget {
  const _InvestmentForm({this.edit});
  final Investment? edit;

  @override
  State<_InvestmentForm> createState() => _InvestmentFormState();
}

class _InvestmentFormState extends State<_InvestmentForm> {
  final _name = TextEditingController();
  final _invested = TextEditingController();
  final _value = TextEditingController();
  DateTime? _investedOn;
  InvestmentType _type = InvestmentType.mutualFund;
  String? _error;

  @override
  void initState() {
    super.initState();
    final inv = widget.edit;
    if (inv != null) {
      _name.text = inv.name;
      _type = inv.type;
      if (inv.openingInvested > 0) {
        _invested.text = amountText(inv.openingInvested);
        _investedOn = inv.openingDate;
      }
      if (inv.currentValue != null) {
        _value.text = amountText(inv.currentValue!);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _invested.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = tr('Enter a name'));
    final invested = _optionalAmount(_invested.text);
    if (invested == null) {
      return setState(() => _error = tr('Enter a valid amount invested'));
    }
    final value = _value.text.trim().isEmpty ? null : parseRupees(_value.text);
    if (_value.text.trim().isNotEmpty && value == null) {
      return setState(() => _error = tr('Enter a valid current value'));
    }
    if (invested > 0 && _investedOn == null) {
      return setState(
        () => _error = tr('Choose when you started investing this amount'),
      );
    }
    final edit = widget.edit;
    if (edit != null) {
      await context.store.updateInvestment(
        edit,
        name,
        _type,
        invested: invested,
        value: value,
        investedOn: _investedOn,
      );
      if (mounted) Navigator.pop(context);
      return;
    }
    final inv = await context.store.addInvestment(
      name,
      _type,
      invested: invested,
      value: value,
      investedOn: _investedOn,
    );
    if (mounted) Navigator.pop(context, inv);
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: widget.edit == null ? tr('Add investment') : tr('Edit investment'),
      error: _error,
      onSave: _save,
      children: [
        DropdownButtonFormField<InvestmentType>(
          initialValue: _type,
          decoration: InputDecoration(labelText: tr('Type')),
          items: [
            for (final t in InvestmentType.values)
              DropdownMenuItem(value: t, child: Text(t.label)),
          ],
          onChanged: (v) => setState(() => _type = v!),
        ),
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: tr('Name'),
            hintText: tr('e.g. Nifty 50 index fund'),
          ),
        ),
        AmountField(
          controller: _invested,
          label: widget.edit == null
              ? tr('Amount invested so far (optional)')
              : tr('Invested before adding it here'),
        ),
        DateButton(
          label: tr('Started investing on'),
          date: _investedOn,
          optional: true,
          onChanged: (d) => setState(() => _investedOn = d),
        ),
        AmountField(controller: _value, label: tr('Current value (optional)')),
        Text(
          tr(
            'Already invested? Enter the total you have put in and today\'s value (from your passbook, fund statement or app) to see your gain straight away. Add new money later with “Invest”; it is kept out of your spending.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ValueForm extends StatefulWidget {
  const _ValueForm({required this.investment});
  final Investment investment;

  @override
  State<_ValueForm> createState() => _ValueFormState();
}

class _ValueFormState extends State<_ValueForm> {
  final _value = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    final v = widget.investment.currentValue;
    if (v != null) {
      _value.text = (v / 100).toStringAsFixed(v % 100 == 0 ? 0 : 2);
    }
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = parseRupees(_value.text);
    if (value == null) {
      return setState(() => _error = tr('Enter a valid value'));
    }
    await context.store.updateInvestmentValue(
      widget.investment,
      value,
      today(),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: tr('Current value'),
      error: _error,
      onSave: _save,
      children: [
        Text(
          widget.investment.name,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        AmountField(
          controller: _value,
          label: tr('Value today'),
          autofocus: true,
        ),
        Text(
          tr(
            'Check your fund statement, broker app or passbook. This is your own figure, not a live market price.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
