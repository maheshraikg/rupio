import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../data/amfi.dart';
import '../ledger/returns.dart';
import '../models/models.dart';
import '../models/money.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import 'forms.dart';
import 'holding_detail_screen.dart';
import 'quick_add_sheet.dart';
import '../l10n/strings.dart';

String _percent(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}%';

/// NAVs downloaded this session, so linking several funds needs one fetch.
Map<String, NavQuote>? _navCache;

Future<Map<String, NavQuote>> _navs({bool fresh = false}) async {
  if (!fresh && _navCache != null) return _navCache!;
  return _navCache = await fetchAmfiNavs();
}

/// Downloads the latest NAVs and revalues every linked fund.
Future<void> refreshFundPrices(BuildContext context) async {
  final store = context.store;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(content: Text(tr('Fetching latest NAVs from AMFI…'))),
  );
  try {
    final n = await store.applyNavs(await _navs(fresh: true));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            n == 0
                ? tr('No linked funds to update')
                : tr('Updated {0} funds', [n]),
          ),
        ),
      );
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(tr('Could not reach AMFI. Check your internet.')),
        ),
      );
  }
}

/// Portfolio kept apart from everyday spending, with returns where a current
/// value is known.
class InvestmentsScreen extends StatelessWidget {
  const InvestmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.ledger;
    final now = today();
    final summaries = [
      for (final i in l.investments) l.investmentSummary(i, now),
    ];
    final scheme = Theme.of(context).colorScheme;

    final netInvested = summaries.fold(0, (s, x) => s + x.netInvested);
    final valued = summaries.where((s) => s.currentValue != null).toList();
    final valuedGain = valued.fold(0, (s, x) => s + x.absoluteReturn!);
    final valuedContributed = valued.fold(0, (s, x) => s + x.contributed);
    Paise valueOf(InvestmentSummary x) =>
        x.currentValue ?? (x.netInvested > 0 ? x.netInvested : 0);
    final currentTotal = summaries.fold(0, (s, x) => s + valueOf(x));

    final byType = <InvestmentType, Paise>{};
    for (final s in summaries) {
      byType.update(
        s.investment.type,
        (v) => v + valueOf(s),
        ifAbsent: () => valueOf(s),
      );
    }
    final allocation = byType.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Investments')),
        actions: [
          if (l.investments.any((i) => i.isLinked))
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: tr('Update fund prices'),
              onPressed: () => refreshFundPrices(context),
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: tr('Add investment'),
            onPressed: () => showAddInvestmentDialog(context),
          ),
        ],
      ),
      body: summaries.isEmpty
          ? EmptyState(
              icon: Icons.insights,
              message: tr(
                'Add your mutual funds, SIPs, stocks, PPF, FDs, NPS, gold and more. Money you invest is kept out of your spending.',
              ),
              actionLabel: tr('Add investment'),
              onAction: () => showAddInvestmentDialog(context),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                HeroPanel(
                  colors: const [Color(0xFF0F172A), Color(0xFF1E3A8A)],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: HeroFigure(
                              tr('Portfolio value'),
                              formatRupees(currentTotal),
                              big: true,
                            ),
                          ),
                          if (valuedContributed > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _percent(valuedGain * 100 / valuedContributed),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: HeroFigure(
                              tr('Invested'),
                              formatRupeesCompact(netInvested),
                            ),
                          ),
                          Expanded(
                            child: HeroFigure(
                              tr('Total gain'),
                              valued.isEmpty
                                  ? '–'
                                  : '${valuedGain >= 0 ? '+' : ''}'
                                        '${formatRupeesCompact(valuedGain)}',
                            ),
                          ),
                        ],
                      ),
                      if (valued.length < summaries.length) ...[
                        const SizedBox(height: 10),
                        Text(
                          tr(
                            'Gain includes only holdings with a current value.',
                          ),
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                if (allocation.length > 1)
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Allocation'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Row(
                            children: [
                              for (var i = 0; i < allocation.length; i++)
                                Expanded(
                                  flex:
                                      (allocation[i].value *
                                              1000 ~/
                                              currentTotal)
                                          .clamp(1, 1000),
                                  child: Container(
                                    height: 12,
                                    color: chartColor(i),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 14,
                          runSpacing: 6,
                          children: [
                            for (var i = 0; i < allocation.length; i++)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: chartColor(i),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${allocation[i].key.label} '
                                    '${(allocation[i].value * 100 / currentTotal).round()}%',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                SectionHeader(tr('Holdings')),
                for (final s in summaries) _InvestmentTile(summary: s),
                Padding(
                  padding: kPagePadding,
                  child: Text(
                    tr(
                      'Values you type are your own figures. Linked mutual funds use the daily NAV published by AMFI.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
    );
  }
}

class _InvestmentTile extends StatelessWidget {
  const _InvestmentTile({required this.summary});
  final InvestmentSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final inv = s.investment;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final gain = s.absoluteReturn;
    final gainColor = gain == null
        ? scheme.onSurfaceVariant
        : gain >= 0
        ? scheme.moneyIn
        : scheme.danger;
    final valueNote = inv.valueUpdatedOn == null
        ? tr('Add today’s value to see returns')
        : '${inv.valueSource ?? 'Value you entered'} · '
              '${shortDate(inv.valueUpdatedOn!)}';

    return Panel(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => HoldingDetailScreen.investment(inv.id),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(_typeIcon(inv.type)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(inv.name, style: t.titleMedium),
                    Text(
                      inv.isLinked
                          ? tr('{0} · {1} units', [
                              inv.type.label,
                              _units(inv.units!),
                            ])
                          : inv.type.label,
                      style: t.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (s.returnPercent != null)
                Pill(_percent(s.returnPercent!), color: gainColor),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Figure(tr('Invested'), formatRupees(s.netInvested)),
              ),
              Expanded(
                child: Figure(
                  tr('Current value'),
                  s.currentValue == null
                      ? tr('Not set')
                      : formatRupees(s.currentValue!),
                ),
              ),
            ],
          ),
          if (gain != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Figure(
                    tr('Gain'),
                    '${gain >= 0 ? '+' : ''}${formatRupees(gain)}',
                    color: gainColor,
                  ),
                ),
                Expanded(
                  child: Figure(
                    tr('Yearly (XIRR)'),
                    s.xirr != null
                        ? _percent(s.xirr! * 100)
                        : s.xirrTooEarly
                        ? tr('After 1 year')
                        : inv.openingInvested > 0 && inv.openingDate == null
                        ? tr('Add start date')
                        : '–',
                  ),
                ),
              ],
            ),
          ],
          if (s.incomePaidOut > 0) ...[
            const SizedBox(height: 8),
            Text(
              tr('Dividends / interest received: {0}', [
                formatRupees(s.incomePaidOut),
              ]),
              style: t.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            valueNote,
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _SmallAction(
                tr('Add money'),
                () => showQuickAdd(
                  context,
                  type: TxnType.invest,
                  investmentId: inv.id,
                ),
              ),
              _SmallAction(
                tr('Update value'),
                () => showUpdateValueDialog(context, inv),
              ),
              if (inv.type == InvestmentType.mutualFund)
                _SmallAction(
                  inv.isLinked ? tr('NAV linked') : tr('Link NAV'),
                  () => showLinkFundSheet(context, inv),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction(this.label, this.onPressed);
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: VisualDensity.compact,
    ),
    child: Text(label),
  );
}

String _units(double u) =>
    u.toStringAsFixed(3).replaceAll(RegExp(r'\.?0+$'), '');

IconData _typeIcon(InvestmentType t) => switch (t) {
  InvestmentType.mutualFund => Icons.pie_chart_outline,
  InvestmentType.stock => Icons.candlestick_chart_outlined,
  InvestmentType.ppf || InvestmentType.nps => Icons.account_balance_outlined,
  InvestmentType.nsc || InvestmentType.postOffice => Icons.local_post_office,
  InvestmentType.fixedDeposit ||
  InvestmentType.recurringDeposit => Icons.savings_outlined,
  InvestmentType.gold => Icons.workspace_premium_outlined,
  InvestmentType.other => Icons.category_outlined,
};

/// Search an AMFI scheme, enter units held, and link the holding so its
/// value follows the daily NAV.
Future<void> showLinkFundSheet(BuildContext context, Investment inv) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _LinkFundSheet(investment: inv),
  );
}

class _LinkFundSheet extends StatefulWidget {
  const _LinkFundSheet({required this.investment});
  final Investment investment;

  @override
  State<_LinkFundSheet> createState() => _LinkFundSheetState();
}

class _LinkFundSheetState extends State<_LinkFundSheet> {
  final _query = TextEditingController();
  final _unitsCtrl = TextEditingController();
  Map<String, NavQuote>? _all;
  NavQuote? _picked;
  String? _error;

  @override
  void initState() {
    super.initState();
    _query.text = widget.investment.name;
    final u = widget.investment.units;
    if (u != null) _unitsCtrl.text = _units(u);
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await _navs();
      if (!mounted) return;
      setState(() {
        _all = all;
        final code = widget.investment.schemeCode;
        if (code != null) _picked = all[code];
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr(
            'Could not download the fund list from AMFI. Check your internet and try again.',
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _unitsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final picked = _picked;
    final units = double.tryParse(_unitsCtrl.text.replaceAll(',', '').trim());
    if (picked == null || units == null || units <= 0) {
      setState(() => _error = tr('Pick a fund and enter the units you hold'));
      return;
    }
    final store = context.store;
    await store.linkScheme(widget.investment, picked.code, units);
    await store.applyNavs({picked.code: picked});
    if (mounted) Navigator.pop(context);
  }

  Future<void> _unlink() async {
    await context.store.linkScheme(widget.investment, null, null);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final all = _all;
    final results = all == null || _picked != null
        ? const <NavQuote>[]
        : searchSchemes(all, _query.text, limit: 30);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Link to daily NAV'), style: t.titleLarge),
              const SizedBox(height: 4),
              Text(
                tr('Value = units × latest NAV published by AMFI.'),
                style: t.bodySmall,
              ),
              const SizedBox(height: 12),
              if (_picked == null)
                TextField(
                  controller: _query,
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: tr('Fund name or scheme code'),
                  ),
                  onChanged: (_) => setState(() {}),
                )
              else
                Panel(
                  margin: EdgeInsets.zero,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_picked!.name, style: t.titleSmall),
                            Text(
                              tr('NAV {0} · {1}', [
                                formatRupees(
                                  (_picked!.nav * 100).round(),
                                  alwaysShowPaise: true,
                                ),
                                shortDate(_picked!.date),
                              ]),
                              style: t.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: tr('Choose another fund'),
                        onPressed: () => setState(() => _picked = null),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (all == null && _error == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_picked == null)
                Expanded(
                  child: ListView(
                    children: [
                      for (final q in results)
                        ListTile(
                          dense: true,
                          title: Text(q.name),
                          subtitle: Text(
                            tr('Code {0} · NAV {1}', [
                              q.code,
                              q.nav.toStringAsFixed(2),
                            ]),
                          ),
                          onTap: () => setState(() => _picked = q),
                        ),
                    ],
                  ),
                )
              else ...[
                TextField(
                  controller: _unitsCtrl,
                  autofocus: widget.investment.units == null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: tr('Units you hold'),
                    helperText: tr('From your fund statement or app'),
                  ),
                ),
                const Spacer(),
                if (widget.investment.isLinked)
                  TextButton(onPressed: _unlink, child: Text(tr('Unlink'))),
                FilledButton(onPressed: _save, child: Text(tr('Link fund'))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
