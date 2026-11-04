/// Optional Gmail source: reads bank alert emails and statement PDFs with
/// read-only access. Requests go straight from the phone to Google; there is
/// no Rupio server.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'bank_messages.dart';
import 'sync.dart';

/// OAuth "Web application" client id from the Google Cloud project, passed
/// at build time: --dart-define=GMAIL_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com
const gmailWebClientId = String.fromEnvironment('GMAIL_WEB_CLIENT_ID');

const _scope = 'https://www.googleapis.com/auth/gmail.readonly';
const _api = 'https://gmail.googleapis.com/gmail/v1/users/me';

/// Senders and subjects that bank alerts and statements use.
const _query =
    '(from:(alerts OR alert OR hdfcbank OR icicibank OR sbicard OR '
    'axisbank OR kotak OR idfcfirstbank OR aubank OR americanexpress OR '
    'indusind OR yesbank OR rblbank OR hsbc OR sc.com OR getonecard OR '
    'federalbank OR canarabank OR bankofbaroda OR pnb OR unionbank OR '
    'onlinesbi OR sbi.co.in) OR subject:(statement OR "credit card" OR '
    'transaction OR debited OR credited OR spent))';

class StatementAttachment {
  const StatementAttachment({
    required this.messageId,
    required this.fileName,
    required this.sender,
    required this.received,
    required this.data,
  });
  final String messageId;
  final String fileName;
  final String sender;
  final DateTime received;
  final Uint8List data;
}

class GmailScan {
  const GmailScan(this.events, this.statements, this.scanned, this.account);

  /// Transactions and bills read from alert emails.
  final List<SourcedEvent> events;

  /// PDF statements found (usually password-protected).
  final List<StatementAttachment> statements;
  final int scanned;
  final String account;
}

class GmailSync {
  static bool get configured => gmailWebClientId.isNotEmpty;
  static bool _initialised = false;
  static GoogleSignInAccount? _account;

  static Future<void> _init() async {
    if (_initialised) return;
    await GoogleSignIn.instance.initialize(serverClientId: gmailWebClientId);
    _initialised = true;
  }

  /// Signs in (showing Google's account picker and consent screen when
  /// [interactive]) and returns an access token for read-only Gmail.
  static Future<String> _token({required bool interactive}) async {
    await _init();
    var account =
        _account ??
        await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (account == null) {
      if (!interactive) throw StateError('Not connected');
      account = await GoogleSignIn.instance.authenticate(scopeHint: [_scope]);
    }
    _account = account;
    final client = account.authorizationClient;
    final auth =
        await client.authorizationForScopes([_scope]) ??
        (interactive
            ? await client.authorizeScopes([_scope])
            : throw StateError('Gmail access not granted'));
    return auth.accessToken;
  }

  static String? get connectedEmail => _account?.email;

  static Future<void> disconnect() async {
    await _init();
    await GoogleSignIn.instance.disconnect();
    _account = null;
  }

  /// Reads up to [maxMessages] recent bank emails from the last [days].
  static Future<GmailScan> scan({
    int days = 180,
    int maxMessages = 150,
    bool interactive = true,
    http.Client? client,
  }) async {
    final token = await _token(interactive: interactive);
    final c = client ?? http.Client();
    final headers = {'Authorization': 'Bearer $token'};
    Future<Map<String, dynamic>> get(String path) async {
      final r = await c
          .get(Uri.parse('$_api/$path'), headers: headers)
          .timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) {
        throw http.ClientException('Gmail returned HTTP ${r.statusCode}');
      }
      return jsonDecode(r.body) as Map<String, dynamic>;
    }

    try {
      final ids = <String>[];
      String? pageToken;
      do {
        final q = Uri.encodeQueryComponent('newer_than:${days}d $_query');
        final page = await get(
          'messages?q=$q&maxResults=100'
          '${pageToken == null ? '' : '&pageToken=$pageToken'}',
        );
        for (final m in (page['messages'] as List?) ?? const []) {
          ids.add((m as Map)['id'] as String);
        }
        pageToken = page['nextPageToken'] as String?;
      } while (pageToken != null && ids.length < maxMessages);

      final events = <SourcedEvent>[];
      final statements = <StatementAttachment>[];
      for (final id in ids.take(maxMessages)) {
        final msg = await get('messages/$id?format=full');
        final payload = msg['payload'] as Map<String, dynamic>;
        String header(String name) =>
            ((payload['headers'] as List?) ?? const [])
                .cast<Map<String, dynamic>>()
                .where((h) => (h['name'] as String).toLowerCase() == name)
                .map((h) => h['value'] as String)
                .firstOrNull ??
            '';
        final from = header('from');
        final subject = header('subject');
        final received = DateTime.fromMillisecondsSinceEpoch(
          int.parse(msg['internalDate'] as String),
        );

        final texts = <String>[];
        final pdfs = <(String, String)>[]; // (file name, attachment id)
        void walk(Map<String, dynamic> part) {
          final mime = (part['mimeType'] as String?) ?? '';
          final body = (part['body'] as Map?)?.cast<String, dynamic>() ?? {};
          final name = (part['filename'] as String?) ?? '';
          if (mime == 'application/pdf' ||
              name.toLowerCase().endsWith('.pdf')) {
            final aid = body['attachmentId'] as String?;
            if (aid != null) pdfs.add((name, aid));
          } else if (body['data'] != null &&
              (mime == 'text/plain' || mime == 'text/html')) {
            final raw = utf8.decode(
              base64Url.decode(base64Url.normalize(body['data'] as String)),
              allowMalformed: true,
            );
            texts.add(mime == 'text/html' ? htmlToText(raw) : raw);
          }
          for (final p in (part['parts'] as List?) ?? const []) {
            walk((p as Map).cast<String, dynamic>());
          }
        }

        walk(payload);
        final text = '$subject. ${texts.isEmpty ? '' : texts.first}';
        final e = parseBankMessage(text, received: received, sender: from);
        if (e != null) events.add(SourcedEvent('mail:$id', e));

        for (final (name, aid) in pdfs) {
          final att = await get('messages/$id/attachments/$aid');
          statements.add(
            StatementAttachment(
              messageId: id,
              fileName: name.isEmpty ? 'statement.pdf' : name,
              sender: from,
              received: received,
              data: base64Url.decode(
                base64Url.normalize(att['data'] as String),
              ),
            ),
          );
        }
      }
      return GmailScan(events, statements, ids.length, _account?.email ?? '');
    } finally {
      if (client == null) c.close();
    }
  }
}

/// Plain text from an HTML email body, enough for the message parser.
String htmlToText(String html) => html
    .replaceAll(
      RegExp(
        r'<(script|style)[^>]*>.*?</\1>',
        caseSensitive: false,
        dotAll: true,
      ),
      ' ',
    )
    .replaceAll(
      RegExp(r'<br\s*/?>|</p>|</tr>|</div>', caseSensitive: false),
      '\n',
    )
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&#8377;', '₹')
    .replaceAll('&#x20b9;', '₹')
    .replaceAll(RegExp(r'[ \t]+'), ' ')
    .trim();
