import 'package:flutter_test/flutter_test.dart';
import 'package:rupeetrack/models/money.dart';

void main() {
  group('formatRupees', () {
    test('uses Indian digit grouping', () {
      expect(formatRupees(0), '₹0');
      expect(formatRupees(25000), '₹250');
      expect(formatRupees(100000), '₹1,000');
      expect(formatRupees(4825000), '₹48,250');
      expect(formatRupees(16940000), '₹1,69,400');
      expect(formatRupees(1234567800), '₹1,23,45,678');
    });

    test('shows paise only when needed', () {
      expect(formatRupees(9999), '₹99.99');
      expect(formatRupees(9950), '₹99.50');
      expect(formatRupees(25000, alwaysShowPaise: true), '₹250.00');
    });

    test('negative amounts', () {
      expect(formatRupees(-125050), '-₹1,250.50');
    });
  });

  test('formatRupeesCompact', () {
    expect(formatRupeesCompact(95000), '₹950');
    expect(formatRupeesCompact(1250000), '₹12.5K');
    expect(formatRupeesCompact(12000000), '₹1.2L');
    expect(formatRupeesCompact(10000000), '₹1L');
    expect(formatRupeesCompact(3400000000), '₹3.4Cr');
  });

  group('parseRupees', () {
    test('accepts common inputs', () {
      expect(parseRupees('250'), 25000);
      expect(parseRupees(' 1,250.5 '), 125050);
      expect(parseRupees('₹ 99.99'), 9999);
      expect(parseRupees('10.'), 1000);
      expect(parseRupees('0'), 0);
    });

    test('rejects bad input', () {
      expect(parseRupees(''), isNull);
      expect(parseRupees('-5'), isNull);
      expect(parseRupees('1.234'), isNull);
      expect(parseRupees('abc'), isNull);
      expect(parseRupees('1' * 20), isNull);
    });
  });
}
