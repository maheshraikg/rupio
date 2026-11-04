import '../app/scope.dart' show shortDate;
import '../ledger/ledger.dart';
import '../models/models.dart';
import '../models/money.dart';

// ---- CSV text --------------------------------------------------------------

String _quote(String v) =>
    RegExp(r'[",\r\n]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;

String toCsv(List<List<String>> rows) =>
    '${rows.map((r) => r.map(_quote).join(',')).join('\r\n')}\r\n';

/// RFC 4180 CSV parser (quoted fields, doubled quotes, CRLF or LF). Blank
/// lines are dropped.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  if (text.startsWith('﻿')) text = text.substring(1);

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      endField();
    } else if (ch == '\n') {
      endRow();
    } else if (ch != '\r') {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

// ---- Export ----------------------------------------------------------------

/// All transactions as a spreadsheet-friendly CSV, oldest first.
String exportTransactionsCsv(Ledger l) {
  String plain(Paise p) => (p / 100).toStringAsFixed(2);
  return toCsv([
    ['Date', 'Type', 'Amount', 'Category', 'Note', 'From', 'To', 'Investment'],
    for (final t in l.txns.reversed)
      [
        isoDate(t.date),
        t.type.labelEn,
        plain(t.amount),
        t.category ?? '',
        t.note ?? '',
        l.account(t.fromAccountId)?.name ??
            l.card(t.fromCardId)?.displayName ??
            '',
        l.account(t.toAccountId)?.name ?? l.card(t.toCardId)?.displayName ?? '',
        l.investment(t.investmentId)?.name ?? '',
      ],
  ]);
}

/// A month's summary by category, for sharing or printing.
String exportMonthSummaryCsv(Ledger l, DateTime month) {
  String plain(Paise p) => (p / 100).toStringAsFixed(2);
  final from = monthStart(month), to = monthEnd(month);
  final budgets = {for (final b in l.budgets) b.category: b.monthlyLimit};
  return toCsv([
    ['Summary', '${shortDate(from)} – ${shortDate(to)}'],
    ['Income', plain(l.income(from, to))],
    ['Spending', plain(l.spending(from, to))],
    ['Invested', plain(l.invested(from, to))],
    [],
    ['Category', 'Spent', 'Budget'],
    for (final e in l.spendingByCategory(from, to).entries)
      [
        e.key,
        plain(e.value),
        budgets[e.key] == null ? '' : plain(budgets[e.key]!),
      ],
  ]);
}

// ---- Bank / card statement import ------------------------------------------

class StatementImport {
  const StatementImport({
    required this.txns,
    required this.duplicates,
    required this.skipped,
  });

  /// New entries, ready to save (ids are 0).
  final List<Txn> txns;

  /// Rows that match an entry already in the app.
  final int duplicates;

  /// Rows that could not be read, or card payments (recorded from the bank
  /// side instead).
  final int skipped;
}

const _monthNames = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// Parses the date formats used by Indian bank statements (day first):
/// 05/10/2026, 05-10-26, 05.10.2026, 2026-10-05, 05-Oct-2026, 5 Oct 26.
DateTime? parseStatementDate(String input) {
  final s = input.trim().split(RegExp(r'\s+\d{1,2}:\d{2}')).first.trim();
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  if (iso != null) {
    return _safeDate(
      int.parse(iso[1]!),
      int.parse(iso[2]!),
      int.parse(iso[3]!),
    );
  }
  final m = RegExp(
    r'^(\d{1,2})[\/\-. ]([A-Za-z]{3,9}|\d{1,2})[\/\-. ,]+(\d{2,4})$',
  ).firstMatch(s);
  if (m == null) return null;
  final day = int.parse(m[1]!);
  final monthText = m[2]!;
  final month =
      int.tryParse(monthText) ??
      _monthNames[monthText.substring(0, 3).toLowerCase()];
  var year = int.parse(m[3]!);
  if (month == null) return null;
  if (year < 100) year += 2000;
  return _safeDate(year, month, day);
}

DateTime? _safeDate(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final date = DateTime.utc(y, m, d);
  return date.month == m ? date : null;
}

/// Amount in a statement cell: "1,234.50", "₹ 250", "-250", "250.00 Dr",
/// "(250.00)". Returns signed paise (negative = money out), or null when
/// empty.
Paise? parseStatementAmount(String input) {
  var s = input.trim().replaceAll('INR', '').replaceAll('Rs.', '').trim();
  if (s.isEmpty || s == '-') return null;
  var sign = 1;
  final lower = s.toLowerCase();
  if (lower.endsWith('dr')) {
    sign = -1;
    s = s.substring(0, s.length - 2).trim();
  } else if (lower.endsWith('cr')) {
    s = s.substring(0, s.length - 2).trim();
  }
  if (s.startsWith('(') && s.endsWith(')')) {
    sign = -sign;
    s = s.substring(1, s.length - 1);
  }
  if (s.startsWith('-')) {
    sign = -sign;
    s = s.substring(1);
  } else if (s.startsWith('+')) {
    s = s.substring(1);
  }
  final value = parseRupees(s);
  return value == null ? null : sign * value;
}

const _categoryKeywords = <String, List<String>>{
  'Food': ['swiggy', 'zomato', 'restaurant', 'cafe', 'hotel', 'dominos', 'kfc'],
  'Groceries': ['bigbasket', 'blinkit', 'zepto', 'dmart', 'grocery', 'kirana'],
  'Fuel': ['petrol', 'fuel', 'hpcl', 'iocl', 'bpcl', 'indian oil', 'shell'],
  'Transport': ['uber', 'ola', 'rapido', 'metro', 'irctc', 'fastag', 'redbus'],
  'Shopping': ['amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'nykaa'],
  'Bills': [
    'electricity', 'bescom', 'mescom', 'airtel', 'jio', 'vodafone', 'vi ', //
    'bsnl', 'broadband', 'recharge', 'gas', 'water', 'dth',
  ],
  'Rent': ['rent'],
  'Health': ['pharmacy', 'hospital', 'apollo', 'medplus', 'clinic', '1mg'],
  'Entertainment': [
    'netflix',
    'hotstar',
    'spotify',
    'prime video',
    'bookmyshow',
  ],
  'Education': ['school', 'college', 'tuition', 'udemy', 'coursera'],
  'Travel': ['makemytrip', 'goibibo', 'indigo', 'air india', 'oyo'],
};

/// Best-guess spending category for a statement description.
String guessCategory(String description) {
  final d = ' ${description.toLowerCase()} ';
  for (final e in _categoryKeywords.entries) {
    if (e.value.any(d.contains)) return e.key;
  }
  return 'Other';
}

/// Best-guess income category for a statement description.
String guessIncomeCategory(String description) {
  final d = description.toLowerCase();
  if (d.contains('salary') || d.contains('sal ')) return 'Salary';
  if (d.contains('interest') || d.contains('int.pd') || d.contains('int pd')) {
    return 'Interest';
  }
  return 'Other';
}

int? _column(List<String> header, List<String> names) {
  for (final n in names) {
    final i = header.indexWhere((h) => h == n);
    if (i >= 0) return i;
  }
  for (final n in names) {
    final i = header.indexWhere((h) => h.contains(n));
    if (i >= 0) return i;
  }
  return null;
}

/// Reads a bank or credit card statement exported as CSV into entries for
/// the account [accountId] or the card [cardId] (exactly one is given).
///
/// The header row is found automatically (statements often start with a few
/// lines about the account). Supported layouts: separate Debit / Credit (or
/// Withdrawal / Deposit) columns, or one Amount column that is signed or
/// marked Dr / Cr. Rows matching an entry already in [existing] (same day,
/// amount, direction and account) are reported as duplicates, not added.
StatementImport importStatement(
  String csvText, {
  int? accountId,
  int? cardId,
  required Ledger existing,
}) {
  assert((accountId == null) != (cardId == null));
  final rows = parseCsv(csvText);
  int? headerIndex, date, desc, debit, credit, amount, drCr;
  for (var i = 0; i < rows.length && i < 40; i++) {
    final h = rows[i].map((c) => c.trim().toLowerCase()).toList();
    final d = _column(h, [
      'txn date',
      'transaction date',
      'date',
      'value date',
    ]);
    final dr = _column(h, ['debit', 'withdrawal', 'withdrawals', 'dr amount']);
    final cr = _column(h, ['credit', 'deposit', 'deposits', 'cr amount']);
    final a = _column(h, ['amount']);
    if (d != null && ((dr != null && cr != null) || a != null)) {
      headerIndex = i;
      date = d;
      desc = _column(h, [
        'description',
        'narration',
        'particulars',
        'details',
        'remarks',
        'transaction details',
      ]);
      if (dr != null && cr != null) {
        debit = dr;
        credit = cr;
      } else {
        amount = a;
        drCr = _column(h, ['dr/cr', 'cr/dr', 'debit/credit', 'type']);
      }
      break;
    }
  }
  if (headerIndex == null) {
    throw const FormatException(
      'Could not find the column headings (Date and Amount, or Debit and '
      'Credit) in this file',
    );
  }

  // Remaining matches per existing (date, signed amount) for this holding.
  final pending = <String, int>{};
  String key(DateTime d, Paise signed) => '${isoDate(d)}|$signed';
  for (final t in existing.txns) {
    Paise? signed;
    if (accountId != null) {
      if (t.fromAccountId == accountId) signed = -t.amount;
      if (t.toAccountId == accountId) signed = t.amount;
    } else {
      if (t.fromCardId == cardId) signed = -t.amount;
      if (t.toCardId == cardId) signed = t.amount;
    }
    if (signed != null) {
      pending.update(key(t.date, signed), (n) => n + 1, ifAbsent: () => 1);
    }
  }

  final txns = <Txn>[];
  var duplicates = 0, skipped = 0;
  for (final row in rows.skip(headerIndex + 1)) {
    String cell(int? i) => i != null && i < row.length ? row[i].trim() : '';
    final d = parseStatementDate(cell(date));
    Paise? signed;
    if (amount != null) {
      signed = parseStatementAmount(cell(amount));
      final marker = cell(drCr).toLowerCase();
      if (signed != null &&
          (marker.startsWith('d') || marker == 'withdrawal')) {
        signed = -signed.abs();
      } else if (signed != null && marker.startsWith('c')) {
        signed = signed.abs();
      }
      // Card statements list purchases as positive amounts.
      if (signed != null && cardId != null && marker.isEmpty) signed = -signed;
    } else {
      final out = parseStatementAmount(cell(debit));
      final inn = parseStatementAmount(cell(credit));
      if (out != null && out != 0) {
        signed = -out.abs();
      } else if (inn != null && inn != 0) {
        signed = inn.abs();
      }
    }
    if (d == null || signed == null || signed == 0) {
      // Closing-balance and footer lines end up here.
      skipped++;
      continue;
    }
    final k = key(d, signed);
    final left = pending[k] ?? 0;
    if (left > 0) {
      pending[k] = left - 1;
      duplicates++;
      continue;
    }
    final description = cell(desc);
    final note = description.isEmpty ? null : description;
    final value = signed.abs();
    if (signed < 0) {
      txns.add(
        Txn(
          id: 0,
          type: TxnType.expense,
          amount: value,
          date: d,
          category: guessCategory(description),
          note: note,
          fromAccountId: accountId,
          fromCardId: cardId,
        ),
      );
    } else if (accountId != null) {
      txns.add(
        Txn(
          id: 0,
          type: TxnType.income,
          amount: value,
          date: d,
          category: guessIncomeCategory(description),
          note: note,
          toAccountId: accountId,
        ),
      );
    } else if (description.toLowerCase().contains('payment')) {
      // Bill payments are recorded from the bank account side.
      skipped++;
    } else {
      txns.add(
        Txn(
          id: 0,
          type: TxnType.refund,
          amount: value,
          date: d,
          category: guessCategory(description),
          note: note,
          toCardId: cardId,
        ),
      );
    }
  }
  return StatementImport(txns: txns, duplicates: duplicates, skipped: skipped);
}
