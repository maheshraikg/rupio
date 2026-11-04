import '../models/models.dart';

/// Statement and due-date arithmetic for a [CreditCard]. All dates are
/// date-only UTC values (see [dateOnly]).
class BillingCycle {
  BillingCycle._();

  /// The most recent statement date on or before [today].
  static DateTime lastStatementDate(CreditCard card, DateTime today) {
    final t = dateOnly(today);
    final thisMonth = _dayInMonth(t.year, t.month, card.statementDay);
    if (!thisMonth.isAfter(t)) return thisMonth;
    return _dayInMonth(t.year, t.month - 1, card.statementDay);
  }

  /// The first statement date after [statementDate].
  static DateTime nextStatementDate(CreditCard card, DateTime statementDate) =>
      _dayInMonth(
        statementDate.year,
        statementDate.month + 1,
        card.statementDay,
      );

  /// Payment due date for the statement generated on [statementDate].
  static DateTime dueDateFor(CreditCard card, DateTime statementDate) {
    final sameMonth = _dayInMonth(
      statementDate.year,
      statementDate.month,
      card.dueDay,
    );
    if (sameMonth.isAfter(statementDate)) return sameMonth;
    return _dayInMonth(
      statementDate.year,
      statementDate.month + 1,
      card.dueDay,
    );
  }

  /// [day] of the given month, clamped to the month's length. [month] may be
  /// outside 1..12 and rolls over into the neighbouring year.
  static DateTime _dayInMonth(int year, int month, int day) {
    final first = DateTime.utc(year, month);
    final length = DateTime.utc(first.year, first.month + 1, 0).day;
    return DateTime.utc(first.year, first.month, day > length ? length : day);
  }
}
