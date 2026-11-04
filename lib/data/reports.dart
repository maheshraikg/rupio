/// Full reports of the user's data as Excel and PDF, for sharing, printing or
/// keeping. (Restore still uses the JSON backup, which keeps every detail.)
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../ledger/ledger.dart';
import '../models/models.dart';
import '../models/money.dart';
import 'xlsx.dart';

String _from(Ledger l, Txn t) =>
    l.account(t.fromAccountId)?.name ??
    l.card(t.fromCardId)?.displayName ??
    (t.type == TxnType.investWithdrawal || t.type == TxnType.investIncome
        ? l.investment(t.investmentId)?.name ?? ''
        : '');

String _to(Ledger l, Txn t) =>
    l.account(t.toAccountId)?.name ??
    l.card(t.toCardId)?.displayName ??
    (t.type == TxnType.invest ? l.investment(t.investmentId)?.name ?? '' : '');

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

/// Signed amount from the user's side: spending negative, income positive.
int _signed(Txn t) => switch (t.type) {
  TxnType.expense => -t.amount,
  TxnType.income || TxnType.refund || TxnType.investIncome => t.amount,
  _ => t.amount,
};

/// Excel workbook: Summary, Transactions, Accounts, Cards, Investments,
/// Budgets.
Uint8List buildExcelReport(Ledger l, DateTime today) {
  final worth = l.netWorth(today);
  final from = monthStart(today), to = monthEnd(today);
  return buildXlsx([
    XlsxSheet(
      'Summary',
      [
        ['Rupio report', _date(today)],
        ['Net worth', Money(worth.total)],
        ['In accounts', Money(worth.cash)],
        ['Investments', Money(worth.investments)],
        ['Credit cards owed', Money(worth.liabilities)],
        [],
        ['This month', ''],
        ['Income', Money(l.income(from, to))],
        ['Spending', Money(l.spending(from, to))],
        ['Invested', Money(l.invested(from, to))],
        [],
        ['Spending by category (this month)', ''],
        for (final e in l.spendingByCategory(from, to).entries)
          [e.key, Money(e.value)],
      ],
      widths: [34, 18],
    ),
    XlsxSheet(
      'Transactions',
      [
        [
          'Date',
          'Type',
          'Amount',
          'In (+) / Out (−)',
          'Category',
          'Note',
          'From',
          'To',
          'Source',
        ],
        for (final t in l.txns)
          [
            _date(t.date),
            t.type.labelEn,
            Money(t.amount),
            Money(_signed(t)),
            t.category ?? '',
            t.note ?? '',
            _from(l, t),
            _to(l, t),
            t.sourceLabel ?? 'Entered',
          ],
      ],
      widths: [12, 18, 14, 16, 16, 30, 22, 22, 11],
    ),
    XlsxSheet(
      'Accounts',
      [
        ['Name', 'Type', 'Account digits', 'Balance'],
        for (final a in l.accounts)
          [a.name, a.kind.labelEn, a.lastFour, Money(l.accountBalance(a.id))],
      ],
      widths: [24, 18, 16, 16],
    ),
    XlsxSheet(
      'Cards',
      [
        [
          'Card',
          'Last 4',
          'Credit limit',
          'Outstanding',
          'Available',
          'Bill to pay',
          'Minimum due',
          'Due date',
        ],
        for (final c in l.cards)
          if (l.cardStatus(c, today) case final s)
            [
              c.name,
              c.lastFour,
              Money(c.creditLimit),
              Money(s.outstanding),
              Money(s.availableCredit),
              Money(s.amountDue),
              s.minDue == null ? '' : Money(s.minDue!),
              _date(s.dueDate),
            ],
      ],
      widths: [24, 8, 14, 14, 14, 14, 14, 12],
    ),
    XlsxSheet(
      'Investments',
      [
        [
          'Name',
          'Type',
          'Invested',
          'Current value',
          'Gain',
          'Return %',
          'Value as of',
        ],
        for (final i in l.investments)
          if (l.investmentSummary(i, today) case final s)
            [
              i.name,
              i.type.labelEn,
              Money(s.netInvested),
              s.currentValue == null ? '' : Money(s.currentValue!),
              s.absoluteReturn == null ? '' : Money(s.absoluteReturn!),
              s.returnPercent == null
                  ? ''
                  : double.parse(s.returnPercent!.toStringAsFixed(2)),
              i.valueUpdatedOn == null ? '' : _date(i.valueUpdatedOn!),
            ],
      ],
      widths: [26, 18, 14, 14, 14, 10, 12],
    ),
    XlsxSheet(
      'Budgets',
      [
        ['Category', 'Monthly limit', 'Spent this month', 'Left'],
        for (final b in l.budgetStatuses(today))
          [
            b.budget.category,
            Money(b.budget.monthlyLimit),
            Money(b.spent),
            Money(b.remaining),
          ],
      ],
      widths: [20, 16, 18, 16],
    ),
  ]);
}

/// PDF report with the same content, laid out for reading and printing.
/// [regular] and [bold] are TTF fonts that include the ₹ sign.
Future<Uint8List> buildPdfReport(
  Ledger l,
  DateTime today, {
  required ByteData regular,
  required ByteData bold,
}) {
  final worth = l.netWorth(today);
  final from = monthStart(today), to = monthEnd(today);
  const teal = PdfColor.fromInt(0xFF00695C);
  final doc = pw.Document(
    title: 'Rupio report ${_date(today)}',
    author: 'Rupio',
    theme: pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
    ),
  );

  pw.Widget heading(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 13,
        fontWeight: pw.FontWeight.bold,
        color: teal,
      ),
    ),
  );

  pw.Widget table(
    List<String> headers,
    List<List<String>> rows, {
    Set<int> right = const {},
  }) => rows.isEmpty
      ? pw.Text('None', style: const pw.TextStyle(color: PdfColors.grey600))
      : pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
            fontSize: 9,
          ),
          headerDecoration: const pw.BoxDecoration(color: teal),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 3,
          ),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          cellAlignments: {for (final i in right) i: pw.Alignment.centerRight},
          headerAlignments: {
            for (final i in right) i: pw.Alignment.centerRight,
          },
        );

  pw.Widget figure(String label, String value) => pw.Expanded(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: teal, width: 1.5)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Rupio',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: teal,
              ),
            ),
            pw.Text('Report · ${_date(today)}'),
          ],
        ),
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ),
      build: (context) => [
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            figure('Net worth', formatRupees(worth.total)),
            figure('In accounts', formatRupees(worth.cash)),
            figure('Investments', formatRupees(worth.investments)),
            figure('Cards owed', formatRupees(worth.liabilities)),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            figure('Income this month', formatRupees(l.income(from, to))),
            figure('Spent this month', formatRupees(l.spending(from, to))),
            figure('Invested this month', formatRupees(l.invested(from, to))),
            pw.Expanded(child: pw.SizedBox()),
          ],
        ),
        heading('Accounts'),
        table(
          ['Name', 'Type', 'Balance'],
          [
            for (final a in l.accounts)
              [
                a.lastFour.isEmpty ? a.name : '${a.name} ••${a.lastFour}',
                a.kind.labelEn,
                formatRupees(l.accountBalance(a.id)),
              ],
          ],
          right: {2},
        ),
        heading('Credit cards'),
        table(
          ['Card', 'Limit', 'Outstanding', 'Bill', 'Due'],
          [
            for (final c in l.cards)
              if (l.cardStatus(c, today) case final s)
                [
                  c.displayName,
                  formatRupees(c.creditLimit),
                  formatRupees(s.outstanding),
                  formatRupees(s.amountDue),
                  _date(s.dueDate),
                ],
          ],
          right: {1, 2, 3},
        ),
        heading('Investments'),
        table(
          ['Name', 'Type', 'Invested', 'Value', 'Gain', 'Return'],
          [
            for (final i in l.investments)
              if (l.investmentSummary(i, today) case final s)
                [
                  i.name,
                  i.type.labelEn,
                  formatRupees(s.netInvested),
                  s.currentValue == null ? '–' : formatRupees(s.currentValue!),
                  s.absoluteReturn == null
                      ? '–'
                      : formatRupees(s.absoluteReturn!),
                  s.returnPercent == null
                      ? '–'
                      : '${s.returnPercent!.toStringAsFixed(1)}%',
                ],
          ],
          right: {2, 3, 4, 5},
        ),
        heading('Spending by category · this month'),
        table(
          ['Category', 'Spent'],
          [
            for (final e in l.spendingByCategory(from, to).entries)
              [e.key, formatRupees(e.value)],
          ],
          right: {1},
        ),
        if (l.budgets.isNotEmpty) ...[
          heading('Budgets · this month'),
          table(
            ['Category', 'Limit', 'Spent', 'Left'],
            [
              for (final b in l.budgetStatuses(today))
                [
                  b.budget.category,
                  formatRupees(b.budget.monthlyLimit),
                  formatRupees(b.spent),
                  formatRupees(b.remaining),
                ],
            ],
            right: {1, 2, 3},
          ),
        ],
        heading('All transactions'),
        table(
          ['Date', 'Details', 'From → To', 'Amount'],
          [
            for (final t in l.txns)
              [
                _date(t.date),
                [
                  t.note ?? t.category ?? t.type.labelEn,
                  if (t.note != null && t.category != null) t.category!,
                ].join(' · '),
                [_from(l, t), _to(l, t)].where((s) => s.isNotEmpty).join(' → '),
                switch (t.type) {
                  TxnType.expense => '−${formatRupees(t.amount)}',
                  TxnType.income ||
                  TxnType.refund ||
                  TxnType.investIncome => '+${formatRupees(t.amount)}',
                  _ => formatRupees(t.amount),
                },
              ],
          ],
          right: {3},
        ),
      ],
    ),
  );
  return doc.save();
}
