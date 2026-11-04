import 'package:flutter_test/flutter_test.dart';
import 'package:rupeetrack/sync/bank_messages.dart';

final received = DateTime(2026, 10, 30, 18, 30);
DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

BankEvent? parse(String body, {String sender = ''}) =>
    parseBankMessage(body, received: received, sender: sender);

void main() {
  group('card spends', () {
    test('HDFC (card digits without mask, ISO date)', () {
      final e = parse(
        'Spent Rs.499.00 On HDFC Bank Card 4821 At AMAZON PAY INDIA On '
        '2026-10-29:14:22:05 Bal Rs.115151.00 Not You? Call 18002586161',
        sender: 'AD-HDFCBK',
      )!;
      expect(e.kind, BankEventKind.cardSpend);
      expect(e.amount, 49900);
      expect(e.digits, '4821');
      expect(e.date, d(2026, 10, 29));
      expect(e.bank, 'HDFC Bank');
      expect(e.description, 'AMAZON PAY INDIA');
    });

    test('SBI Card', () {
      final e = parse(
        'Rs.1,499.00 spent on your SBI Credit Card ending 1190 at SWIGGY on '
        '25/10/26. Trxn. Not done by you? Report at https://sbicard.com/Dispute',
        sender: 'VM-SBICRD',
      )!;
      expect(e.kind, BankEventKind.cardSpend);
      expect(e.amount, 149900);
      expect(e.digits, '1190');
      expect(e.date, d(2026, 10, 25));
      expect(e.bank, 'SBI Card');
      expect(e.description, 'SWIGGY');
    });

    test('ICICI with available limit and merchant after "on"', () {
      final e = parse(
        'INR 2,499.00 spent using ICICI Bank Card XX4003 on 29-Oct-26 on '
        'AMAZON. Avl Limit: INR 1,38,000.00. If not you, call 1800 2662/SMS '
        'BLOCK 4003 to 9215676766.',
        sender: 'JD-ICICIT',
      )!;
      expect(e.kind, BankEventKind.cardSpend);
      expect(e.amount, 249900);
      expect(e.digits, '4003');
      expect(e.date, d(2026, 10, 29));
      expect(e.availableLimit, 13800000);
      expect(e.description, 'AMAZON');
    });

    test('Axis and Kotak wordings', () {
      final axis = parse(
        'INR 850.00 spent on credit card no. XX7788 on 28-10-26 at ZOMATO. '
        'Avl Lmt INR 45,150.00',
      )!;
      expect(axis.kind, BankEventKind.cardSpend);
      expect(axis.digits, '7788');
      expect(axis.description, 'ZOMATO');
      expect(axis.availableLimit, 4515000);

      final kotak = parse(
        'Spent Rs.250.00 at ZOMATO on 30-10-2026 using Kotak Credit Card '
        'x7766. Avl limit Rs.98,000',
      )!;
      expect(kotak.kind, BankEventKind.cardSpend);
      expect(kotak.digits, '7766');
      expect(kotak.bank, 'Kotak');
    });
  });

  group('card payments, refunds and bills', () {
    test('payment received', () {
      final e = parse(
        'Payment of Rs. 30,150.00 has been received on your HDFC Bank Credit '
        'Card ending 4821 on 29-10-2026. Thank you.',
      )!;
      expect(e.kind, BankEventKind.cardPayment);
      expect(e.amount, 3015000);
      expect(e.digits, '4821');
    });

    test('refund', () {
      final e = parse(
        'Refund of Rs.499.00 from AMAZON has been credited to your ICICI Bank '
        'Credit Card XX4003 on 30-Oct-26.',
      )!;
      expect(e.kind, BankEventKind.cardRefund);
      expect(e.amount, 49900);
      expect(e.digits, '4003');
    });

    test('statement with total, minimum and due date', () {
      final e = parse(
        'Statement for your HDFC Bank Credit Card ending 4821 has been '
        'generated. Total Amount Due: Rs.30,150.00, Minimum Amount Due: '
        'Rs.1,510.00. Payment Due Date: 05-11-2026.',
      )!;
      expect(e.kind, BankEventKind.cardBill);
      expect(e.amount, 3015000);
      expect(e.minDue, 151000);
      expect(e.dueDate, d(2026, 11, 5));
      expect(e.digits, '4821');
    });

    test('SBI Card e-statement with statement date', () {
      final e = parse(
        'E-statement of SBI Credit Card ending 1190 dated 20/10/2026 sent to '
        'your email. Total Amt Due Rs.12,500; Min Amt Due Rs.625; Payable by '
        '09/11/2026.',
      )!;
      expect(e.kind, BankEventKind.cardBill);
      expect(e.amount, 1250000);
      expect(e.minDue, 62500);
      expect(e.dueDate, d(2026, 11, 9));
      expect(e.statementDate, d(2026, 10, 20));
    });

    test('a bill reminder still gives the bill', () {
      final e = parse(
        'Your HDFC Bank Credit Card XX4821 bill of Rs.30,150 is due on '
        '05-11-2026. Pay now to avoid late fee.',
      )!;
      expect(e.kind, BankEventKind.cardBill);
      expect(e.amount, 3015000);
      expect(e.dueDate, d(2026, 11, 5));
    });
  });

  group('bank accounts', () {
    test('SBI UPI debit without currency sign', () {
      final e = parse(
        'Dear UPI user A/C X1234 debited by 250.0 on date 30Oct26 trf to '
        'SWIGGY Refno 612345678901. If not u? call 1800111109. -SBI',
      )!;
      expect(e.kind, BankEventKind.accountDebit);
      expect(e.amount, 25000);
      expect(e.digits, '1234');
      expect(e.date, d(2026, 10, 30));
      expect(e.description, 'SWIGGY');
    });

    test('HDFC UPI sent', () {
      final e = parse(
        'Sent Rs.500.00 From HDFC Bank A/C *1234 To RAHUL KUMAR On 29/10/26 '
        'Ref 612345678901 Not You? Call 18002586161/SMS BLOCK UPI to '
        '7308080808',
      )!;
      expect(e.kind, BankEventKind.accountDebit);
      expect(e.amount, 50000);
      expect(e.digits, '1234');
      expect(e.description, 'RAHUL KUMAR');
    });

    test('salary credit with balance', () {
      final e = parse(
        'Your A/C XXXXX1234 Credited INR 85,000.00 on 01/10/26 -Deposit by '
        'transfer from ACME CORP. Avl Bal INR 95,532.00 -SBI',
      )!;
      expect(e.kind, BankEventKind.accountCredit);
      expect(e.amount, 8500000);
      expect(e.balance, 9553200);
      expect(e.date, d(2026, 10, 1));
    });

    test('card bill paid from the bank account', () {
      final e = parse(
        'Rs.30150.00 debited from A/c XX1234 on 29-10-26 towards HDFC Bank '
        'Credit Card XX4821 payment. Avl bal Rs.65,382.00',
      )!;
      expect(e.kind, BankEventKind.accountDebit);
      expect(e.digits, '1234');
      expect(e.paysCard, isTrue);
      expect(e.cardDigits, '4821');
    });
  });

  group('ignored', () {
    for (final (name, body) in [
      (
        'OTP',
        '123456 is your OTP for txn of Rs.499 at AMAZON on HDFC Bank Card '
            'xx4821. Do not share it with anyone.',
      ),
      (
        'offer',
        'Get a pre-approved loan of Rs 2,00,000 on your credit card. Apply '
            'now!',
      ),
      ('declined', 'Txn of Rs.499 on card xx4821 declined due to wrong PIN.'),
      (
        'collect request',
        'RAHUL has requested Rs.500 from your A/c XX1234 via UPI. Ignore if '
            'not you.',
      ),
      ('no amount', 'Your HDFC Bank Credit Card xx4821 is now active.'),
    ]) {
      test(name, () => expect(parse(body), isNull));
    }
  });

  test('digitsMatch', () {
    expect(digitsMatch('1234', '1234'), isTrue);
    expect(digitsMatch('01234', '1234'), isTrue);
    expect(digitsMatch('234', '1234'), isTrue);
    expect(digitsMatch('1234', '5234'), isFalse);
    expect(digitsMatch('34', '1234'), isFalse);
  });
}
