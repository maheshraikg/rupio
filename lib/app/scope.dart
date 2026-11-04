import 'package:flutter/material.dart';

import '../ledger/ledger.dart';
import '../models/models.dart';
import 'store.dart';
import '../l10n/strings.dart';

/// Gives widgets access to the [FinanceStore] and rebuilds them when it
/// changes.
class AppScope extends InheritedNotifier<FinanceStore> {
  const AppScope({super.key, required FinanceStore store, required super.child})
    : super(notifier: store);

  static FinanceStore storeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

extension AppContext on BuildContext {
  FinanceStore get store => AppScope.storeOf(this);
  Ledger get ledger => store.ledger;
}

/// Today's date (overridable in tests).
DateTime Function() clock = DateTime.now;

DateTime today() => dateOnly(clock());

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// "12 Mar 2026".
String shortDate(DateTime d) =>
    '${d.day} ${tr(_months[d.month - 1])} ${d.year}';

/// "12 Mar".
String dayMonth(DateTime d) => '${d.day} ${tr(_months[d.month - 1])}';

/// "March 2026".
String monthLabel(DateTime d) => '${tr(_monthsLong[d.month - 1])} ${d.year}';

/// "Today", "Yesterday" or [shortDate].
String relativeDate(DateTime d) {
  final diff = today().difference(dateOnly(d)).inDays;
  if (diff == 0) return tr('Today');
  if (diff == 1) return tr('Yesterday');
  return shortDate(d);
}

/// Full month name (1 = January) in the interface language.
String monthName(int month) => tr(_monthsLong[month - 1]);
