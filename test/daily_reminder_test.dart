import 'package:flutter_test/flutter_test.dart';
import 'package:rupeetrack/app/notifications.dart';

void main() {
  test('next reminder is later today or tomorrow', () {
    final morning = DateTime(2026, 11, 4, 8);
    expect(nextDailyReminder(21 * 60, morning), DateTime(2026, 11, 4, 21));
    final night = DateTime(2026, 11, 4, 22);
    expect(nextDailyReminder(21 * 60, night), DateTime(2026, 11, 5, 21));
    final monthEnd = DateTime(2026, 11, 30, 23);
    expect(
      nextDailyReminder(21 * 60 + 30, monthEnd),
      DateTime(2026, 12, 1, 21, 30),
    );
  });

  test('times read like 9 PM', () {
    expect(formatReminderTime(21 * 60), '9 PM');
    expect(formatReminderTime(21 * 60 + 5), '9:05 PM');
    expect(formatReminderTime(0), '12 AM');
    expect(formatReminderTime(12 * 60), '12 PM');
    expect(formatReminderTime(8 * 60 + 30), '8:30 AM');
  });
}
