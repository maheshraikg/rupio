import 'dart:convert';

import '../l10n/strings.dart';
import '../ledger/ledger.dart';
import '../models/money.dart';
import 'native.dart';
import 'scope.dart';
import 'store.dart';

/// Figures for the home screen widget: this month's spending, total and
/// per day, already formatted in the interface language.
String widgetJson(Ledger l, DateTime today) {
  final from = monthStart(today), to = monthEnd(today);
  final values = [
    for (var d = 1; d <= to.day; d++)
      l.spending(
            DateTime.utc(today.year, today.month, d),
            DateTime.utc(today.year, today.month, d),
          ) /
          100,
  ];
  return jsonEncode({
    'label': tr('Spent in {0}', [monthName(today.month)]),
    'total': formatRupees(l.spending(from, to)),
    'values': values,
    'color': '#F87171',
  });
}

Future<void> updateHomeWidget(FinanceStore store) =>
    Native.updateWidget(widgetJson(store.ledger, today()));
