import 'models.dart';
import 'money.dart';
import '../l10n/strings.dart';

/// A monthly spending limit for one category.
class Budget {
  const Budget({required this.category, required this.monthlyLimit});

  final String category;
  final Paise monthlyLimit;

  Map<String, Object?> toJson() => {
    'category': category,
    'limit': monthlyLimit,
  };

  factory Budget.fromJson(Map<String, dynamic> j) => Budget(
    category: j['category'] as String,
    monthlyLimit: j['limit'] as int,
  );
}

enum Frequency {
  weekly('Every week'),
  monthly('Every month'),
  yearly('Every year');

  const Frequency(this.labelEn);

  /// English name (exports, reports).
  final String labelEn;

  /// Name in the interface language.
  String get label => tr(labelEn);
}

/// A repeating entry (rent, SIP, subscription, salary). Copies of [template]
/// are posted automatically on each due date up to today.
class Recurring {
  const Recurring({
    required this.id,
    required this.template,
    required this.frequency,
    required this.nextDate,
    this.active = true,
  });

  final int id;

  /// The entry to copy. Its date is the first occurrence and sets the day of
  /// the month (or week) for later ones.
  final Txn template;
  final Frequency frequency;

  /// The next date that has not been posted yet.
  final DateTime nextDate;
  final bool active;

  Recurring copyWith({DateTime? nextDate, bool? active, Txn? template}) =>
      Recurring(
        id: id,
        template: template ?? this.template,
        frequency: frequency,
        nextDate: nextDate ?? this.nextDate,
        active: active ?? this.active,
      );

  /// The occurrence after [date].
  DateTime after(DateTime date) {
    final anchor = template.date;
    switch (frequency) {
      case Frequency.weekly:
        return dateOnly(date).add(const Duration(days: 7));
      case Frequency.monthly:
        return _clamped(date.year, date.month + 1, anchor.day);
      case Frequency.yearly:
        return _clamped(date.year + 1, anchor.month, anchor.day);
    }
  }

  /// Dates from [nextDate] up to and including [today] that still need to
  /// be posted (at most [limit], so a long-unused app cannot flood itself).
  List<DateTime> dueDates(DateTime today, {int limit = 60}) {
    if (!active) return const [];
    final t = dateOnly(today);
    final result = <DateTime>[];
    var d = nextDate;
    while (!d.isAfter(t) && result.length < limit) {
      result.add(d);
      d = after(d);
    }
    return result;
  }

  static DateTime _clamped(int year, int month, int day) {
    final first = DateTime.utc(year, month);
    final length = DateTime.utc(first.year, first.month + 1, 0).day;
    return DateTime.utc(first.year, first.month, day > length ? length : day);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'template': template.toJson(),
    'frequency': frequency.name,
    'next': isoDate(nextDate),
    'active': active,
  };

  factory Recurring.fromJson(Map<String, dynamic> j) => Recurring(
    id: j['id'] as int,
    template: Txn.fromJson(j['template'] as Map<String, dynamic>),
    frequency:
        Frequency.values.asNameMap()[j['frequency']] ?? Frequency.monthly,
    nextDate: parseIsoDate(j['next'] as String),
    active: (j['active'] as bool?) ?? true,
  );
}
