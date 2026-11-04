import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to MainActivity.kt.
class Native {
  static const _channel = MethodChannel('rupeetrack/native');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Opens the app; returns false (after opening its Play Store page) when
  /// it is not installed.
  static Future<bool> openApp(String package) async {
    if (!supported) return false;
    return await _channel.invokeMethod<bool>('openApp', {'package': package}) ??
        false;
  }

  /// Opens the email app with a draft; false when no email app is set up.
  static Future<bool> sendEmail({
    required String to,
    required String subject,
    required String body,
  }) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('sendEmail', {
            'to': to,
            'subject': subject,
            'body': body,
          }) ??
          false;
    } on Exception {
      return false;
    }
  }

  /// App version, Android version and phone model, for bug reports.
  static Future<Map<String, String>> deviceInfo() async {
    if (!supported) return const {};
    try {
      final m = await _channel.invokeMapMethod<String, String>('deviceInfo');
      return m ?? const {};
    } on Exception {
      return const {};
    }
  }

  static Future<bool> isInstalled(String package) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isInstalled', {
            'package': package,
          }) ??
          false;
    } on Exception {
      // No native side (tests, other platforms).
      return false;
    }
  }

  /// "granted", "denied", or "blocked" (refused for good: only the system
  /// settings can allow it).
  static Future<String> smsPermission() async {
    if (!supported) return 'denied';
    try {
      return await _channel.invokeMethod<String>('smsPermission') ?? 'denied';
    } on Exception {
      return 'denied';
    }
  }

  static Future<String> requestSmsPermission() async {
    if (!supported) return 'denied';
    return await _channel.invokeMethod<String>('requestSmsPermission') ??
        'denied';
  }

  static Future<void> openAppSettings() async {
    if (supported) await _channel.invokeMethod<void>('openAppSettings');
  }

  /// A statement PDF the app was started with (Share / Open with), copied
  /// to the cache folder; null when there is none.
  static Future<String?> takeSharedPdf() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>('takeSharedPdf');
    } on Exception {
      return null;
    }
  }

  /// Calls [onPdf] for PDFs shared while the app is already open.
  static void listenForSharedPdfs(void Function(String path) onPdf) {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedPdf' && call.arguments is String) {
        onPdf(call.arguments as String);
      }
    });
  }

  /// Inbox SMS newer than [since], newest first. Throws [PlatformException]
  /// with code "permission" when SMS access has not been granted.
  static Future<List<SmsMessage>> readSms({
    DateTime? since,
    int limit = 5000,
  }) async {
    if (!supported) return const [];
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'readSms',
      {'since': since?.millisecondsSinceEpoch ?? 0, 'limit': limit},
    );
    return [
      for (final m in raw ?? const <Map<Object?, Object?>>[])
        SmsMessage(
          sender: (m['address'] as String?) ?? '',
          body: (m['body'] as String?) ?? '',
          received: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        ),
    ];
  }

  /// Sends new figures to the home screen widget (no-op elsewhere).
  static Future<void> updateWidget(String json) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('updateWidget', {'json': json});
    } on Exception {
      // No widget support on this build; nothing to update.
    }
  }
}

class SmsMessage {
  const SmsMessage({
    required this.sender,
    required this.body,
    required this.received,
  });
  final String sender;
  final String body;
  final DateTime received;
}
