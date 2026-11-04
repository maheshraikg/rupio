/// Amounts are stored as whole paise (1 rupee = 100 paise) so that totals
/// never pick up floating-point errors.
typedef Paise = int;

/// Formats [amount] as rupees with Indian digit grouping, e.g.
/// 16940000 -> "₹1,69,400". Paise are shown only when non-zero, unless
/// [alwaysShowPaise] is set.
String formatRupees(Paise amount, {bool alwaysShowPaise = false}) {
  final sign = amount < 0 ? '-' : '';
  final abs = amount.abs();
  final rupees = abs ~/ 100;
  final paise = abs % 100;
  final fraction = (paise != 0 || alwaysShowPaise)
      ? '.${paise.toString().padLeft(2, '0')}'
      : '';
  return '$sign₹${_groupIndian(rupees.toString())}$fraction';
}

/// Short form for tight spaces: ₹950, ₹12.5K, ₹1.2L, ₹3.4Cr.
String formatRupeesCompact(Paise amount) {
  final sign = amount < 0 ? '-' : '';
  final rupees = amount.abs() / 100;
  String trim(double v) => v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  if (rupees >= 1e7) return '$sign₹${trim(rupees / 1e7)}Cr';
  if (rupees >= 1e5) return '$sign₹${trim(rupees / 1e5)}L';
  if (rupees >= 1e4) return '$sign₹${trim(rupees / 1e3)}K';
  return '$sign₹${_groupIndian(rupees.round().toString())}';
}

String _groupIndian(String digits) {
  if (digits.length <= 3) return digits;
  final lastThree = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '${groups.join(',')},$lastThree';
}

final _amountPattern = RegExp(r'^(\d+)(?:\.(\d{0,2}))?$');

/// Parses user input such as "250", "1,250.5" or "₹ 99.99" into paise.
/// Returns null for empty, negative or malformed input, or more than two
/// decimal places.
Paise? parseRupees(String input) {
  var cleaned = input.trim();
  if (cleaned.startsWith('₹')) cleaned = cleaned.substring(1);
  cleaned = cleaned.replaceAll(',', '').trim();
  final match = _amountPattern.firstMatch(cleaned);
  if (match == null) return null;
  final whole = match.group(1)!;
  // 15 digits of rupees is far beyond any personal balance and stays well
  // inside a 64-bit int once converted to paise.
  if (whole.length > 15) return null;
  final paise = (match.group(2) ?? '').padRight(2, '0');
  return int.parse(whole) * 100 + int.parse(paise);
}

/// Like [parseRupees] but also accepts a leading minus (e.g. an overdrawn
/// balance).
Paise? parseSignedRupees(String input) {
  final s = input.trim();
  if (s.startsWith('-')) {
    final v = parseRupees(s.substring(1));
    return v == null ? null : -v;
  }
  return parseRupees(s);
}

/// Paise as plain text for an input field: "1250", "99.50", "-40".
String amountText(Paise p) {
  final sign = p < 0 ? '-' : '';
  final a = p.abs();
  return a % 100 == 0
      ? '$sign${a ~/ 100}'
      : '$sign${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
}
