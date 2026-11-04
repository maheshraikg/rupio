import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../ledger/ledger.dart';
import '../models/money.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import 'auto_detect_screen.dart';
import 'forms.dart';
import 'holding_detail_screen.dart';
import 'pay_bill_sheet.dart';
import '../l10n/strings.dart';
import '../sync/sms_sync.dart';

/// Gradients for the card faces, picked by card id so each keeps its look.
const _cardFaces = [
  [Color(0xFF2C2C30), Color(0xFF111113)], // graphite
  [Color(0xFF173D2C), Color(0xFF0B1F17)], // forest
  [Color(0xFF3A3F47), Color(0xFF17191D)], // steel
  [Color(0xFF243447), Color(0xFF0F1620)], // midnight
  [Color(0xFF453628), Color(0xFF1B1510)], // bronze
];

/// Every credit card with its limit, usage, bill and due date.
class CardsScreen extends StatelessWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.ledger;
    final now = today();
    final statuses = [for (final c in l.cards) l.cardStatus(c, now)];
    final totalLimit = l.cards.fold(0, (s, c) => s + c.creditLimit);
    final totalOwed = l.totalCardOutstanding;
    final totalDue = statuses.fold(0, (s, x) => s + x.amountDue);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Credit cards')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_card),
            tooltip: tr('Add card'),
            onPressed: () => showAddCardDialog(context),
          ),
        ],
      ),
      body: statuses.isEmpty
          ? EmptyState(
              icon: Icons.credit_card,
              message: tr(
                'Add your credit cards to track spending, limits and payment due dates, with reminders before every bill.',
              ),
              actionLabel: tr('Add card'),
              onAction: () => showAddCardDialog(context),
              secondaryLabel: SmsSync.available
                  ? tr('Find my cards from SMS')
                  : null,
              onSecondary: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const AutoDetectScreen(),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (statuses.length > 1)
                  Panel(
                    child: Row(
                      children: [
                        Expanded(
                          child: Figure(
                            tr('Total owed'),
                            formatRupees(totalOwed),
                          ),
                        ),
                        Expanded(
                          child: Figure(
                            tr('Bills due'),
                            formatRupees(totalDue),
                          ),
                        ),
                        Expanded(
                          child: Figure(
                            tr('Used'),
                            totalLimit == 0
                                ? '–'
                                : '${(totalOwed * 100 / totalLimit).toStringAsFixed(0)}%',
                          ),
                        ),
                      ],
                    ),
                  ),
                for (var i = 0; i < statuses.length; i++)
                  _CardBlock(status: statuses[i], face: i),
              ],
            ),
    );
  }
}

class _CardBlock extends StatelessWidget {
  const _CardBlock({required this.status, required this.face});
  final CardStatus status;

  /// Position in the list, so cards take the colourful faces in order.
  final int face;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final util = s.utilisationPercent;
    final utilColor = util >= 75
        ? scheme.error
        : util >= 30
        ? kOrange
        : scheme.moneyIn;
    final daysLeft = s.dueDate.difference(today()).inDays;
    final (dueText, dueColor) = s.overdue
        ? (tr('Overdue since {0}', [dayMonth(s.dueDate)]), scheme.error)
        : s.amountDue > 0
        ? (
            daysLeft == 0
                ? tr('Due today')
                : tr('Due {0} · {1} days', [dayMonth(s.dueDate), daysLeft]),
            daysLeft <= 7 ? kOrange : scheme.onSurfaceVariant,
          )
        : (tr('Next due {0}', [dayMonth(s.dueDate)]), scheme.moneyIn);

    void open() => Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => HoldingDetailScreen.card(s.card.id),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: open,
            child: AspectRatio(
              aspectRatio: 1.75,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _cardFaces[face % _cardFaces.length],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(20),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: Colors.white),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.card.name,
                              style: t.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Icon(Icons.contactless, color: Colors.white70),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: 38,
                        height: 28,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFD9C08A), Color(0xFFA2884F)],
                          ),
                        ),
                      ),
                      const Spacer(),
                      HeroFigure(
                        tr('Outstanding'),
                        formatRupees(s.outstanding),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            s.card.lastFour.isEmpty
                                ? '•••• ••••'
                                : '•••• ${s.card.lastFour}',
                            style: const TextStyle(
                              letterSpacing: 2,
                              color: Colors.white70,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            tr('Limit {0}', [
                              formatRupeesCompact(s.card.creditLimit),
                            ]),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Panel(
            margin: const EdgeInsets.only(top: 12),
            onTap: open,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('{0}% of limit used', [util.toStringAsFixed(0)]),
                        style: t.labelLarge,
                      ),
                    ),
                    Text(
                      tr('{0} available', [formatRupees(s.availableCredit)]),
                      style: t.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Meter(value: util / 100, color: utilColor),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Figure(
                        tr('Bill to pay'),
                        formatRupees(s.amountDue),
                        color: s.overdue ? scheme.error : null,
                      ),
                    ),
                    Expanded(
                      child: Figure(
                        tr('Spent this cycle'),
                        formatRupees(s.cycleSpend),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Pill(
                          dueText,
                          color: dueColor,
                          icon: s.overdue ? Icons.error_outline : Icons.event,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 128,
                      child: GradientButton(
                        height: 46,
                        onPressed: () => showPayBillSheet(context, s.card),
                        label: tr('Pay bill'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
