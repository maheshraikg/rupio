/// Reads Indian bank and credit card alert messages (SMS or email text) into
/// structured events. Everything here is plain text matching; nothing leaves
/// the phone.
library;

import '../data/csv.dart' show parseStatementDate;
import '../models/models.dart';
import '../models/money.dart';

enum BankEventKind {
  /// Purchase on a credit card.
  cardSpend,

  /// Refund or reversal credited to a credit card.
  cardRefund,

  /// Bill payment received on a credit card.
  cardPayment,

  /// Statement generated: total due, minimum due, due date.
  cardBill,

  /// Money out of a bank account (UPI, NEFT, ATM, debit card, ...).
  accountDebit,

  /// Money into a bank account.
  accountCredit,
}

class BankEvent {
  const BankEvent({
    required this.kind,
    required this.amount,
    required this.date,
    required this.digits,
    this.bank,
    this.description,
    this.availableLimit,
    this.minDue,
    this.dueDate,
    this.statementDate,
    this.balance,
    this.paysCard = false,
    this.cardDigits,
  });

  final BankEventKind kind;

  /// Amount of the transaction, or the total due for [BankEventKind.cardBill].
  final Paise amount;
  final DateTime date;

  /// Trailing digits of the card or account number the message is about.
  final String digits;
  final String? bank;

  /// Merchant or payee, when the message names one.
  final String? description;

  /// Card limit still available after the transaction.
  final Paise? availableLimit;
  final Paise? minDue;
  final DateTime? dueDate;
  final DateTime? statementDate;

  /// Account balance after the transaction.
  final Paise? balance;

  /// An account debit that pays a credit card bill.
  final bool paysCard;

  /// Digits of the card being paid, when the debit message names them.
  final String? cardDigits;

  bool get isCard => switch (kind) {
    BankEventKind.cardSpend ||
    BankEventKind.cardRefund ||
    BankEventKind.cardPayment ||
    BankEventKind.cardBill => true,
    _ => false,
  };

  @override
  String toString() =>
      'BankEvent($kind ${formatRupees(amount)} ${isoDate(date)} '
      '…$digits ${bank ?? ''} ${description ?? ''})';
}

// ---- Shared patterns ---------------------------------------------------------

const _amount = r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)';
final _amountRe = RegExp(_amount, caseSensitive: false);

Paise? parseMoney(String s) {
  // Some banks write more decimals than paise ("250.000").
  final m = RegExp(r'^([0-9,]+)(?:\.([0-9]+))?$').firstMatch(s.trim());
  if (m == null) return null;
  final frac = (m.group(2) ?? '').padRight(2, '0').substring(0, 2);
  return parseRupees('${m.group(1)!.replaceAll(',', '')}.$frac');
}

/// The transaction amount: the first "Rs/INR/₹ amount", or "debited by
/// 250.0" as written by some UPI alerts.
Paise? _txnAmount(String text) {
  final m =
      _amountRe.firstMatch(text) ??
      RegExp(
        r'(?:debited|credited)\s+(?:by|with|for)\s+([0-9][0-9,]*(?:\.[0-9]+)?)',
        caseSensitive: false,
      ).firstMatch(text);
  return m == null ? null : parseMoney(m.group(1)!);
}

/// First amount within [window] characters after any of [labels]
/// (lower-case).
Paise? amountAfter(String text, List<String> labels, {int window = 60}) {
  final lower = text.toLowerCase();
  for (final label in labels) {
    var from = 0;
    while (true) {
      final i = lower.indexOf(label, from);
      if (i < 0) break;
      final start = i + label.length;
      final end = (start + window).clamp(0, text.length);
      final m = _amountRe.firstMatch(text.substring(start, end));
      if (m != null) return parseMoney(m.group(1)!);
      // Statements also write the amount without a currency sign.
      final plain = RegExp(r'^[\s:=-]*(?:is\s*)?([0-9][0-9,]*\.[0-9]{2})')
          .firstMatch(text.substring(start, end));
      if (plain != null) return parseMoney(plain.group(1)!);
      from = start;
    }
  }
  return null;
}

const _monthWords =
    'jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec|january|february|'
    'march|april|june|july|august|september|october|november|december';

final _dateRe = RegExp(
  [
    r'(\d{4}-\d{1,2}-\d{1,2}',
    '\\d{1,2}(?:$_monthWords)\\d{2,4}',
    '\\d{1,2}[/\\-.](?:\\d{1,2}|(?:$_monthWords))[/\\-.]\\d{2,4}',
    '\\d{1,2}\\s+(?:$_monthWords),?\\s+\\d{2,4})',
  ].join('|'),
  caseSensitive: false,
);

/// Dates written in the text, parsed day-first.
List<DateTime> datesIn(String text) => [
  for (final m in _dateRe.allMatches(text)) ?_parseDate(m.group(1)!),
];

DateTime? _parseDate(String s) {
  final compact = RegExp(r'^(\d{1,2})([A-Za-z]{3,9})(\d{2,4})$')
      .firstMatch(s.trim());
  if (compact != null) {
    return parseStatementDate('${compact[1]}-${compact[2]}-${compact[3]}');
  }
  return parseStatementDate(s);
}

/// First date within [window] characters after any of [labels].
DateTime? dateAfter(String text, List<String> labels, {int window = 40}) {
  final lower = text.toLowerCase();
  for (final label in labels) {
    final i = lower.indexOf(label);
    if (i < 0) continue;
    final start = i + label.length;
    final end = (start + window).clamp(0, text.length);
    final found = datesIn(text.substring(start, end));
    if (found.isNotEmpty) return found.first;
  }
  return null;
}

/// Masked card or account digits: "XX1234", "xx 4821", "*7788", "ending 4821",
/// "ending with 4821", "no. XXXXXXXX1234".
final _maskedDigitsRe = RegExp(
  r'(?:[x*•]{1,}\s*|ending(?:\s+with)?\s*(?:no\.?\s*)?|ending in\s*)(\d{3,6})\b',
  caseSensitive: false,
);

String? _digitsNear(String text, RegExp context) {
  for (final m in context.allMatches(text)) {
    final after = text.substring(m.end);
    final window = after.substring(0, after.length.clamp(0, 40));
    final masked = _maskedDigitsRe.firstMatch(window);
    if (masked != null) return masked.group(1);
    // "HDFC Bank Card 4821", "A/c no. 1234".
    final plain = RegExp(
      r'^\s*(?:no\.?\s*|number\s*)?(\d{4})\b',
      caseSensitive: false,
    ).firstMatch(window);
    if (plain != null) return plain.group(1);
  }
  return null;
}

final _cardContextRe = RegExp(
  r'credit\s*card|\bcard\b(?!\s*holder)',
  caseSensitive: false,
);
final _debitCardRe = RegExp(r'debit\s*card', caseSensitive: false);
final _accountContextRe = RegExp(
  r'\ba/c\b|\bacct\b|\baccount\b|\bac\b|\bsb\s*a/c',
  caseSensitive: false,
);

bool _has(String text, String pattern) =>
    RegExp(pattern, caseSensitive: false).hasMatch(text);

const _banks = {
  'HDFC Bank': ['hdfc'],
  'SBI Card': ['sbicrd', 'sbi card', 'sbicard'],
  'SBI': ['sbiinb', 'sbibnk', 'state bank', 'sbiupi', 'sbipsg', ' sbi '],
  'ICICI Bank': ['icici'],
  'Axis Bank': ['axis'],
  'Kotak': ['kotak'],
  'AU Bank': ['aubank', 'au small', 'au bank'],
  'IDFC FIRST': ['idfc'],
  'American Express': ['amex', 'american express', 'americanexpress'],
  'OneCard': ['onecard', 'one card'],
  'RBL Bank': ['rbl'],
  'IndusInd': ['indus'],
  'Yes Bank': ['yesbnk', 'yes bank'],
  'HSBC': ['hsbc'],
  'Standard Chartered': ['scbank', 'standard chartered', 'stanchart'],
  'Federal Bank': ['federal', 'fedbnk'],
  'Canara Bank': ['canara', 'canbnk'],
  'Bank of Baroda': ['baroda', 'bobcrd', 'bobcard', 'bobtxn'],
  'PNB': ['pnb', 'punjab national'],
  'Union Bank': ['union bank', 'unionb', 'ubiin'],
  'Bank of India': ['bank of india', 'boiind'],
  'IDBI': ['idbi'],
  'Indian Bank': ['indian bank', 'indbnk'],
  'Karnataka Bank': ['karnataka bank', 'ktkbnk'],
};

/// Bank name from the sender id ("AD-HDFCBK") or the text.
String? detectBank(String sender, String text) {
  final hay = ' ${sender.toLowerCase()} ${text.toLowerCase()} ';
  for (final e in _banks.entries) {
    if (e.value.any(hay.contains)) return e.key;
  }
  return null;
}

/// Payee or merchant: "at AMAZON PAY", "to SWIGGY", "Info: UPI/zomato",
/// "towards Netflix", "VPA abc@ybl".
String? _merchant(String text) {
  final patterns = [
    RegExp(
      r'\bat\s+([A-Za-z0-9][A-Za-z0-9 &._\-/*@]{1,40}?)'
      r'(?=\s+(?:on|dated|at|for|ref|via|using|txn|is|avl|available)\b|[.,;]|\s*$)',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:to|towards|trf to|paid to)\s+(?:vpa\s+)?'
      r'([A-Za-z0-9][A-Za-z0-9 &._\-/@]{1,40}?)'
      r'(?=\s+(?:on|dated|ref\w*|via|upi|for|from|is|avl|available)\b|[.,;(]|\s*$)',
      caseSensitive: false,
    ),
    RegExp(
      r'\bon\s+([A-Z][A-Za-z0-9 &._\-*]{2,40}?)(?=\s*[.,;]|\s+(?:avl|available)\b|\s*$)',
    ),
    RegExp(
      r'\binfo[:\s-]+([A-Za-z0-9][A-Za-z0-9 &._\-/@]{1,40}?)(?=[.,;]|\s*$)',
      caseSensitive: false,
    ),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(text);
    if (m == null) continue;
    final name = m.group(1)!.trim();
    // Skip things that are not names (e.g. "to your account", "at 10:15").
    if (RegExp(
      r'^(your|you|the|a/c|ac|account|card|\d)',
      caseSensitive: false,
    ).hasMatch(name)) {
      continue;
    }
    return name;
  }
  return null;
}

/// When the text names the transaction date, that date (if plausible);
/// otherwise the day the message arrived.
DateTime _eventDate(String text, DateTime received) {
  final r = dateOnly(received);
  for (final d in datesIn(text)) {
    final diff = r.difference(d).inDays;
    if (diff >= -1 && diff <= 400) return d;
  }
  return r;
}

// ---- Classification ----------------------------------------------------------

final _ignoreRe = RegExp(
  r'\botp\b|one[\s-]?time[\s-]?password|verification code|do not share'
  r'|declined|failed|unsuccessful|not processed|insufficient|blocked'
  r'|will be debited|will be auto[\s-]?debited|is due on|reminder'
  r'|request(?:ed)? (?:of|for) rs|has requested|collect request'
  r'|pre-?approved|offer|apply now|eligible|win |congratulations|voucher',
  caseSensitive: false,
);

/// Parses one bank message. Returns null for anything that is not a
/// completed transaction or a card statement (OTPs, offers, reminders,
/// declined transactions, ...).
BankEvent? parseBankMessage(
  String body, {
  required DateTime received,
  String sender = '',
}) {
  final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty || _txnAmount(text) == null) return null;
  final bank = detectBank(sender, text);

  final statement = _parseStatement(text, bank);
  if (statement != null) return statement;
  if (_ignoreRe.hasMatch(text)) return null;

  // A debit from a bank account that pays a card mentions both; the account
  // side wins ("Rs X debited from A/c XX1234 towards Credit Card XX4821").
  final fromAccount = _has(
    text,
    r'from\s+(?:your\s+)?(?:hdfc bank\s+|sbi\s+)?(?:a/c|acct|account|ac)\b'
    r'|(?:a/c|acct|account)\s*(?:no\.?)?\s*[x*]*\d{3,}\s+(?:is\s+|has been\s+)?(?:debited|credited)',
  );
  final isCredit =
      !fromAccount &&
      _cardContextRe.hasMatch(text) &&
      !_debitCardRe.hasMatch(text) &&
      _has(
        text,
        r'credit\s*card|\bcard\s*(?:no\.?\s*)?(?:ending|[x*•]|\d{4}\b)',
      );
  if (isCredit) return _parseCard(text, received, bank);
  return _parseAccount(text, received, bank);
}

BankEvent? _parseStatement(String text, String? bank) {
  if (!_has(text, r'statement|stmt|\bbill\b')) return null;
  final total = amountAfter(text, [
    'total amount due',
    'total amt due',
    'total amt. due',
    'total due',
    'total payment due',
    'tad',
    'amount due',
    'amt due',
    'bill amount',
    'billed amount',
    'bill of',
  ]);
  final due = dateAfter(text, [
    'payment due date',
    'due date',
    'due by',
    'due on',
    'pay by',
    'payable by',
    'before',
  ]);
  if (total == null || due == null) return null;
  final digits =
      _digitsNear(text, _cardContextRe) ??
      _maskedDigitsRe.firstMatch(text)?.group(1);
  if (digits == null) return null;
  return BankEvent(
    kind: BankEventKind.cardBill,
    amount: total,
    date: due,
    digits: digits,
    bank: bank,
    minDue: amountAfter(text, [
      'minimum amount due',
      'min amount due',
      'minimum amt due',
      'min amt due',
      'min. amt. due',
      'minimum due',
      'min due',
      'mad',
    ]),
    dueDate: due,
    statementDate: dateAfter(text, [
      'statement date',
      'stmt date',
      'generated on',
      'dated',
    ]),
  );
}

BankEvent? _parseCard(String text, DateTime received, String? bank) {
  final digits =
      _digitsNear(text, _cardContextRe) ??
      _maskedDigitsRe.firstMatch(text)?.group(1);
  if (digits == null) return null;
  final amount = _txnAmount(text);
  if (amount == null || amount == 0) return null;
  final avl = amountAfter(text, [
    'available credit limit',
    'avl cr lmt',
    'avl. cr. lmt',
    'avl lmt',
    'avl limit',
    'available limit',
    'avbl lmt',
    'available balance',
    'avl bal',
  ]);
  final date = _eventDate(text, received);

  final BankEventKind kind;
  if (_has(
    text,
    r'payment\s+(?:of\s+)?(?:rs\.?|inr|₹)?\s*[0-9,.]*\s*(?:has been\s+|is\s+)?'
    r'(?:received|credited|successful|processed)'
    r'|received\s+(?:a\s+)?payment|thank\s*(?:you|s)\s+for\s+(?:the\s+|your\s+)?payment'
    r'|payment\s+(?:towards|to|on)\s+your',
  )) {
    kind = BankEventKind.cardPayment;
  } else if (_has(
    text,
    r'refund|reversal|reversed|credited to your|cashback',
  )) {
    kind = BankEventKind.cardRefund;
  } else if (_has(
    text,
    r'spent|used|debited|purchase|\btxn\b|transaction|charged|paid|made a',
  )) {
    kind = BankEventKind.cardSpend;
  } else {
    return null;
  }
  return BankEvent(
    kind: kind,
    amount: amount,
    date: date,
    digits: digits,
    bank: bank,
    description: kind == BankEventKind.cardSpend ? _merchant(text) : null,
    availableLimit: avl,
  );
}

BankEvent? _parseAccount(String text, DateTime received, String? bank) {
  final digits =
      _digitsNear(text, _accountContextRe) ?? _digitsNear(text, _debitCardRe);
  if (digits == null) return null;
  final amount = _txnAmount(text);
  if (amount == null || amount == 0) return null;

  // Debit or credit: whichever word comes first decides ("debited from your
  // a/c ... and credited to X" is a debit).
  final lower = text.toLowerCase();
  int first(List<String> words) {
    var best = -1;
    for (final w in words) {
      final i = RegExp('\\b$w\\b').firstMatch(lower)?.start ?? -1;
      if (i >= 0 && (best < 0 || i < best)) best = i;
    }
    return best;
  }

  final debitAt = first([
    'debited',
    'withdrawn',
    'sent',
    'spent',
    'paid',
    'deducted',
    'transferred',
    'dr',
    'purchase',
    'used',
  ]);
  final creditAt = first(['credited', 'received', 'deposited', 'cr', 'added']);
  if (debitAt < 0 && creditAt < 0) return null;
  final isDebit = creditAt < 0 || (debitAt >= 0 && debitAt < creditAt);

  final paysCard =
      isDebit &&
      _has(
        text,
        r'credit\s*card|card\s*(?:bill|payment|dues)|\bcc\b|towards\s+card',
      );
  String? cardDigits;
  if (paysCard) {
    final cardPart = RegExp(
      r'(?:credit\s*card|card)[^0-9]{0,25}?(\d{4})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (cardPart != null && cardPart.group(1) != digits) {
      cardDigits = cardPart.group(1);
    }
  }

  return BankEvent(
    kind: isDebit ? BankEventKind.accountDebit : BankEventKind.accountCredit,
    amount: amount,
    date: _eventDate(text, received),
    digits: digits,
    bank: bank,
    description: _merchant(text),
    balance: amountAfter(text, [
      'avl bal',
      'avl. bal',
      'available balance',
      'avbl bal',
      'a/c bal',
      'balance is',
      'bal:',
      'bal ',
    ]),
    paysCard: paysCard,
    cardDigits: cardDigits,
  );
}

/// Whether two trailing-digit strings refer to the same number ("1234" and
/// "01234" match; at least three digits must overlap).
bool digitsMatch(String a, String b) {
  if (a.isEmpty || b.isEmpty) return false;
  final shorter = a.length <= b.length ? a : b;
  final longer = a.length <= b.length ? b : a;
  if (shorter.length < 3) return a == b;
  return longer.endsWith(shorter);
}
