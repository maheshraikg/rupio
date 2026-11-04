import 'dart:math' as math;

import '../models/models.dart';
import '../models/money.dart';

class InvestmentSummary {
  const InvestmentSummary({
    required this.investment,
    required this.contributed,
    required this.withdrawn,
    required this.incomePaidOut,
    this.value,
    this.xirr,
    this.xirrTooEarly = false,
  });

  final Investment investment;
  final Paise contributed;
  final Paise withdrawn;

  /// Dividends / interest paid out to an account. Reinvested income is
  /// already part of the current value, so it is not added again.
  final Paise incomePaidOut;

  /// Current value (units × latest NAV for linked funds), or null when not
  /// known yet.
  final Paise? value;

  /// Annualised return as a fraction (0.12 = 12% a year), when computable.
  final double? xirr;

  /// True when there is less than a year of history: a yearly rate would be
  /// misleading, so only the plain return is shown.
  final bool xirrTooEarly;

  Paise? get currentValue => value;

  Paise get netInvested => contributed - withdrawn;

  /// Gain including withdrawals and payouts; null until the user enters a
  /// current value.
  Paise? get absoluteReturn {
    final value = currentValue;
    if (value == null) return null;
    return value + withdrawn + incomePaidOut - contributed;
  }

  /// [absoluteReturn] as a percentage of everything contributed.
  double? get returnPercent {
    final gain = absoluteReturn;
    if (gain == null || contributed <= 0) return null;
    return gain * 100 / contributed;
  }
}

/// A dated cash flow from the investor's side: negative = money put in,
/// positive = money received (or the current value at the valuation date).
class CashFlow {
  const CashFlow(this.date, this.amount);
  final DateTime date;
  final Paise amount;
}

/// Annualised internal rate of return for irregular cash flows (the usual way
/// to measure a SIP), as a fraction. Null when no meaningful rate exists.
double? xirr(List<CashFlow> flows) {
  if (!flows.any((f) => f.amount < 0) || !flows.any((f) => f.amount > 0)) {
    return null;
  }
  final start = flows
      .map((f) => f.date)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  if (flows.every((f) => f.date == start)) return null;

  double npv(double rate) {
    var sum = 0.0;
    for (final f in flows) {
      final years = f.date.difference(start).inDays / 365.0;
      sum += f.amount / math.pow(1 + rate, years);
    }
    return sum;
  }

  // Bisection: slower than Newton's method but cannot diverge.
  var low = -0.9999;
  var high = 100.0;
  var npvLow = npv(low);
  if (npvLow * npv(high) > 0) return null;
  for (var i = 0; i < 200; i++) {
    final mid = (low + high) / 2;
    final npvMid = npv(mid);
    if (npvLow * npvMid <= 0) {
      high = mid;
    } else {
      low = mid;
      npvLow = npvMid;
    }
  }
  return (low + high) / 2;
}
