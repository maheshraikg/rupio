import 'dart:io';

import 'package:flutter/material.dart';

import '../app/files.dart';
import '../app/scope.dart';
import '../app/store.dart';
import '../models/models.dart';
import '../models/money.dart';
import '../models/planning.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import 'forms.dart';
import '../l10n/strings.dart';

/// Opens the quick entry sheet. Pass [initial] to edit an existing
/// transaction, or [type] / [toCardId] / [investmentId] to prefill a new one.
Future<void> showQuickAdd(
  BuildContext context, {
  Txn? initial,
  TxnType? type,
  int? toCardId,
  int? investmentId,
  int? amount,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => QuickAddSheet(
      initial: initial,
      type: type,
      toCardId: toCardId,
      investmentId: investmentId,
      amount: amount,
    ),
  );
}

/// Amount first, then one tap each for category and payment source, then
/// Save: a typical expense takes a few seconds.
class QuickAddSheet extends StatefulWidget {
  const QuickAddSheet({
    super.key,
    this.initial,
    this.type,
    this.toCardId,
    this.investmentId,
    this.amount,
  });

  final Txn? initial;
  final TxnType? type;
  final int? toCardId;
  final int? investmentId;
  final int? amount;

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late TxnType _type;
  String? _category;
  Source? _from;
  Source? _to;
  int? _investmentId;
  late DateTime _date;
  List<String> _errors = const [];
  bool _initialised = false;
  String? _receipt;
  Frequency? _repeat;
  bool _more = false;

  bool get _editing => widget.initial != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    final store = context.store;
    final t = widget.initial;
    if (t != null) {
      _type = t.type;
      _amount.text = formatRupees(t.amount).substring(1).replaceAll(',', '');
      _note.text = t.note ?? '';
      _category = t.category;
      _from = _sourceOf(t.fromAccountId, t.fromCardId);
      _to = _sourceOf(t.toAccountId, t.toCardId);
      _investmentId = t.investmentId;
      _date = t.date;
      _receipt = t.receiptPath;
      _more = !_simpleType || t.receiptPath != null || t.date != today();
    } else {
      _type = widget.type ?? TxnType.expense;
      if (widget.amount != null) {
        _amount.text = (widget.amount! / 100).toStringAsFixed(
          widget.amount! % 100 == 0 ? 0 : 2,
        );
      }
      _category = _type == TxnType.income
          ? incomeCategories.first
          : store.lastCategory;
      _from = _validSource(store.lastSource) ?? _defaultAccount();
      _to = widget.toCardId != null ? Source.card(widget.toCardId!) : null;
      _investmentId =
          widget.investmentId ??
          (store.ledger.investments.length == 1
              ? store.ledger.investments.first.id
              : null);
      _date = today();
      _adjustForType();
    }
  }

  static Source? _sourceOf(int? accountId, int? cardId) => accountId != null
      ? Source.account(accountId)
      : cardId != null
      ? Source.card(cardId)
      : null;

  Source? _validSource(Source? s) {
    if (s == null) return null;
    final l = context.ledger;
    if (s.accountId != null && l.account(s.accountId) != null) return s;
    if (s.cardId != null && l.card(s.cardId) != null) return s;
    return null;
  }

  Source? _defaultAccount() {
    final accounts = context.ledger.accounts;
    return accounts.isEmpty ? null : Source.account(accounts.first.id);
  }

  /// Keeps the selected from/to choices valid for the current type.
  void _adjustForType() {
    final l = context.ledger;
    final fromAccountOnly = switch (_type) {
      TxnType.transfer || TxnType.cardPayment => true,
      _ => false,
    };
    if (!_usesFrom) {
      _from = null;
    } else if (_from == null || (fromAccountOnly && _from!.cardId != null)) {
      _from = _defaultAccount();
    }
    switch (_type) {
      case TxnType.income || TxnType.investWithdrawal:
        if (_to?.accountId == null) _to = _defaultAccount();
      case TxnType.transfer:
        if (_to?.accountId == null || _to == _from) {
          final other = l.accounts.where((a) => Source.account(a.id) != _from);
          _to = other.isEmpty ? null : Source.account(other.first.id);
        }
      case TxnType.cardPayment:
        if (_to?.cardId == null && l.cards.isNotEmpty) {
          _to = Source.card(l.cards.first.id);
        }
      case TxnType.refund:
        _to ??= _from ?? _defaultAccount();
      case TxnType.investIncome:
        if (_to?.cardId != null) _to = null;
      case TxnType.expense || TxnType.invest:
        _to = null;
    }
    if (_type == TxnType.income) {
      if (!incomeCategories.contains(_category)) {
        _category = incomeCategories.first;
      }
    } else if (_usesCategory &&
        incomeCategories.contains(_category) &&
        !expenseCategories.contains(_category)) {
      _category = context.store.lastCategory;
    }
  }

  bool get _simpleType => _type == TxnType.expense || _type == TxnType.income;

  void _setType(TxnType t) => setState(() {
    _type = t;
    _errors = const [];
    _adjustForType();
  });

  bool get _usesCategory => switch (_type) {
    TxnType.expense || TxnType.income || TxnType.refund => true,
    _ => false,
  };

  bool get _usesFrom => switch (_type) {
    TxnType.expense ||
    TxnType.invest ||
    TxnType.transfer ||
    TxnType.cardPayment => true,
    _ => false,
  };

  bool get _usesInvestment => switch (_type) {
    TxnType.invest || TxnType.investWithdrawal || TxnType.investIncome => true,
    _ => false,
  };

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseRupees(_amount.text);
    if (amount == null) {
      setState(() => _errors = [tr('Enter a valid amount, e.g. 250 or 99.50')]);
      return;
    }
    final note = _note.text.trim();
    final txn = Txn(
      id: widget.initial?.id ?? 0,
      type: _type,
      amount: amount,
      date: _date,
      category: _usesCategory ? _category : null,
      note: note.isEmpty ? null : note,
      fromAccountId: _usesFrom ? _from?.accountId : null,
      fromCardId: _usesFrom ? _from?.cardId : null,
      toAccountId: _to?.accountId,
      toCardId: _to?.cardId,
      investmentId: _usesInvestment ? _investmentId : null,
      receiptPath: _receipt,
      recurringId: widget.initial?.recurringId,
    );
    final previousReceipt = widget.initial?.receiptPath;
    final errors = await context.store.saveTxn(txn, repeat: _repeat);
    if (!mounted) return;
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    // The old photo is no longer referenced once a new one replaced it.
    if (previousReceipt != null && previousReceipt != _receipt) {
      deleteReceipt(previousReceipt);
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _editing
              ? tr('Updated')
              : _repeat != null
              ? tr('{0} of {1} saved · {2}', [
                  _type.label,
                  formatRupees(amount),
                  _repeat!.label.toLowerCase(),
                ])
              : tr('{0} of {1} saved', [_type.label, formatRupees(amount)]),
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final t = widget.initial!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete this entry?')),
        content: Text(
          tr('{0} of {1} on {2}', [
            t.type.label,
            formatRupees(t.amount),
            relativeDate(t.date),
          ]),
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
    if (ok != true || !mounted) return;
    final store = context.store;
    final messenger = ScaffoldMessenger.of(context);
    await store.deleteTxn(t.id);
    if (!mounted) return;
    Navigator.pop(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(tr('Deleted {0}', [formatRupees(t.amount)])),
          action: SnackBarAction(
            label: tr('Undo'),
            onPressed: () => store.restoreTxn(t),
          ),
        ),
      );
  }

  Future<void> _addReceipt() async {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(tr('Take photo')),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(tr('Choose from gallery')),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (camera == null) return;
    try {
      final path = await captureReceipt(camera: camera);
      if (path != null && mounted) setState(() => _receipt = path);
    } catch (e) {
      if (mounted) {
        setState(
          () => _errors = [
            tr('Could not attach the photo: {0}', [e]),
          ],
        );
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: today().add(const Duration(days: 366)),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  Future<void> _newCategory() async {
    final name = await promptText(
      context,
      title: tr('New category'),
      label: tr('Name'),
    );
    if (name != null && name.isNotEmpty) setState(() => _category = name);
  }

  Future<void> _newInvestment() async {
    final inv = await showAddInvestmentDialog(context);
    if (inv != null) setState(() => _investmentId = inv.id);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.ledger;
    final scheme = Theme.of(context).colorScheme;

    if (l.accounts.isEmpty && l.cards.isEmpty) {
      return EmptyState(
        icon: Icons.account_balance,
        message: tr(
          'Add a bank account, cash or a credit card first so that Rupio knows where the money comes from.',
        ),
        actionLabel: tr('Add account'),
        onAction: () async {
          await showAddAccountDialog(context);
          if (context.mounted) setState(() => _adjustForType());
        },
      );
    }

    final categories = _type == TxnType.income
        ? incomeCategories
        : [
            ...expenseCategories,
            if (_category != null && !expenseCategories.contains(_category))
              _category!,
          ];

    // The form scrolls; Save stays pinned below it so it is always reachable
    // on short screens and above the keyboard.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_editing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        tr('Edit transaction'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  Center(
                    child: Toggle(
                      options: [tr('Expense'), tr('Income')],
                      selected: switch (_type) {
                        TxnType.expense => 0,
                        TxnType.income => 1,
                        _ => -1,
                      },
                      onChanged: (i) =>
                          _setType(i == 1 ? TxnType.income : TxnType.expense),
                    ),
                  ),
                  if (!_simpleType)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _type.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.primary),
                      ),
                    ),
                  const SizedBox(height: 20),
                  AmountField(
                    controller: _amount,
                    autofocus: !_editing && widget.amount == null,
                    large: true,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _note,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: tr('Description'),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                  if (_usesCategory) ...[
                    _Label(tr('Category')),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final c in categories)
                          ChoiceChip(
                            showCheckmark: false,
                            avatar: Icon(iconForCategory(c), size: 18),
                            label: Text(tr(c)),
                            selected: _category == c,
                            onSelected: (_) => setState(() => _category = c),
                          ),
                        if (_type != TxnType.income)
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 18),
                            label: Text(tr('New')),
                            onPressed: _newCategory,
                          ),
                      ],
                    ),
                  ],
                  if (_usesInvestment) ...[
                    _Label(tr('Investment')),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final inv in l.investments)
                          ChoiceChip(
                            label: Text(inv.name),
                            selected: _investmentId == inv.id,
                            onSelected: (_) =>
                                setState(() => _investmentId = inv.id),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 18),
                          label: Text(tr('New investment')),
                          onPressed: _newInvestment,
                        ),
                      ],
                    ),
                  ],
                  if (_usesFrom) ...[
                    _Label(
                      _type == TxnType.transfer ? tr('From') : tr('Paid from'),
                    ),
                    _SourceChips(
                      selected: _from,
                      includeCards:
                          _type == TxnType.expense || _type == TxnType.invest,
                      onSelected: (s) => setState(() => _from = s),
                    ),
                  ],
                  if (_type != TxnType.expense && _type != TxnType.invest) ...[
                    _Label(switch (_type) {
                      TxnType.cardPayment => tr('Card'),
                      TxnType.investIncome => tr(
                        'Paid into (leave empty if reinvested)',
                      ),
                      _ => tr('To'),
                    }),
                    _SourceChips(
                      selected: _to,
                      includeAccounts: _type != TxnType.cardPayment,
                      includeCards:
                          _type == TxnType.cardPayment ||
                          _type == TxnType.refund,
                      exclude: _type == TxnType.transfer ? _from : null,
                      onSelected: (s) => setState(
                        () => _to = (_type == TxnType.investIncome && s == _to)
                            ? null
                            : s,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => setState(() => _more = !_more),
                      icon: Icon(
                        _more ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                      ),
                      label: Text(
                        _more ? tr('Fewer details') : tr('More details'),
                      ),
                    ),
                  ),
                  if (_more) ...[
                    _Label(tr('Type')),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final t in TxnType.values)
                          ChoiceChip(
                            label: Text(t.label),
                            selected: _type == t,
                            onSelected: (_) => _setType(t),
                          ),
                      ],
                    ),
                    _Label(tr('Date')),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ActionChip(
                        avatar: const Icon(Icons.event, size: 18),
                        label: Text(relativeDate(_date)),
                        onPressed: _pickDate,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (_receipt == null)
                          ActionChip(
                            avatar: const Icon(Icons.receipt_long, size: 18),
                            label: Text(tr('Add receipt')),
                            onPressed: _addReceipt,
                          )
                        else
                          InputChip(
                            avatar: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.file(
                                File(_receipt!),
                                width: 24,
                                height: 24,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.broken_image, size: 18),
                              ),
                            ),
                            label: Text(tr('Receipt')),
                            onPressed: () => showReceipt(context, _receipt!),
                            onDeleted: () => setState(() => _receipt = null),
                          ),
                        if (widget.initial?.recurringId == null && !_editing)
                          PopupMenuButton<Frequency?>(
                            tooltip: tr('Repeat'),
                            initialValue: _repeat,
                            onSelected: (f) => setState(() => _repeat = f),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: null,
                                child: Text(tr('Does not repeat')),
                              ),
                              for (final f in Frequency.values)
                                PopupMenuItem(value: f, child: Text(f.label)),
                            ],
                            child: Chip(
                              avatar: Icon(
                                _repeat == null
                                    ? Icons.repeat
                                    : Icons.event_repeat,
                                size: 18,
                              ),
                              label: Text(_repeat?.label ?? 'Repeat'),
                              backgroundColor: _repeat == null
                                  ? null
                                  : scheme.secondaryContainer,
                            ),
                          ),
                        if (widget.initial?.recurringId != null)
                          Chip(
                            avatar: Icon(Icons.event_repeat, size: 18),
                            label: Text(tr('Recurring entry')),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in _errors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(e, style: TextStyle(color: scheme.error)),
                  ),
                GradientButton(
                  onPressed: _save,
                  icon: Icons.check_rounded,
                  label: _editing ? tr('Update') : tr('Save'),
                ),
                if (_editing)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton.icon(
                      onPressed: _delete,
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(tr('Delete')),
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

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}

class _SourceChips extends StatelessWidget {
  const _SourceChips({
    required this.selected,
    required this.onSelected,
    this.includeAccounts = true,
    this.includeCards = true,
    this.exclude,
  });

  final Source? selected;
  final ValueChanged<Source> onSelected;
  final bool includeAccounts;
  final bool includeCards;
  final Source? exclude;

  @override
  Widget build(BuildContext context) {
    final l = context.ledger;
    final chips = <Widget>[
      if (includeAccounts)
        for (final a in l.accounts)
          if (Source.account(a.id) != exclude)
            ChoiceChip(
              showCheckmark: false,
              avatar: Icon(iconForAccount(a.kind), size: 18),
              label: Text(a.name),
              selected: selected == Source.account(a.id),
              onSelected: (_) => onSelected(Source.account(a.id)),
            ),
      if (includeCards)
        for (final c in l.cards)
          ChoiceChip(
            showCheckmark: false,
            avatar: const Icon(Icons.credit_card, size: 18),
            label: Text(c.displayName),
            selected: selected == Source.card(c.id),
            onSelected: (_) => onSelected(Source.card(c.id)),
          ),
    ];
    if (chips.isEmpty) {
      return Text(
        includeAccounts
            ? tr('Add an account first.')
            : tr('Add a credit card first.'),
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return Wrap(spacing: 8, runSpacing: 4, children: chips);
  }
}

/// Full-screen, zoomable view of a receipt photo.
void showReceipt(BuildContext context, String path) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(tr('Receipt'), style: TextStyle(color: Colors.white)),
        ),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Image.file(
              File(path),
              errorBuilder: (_, _, _) => Text(
                tr('The photo is no longer on this phone.'),
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
