import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/scope.dart';
import '../app/store.dart';
import '../models/money.dart';
import '../sync/gmail.dart';
import '../sync/sms_sync.dart';
import '../sync/statement_pdf.dart';
import '../sync/sync.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import 'forms.dart';
import '../l10n/strings.dart';

/// One place to fill the app automatically: bank SMS, statement PDFs and
/// (optionally) Gmail. All reading happens on the phone.
class AutoDetectScreen extends StatefulWidget {
  const AutoDetectScreen({super.key});

  @override
  State<AutoDetectScreen> createState() => _AutoDetectScreenState();
}

class _AutoDetectScreenState extends State<AutoDetectScreen> {
  bool _busy = false;
  String? _status;
  List<StatementAttachment> _mailStatements = const [];

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final message = await action();
      if (mounted) setState(() => _status = message);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _status = tr('Could not read: {0}', [e.message]));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = tr('Something went wrong: {0}', [e]));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanSms() => _run(() async {
    final store = context.store;
    if (!await SmsSync.hasPermission()) {
      final state = await SmsSync.requestPermission();
      if (state != 'granted') {
        if (state == 'blocked') {
          await SmsSync.openSettings();
          return tr(
            'Allow "SMS" for Rupio in the settings that opened, then tap Scan again.',
          );
        }
        return tr('SMS access was not allowed.');
      }
    }
    await store.setSmsSync(true);
    final r = await SmsSync.run(store);
    return tr('SMS: {0}', [describeSync(r)]);
  });

  Future<void> _addDetected(String key, DetectedHolding h) async {
    final store = context.store;
    if (h.isCard) {
      await showAddCardDialog(
        context,
        name: h.bank ?? 'Credit card',
        lastFour: h.digits.length > 4
            ? h.digits.substring(h.digits.length - 4)
            : h.digits,
        availableLimit: h.latestFigure,
      );
    } else {
      await showAddAccountDialog(
        context,
        name: h.bank ?? 'Bank account',
        lastFour: h.digits,
        balance: h.latestFigure,
      );
    }
    if (!mounted) return;
    store.dismissDetected(key);
    // Import its history now that it is known.
    if (store.smsSync && await SmsSync.hasPermission()) {
      await _run(
        () async => tr('SMS: {0}', [describeSync(await SmsSync.run(store))]),
      );
    }
  }

  Future<void> _pickPdf() => _run(() async {
    final f = await FilePicker.pickFile(type: FileType.any);
    if (f == null) return null;
    final bytes = await f.readAsBytes();
    if (!mounted) return null;
    final ok = await importStatementPdf(context, bytes, f.name);
    return ok == null ? null : tr('Statement: {0}', [ok]);
  });

  Future<void> _scanGmail() => _run(() async {
    final store = context.store;
    final scan = await GmailSync.scan();
    final r = store.planEvents(scan.events, source: 'email');
    await store.applySync(r);
    if (mounted) setState(() => _mailStatements = scan.statements);
    return tr('Gmail ({0}): {1} emails checked · {2}{3}', [
      scan.account,
      scan.scanned,
      describeSync(r),
      scan.statements.isEmpty
          ? ''
          : ' · ${scan.statements.length} statement PDFs found below',
    ]);
  });

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final detected = store.detected.entries.toList();

    return Scaffold(
      appBar: AppBar(title: Text(tr('Auto-detect'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          HeroPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome, size: 32),
                const SizedBox(height: 10),
                Text(
                  tr('Fill cards and accounts from your bank messages'),
                  style: t.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    'Spends, refunds, bill amounts, due dates and payments are read on this phone. Nothing is uploaded.',
                  ),
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_status != null)
            Panel(color: scheme.primaryContainer, child: Text(_status!)),

          if (SmsSync.available)
            _Section(
              icon: Icons.sms_outlined,
              title: tr('Bank SMS'),
              subtitle: !store.smsSync || store.lastSync == null
                  ? tr(
                      'Reads the last {0} days of bank SMS, then new ones each time you open the app.',
                      [SmsSync.historyDays],
                    )
                  : tr(
                      'On · last checked {0}. New SMS are read each time you open the app.',
                      [relativeDate(store.lastSync!)],
                    ),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _scanSms,
                      icon: const Icon(Icons.search),
                      label: Text(
                        store.smsSync ? tr('Scan now') : tr('Allow SMS & scan'),
                      ),
                    ),
                  ),
                  if (store.smsSync) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => store.setSmsSync(false),
                      child: Text(tr('Turn off')),
                    ),
                  ],
                ],
              ),
            ),

          if (detected.isNotEmpty) ...[
            SectionHeader(tr('Found in your messages')),
            Panel(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final MapEntry(:key, value: h) in detected)
                    ListTile(
                      leading: IconBadge(
                        h.isCard ? Icons.credit_card : Icons.account_balance,
                      ),
                      title: Text(h.label),
                      subtitle: Text(
                        [
                          h.count == 1
                              ? tr('1 message')
                              : tr('{0} messages', [h.count]),
                          if (h.spent > 0)
                            tr('{0} spent', [formatRupees(h.spent)]),
                          if (h.latestFigure != null)
                            h.isCard
                                ? tr('{0} available', [
                                    formatRupees(h.latestFigure!),
                                  ])
                                : tr('balance {0}', [
                                    formatRupees(h.latestFigure!),
                                  ]),
                        ].join(' · '),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: tr('Ignore'),
                            icon: const Icon(Icons.close),
                            onPressed: () => store.dismissDetected(key),
                          ),
                          FilledButton.tonal(
                            onPressed: () => _addDetected(key, h),
                            child: Text(tr('Add')),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],

          _Section(
            icon: Icons.picture_as_pdf_outlined,
            title: tr('Statement PDF'),
            subtitle: tr(
              'Choose a card or bank statement PDF, or share one to Rupio from Gmail, WhatsApp or Files. Password-protected statements are fine.',
            ),
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _pickPdf,
              icon: const Icon(Icons.upload_file),
              label: Text(tr('Choose statement PDF')),
            ),
          ),

          _Section(
            icon: Icons.mail_outline,
            title: tr('Gmail (optional)'),
            subtitle: GmailSync.configured
                ? tr(
                    'Read-only access to bank alert emails and statement PDFs. Google asks you to allow it.',
                  )
                : tr('Needs a one-time Google Cloud setup for this app build.'),
            child: GmailSync.configured
                ? Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _scanGmail,
                          icon: const Icon(Icons.mail),
                          label: Text(
                            GmailSync.connectedEmail == null
                                ? tr('Connect Gmail & scan')
                                : tr('Scan Gmail'),
                          ),
                        ),
                      ),
                      if (GmailSync.connectedEmail != null)
                        TextButton(
                          onPressed: () async {
                            await GmailSync.disconnect();
                            if (mounted) setState(() {});
                          },
                          child: Text(tr('Disconnect')),
                        ),
                    ],
                  )
                : OutlinedButton(
                    onPressed: () => _showGmailSetup(context),
                    child: Text(tr('How to set up')),
                  ),
          ),
          for (final s in _mailStatements)
            Panel(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.picture_as_pdf),
                title: Text(s.fileName),
                subtitle: Text('${s.sender} · ${relativeDate(s.received)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _run(() async {
                  final ok = await importStatementPdf(
                    context,
                    s.data,
                    s.fileName,
                    source: 'mail',
                  );
                  return ok == null ? null : tr('Statement: {0}', [ok]);
                }),
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(icon),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: t.titleMedium)),
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: t.bodyMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

void _showGmailSetup(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Set up Gmail access')),
      scrollable: true,
      content: Text(
        tr(
          'Google only lets apps read Gmail after the developer registers them. For personal use this is free:\n\n1. In console.cloud.google.com create a project and enable the Gmail API.\n2. OAuth consent screen: External, add the gmail.readonly scope and add your Gmail address (up to 100 people) as test users.\n3. Credentials: create an "Android" OAuth client with package com.rupio.app and the app\'s SHA-1 (see the README), and a "Web application" client.\n4. Build the app with the web client id: in the GitHub repository add an Actions variable GMAIL_WEB_CLIENT_ID.\n\nUntil then, statement PDFs can be shared to Rupio from the Gmail app.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('OK')),
        ),
      ],
    ),
  );
}

/// Reads a statement PDF (asking for its password if needed), shows what
/// will be imported and imports it on confirmation. Returns a summary, or
/// null if cancelled.
Future<String?> importStatementPdf(
  BuildContext context,
  Uint8List data,
  String fileName, {
  String source = 'pdf',
}) async {
  final store = context.store;
  String? password;
  String? text;
  var wrong = false;
  while (text == null) {
    try {
      text = await extractPdfText(data, password: password);
    } on StatementPasswordNeeded catch (e) {
      if (!context.mounted) return null;
      wrong = e.wrongPassword;
      password = await _askPassword(context, fileName, wrong: wrong);
      if (password == null) return null;
    }
  }
  final plan = planStatement(text, source: source);
  if (plan == null) {
    return tr('this PDF does not look like a bank or card statement');
  }
  final result = store.planEvents(plan.events, source: tr('statement PDF'));
  if (!context.mounted) return null;
  final confirmed = await _confirmImport(context, plan, result);
  if (confirmed != true) return null;
  await store.applySync(result, remember: false);
  store.mergeDetected(result.unknown);
  return describeSync(result);
}

Future<String?> _askPassword(
  BuildContext context,
  String fileName, {
  required bool wrong,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Statement password')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(fileName, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: InputDecoration(
              labelText: tr('Password'),
              errorText: wrong
                  ? tr('That password did not open the file')
                  : null,
              helperText: tr(
                'Often the first 4 letters of your name + date of birth (e.g. RAHU0105). See your bank\'s email.',
              ),
              helperMaxLines: 3,
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(tr('Open')),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

Future<bool?> _confirmImport(
  BuildContext context,
  StatementImportPlan plan,
  SyncResult r,
) {
  final s = plan.statement;
  final unknownHolding = r.unknown.values.firstOrNull;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(s.isCard ? tr('Card statement') : tr('Bank statement')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('{0}{1} · {2} transactions', [
              s.bank ?? tr('Bank'),
              s.digits == null ? '' : ' ••${s.digits}',
              s.transactionCount,
            ]),
          ),
          const SizedBox(height: 12),
          if (unknownHolding != null)
            Text(
              unknownHolding.isCard
                  ? tr(
                      'This card is not in Rupio yet. Add it (with its last digits) from Auto-detect, then import the statement again.',
                    )
                  : tr(
                      'This account is not in Rupio yet. Add it (with its last digits) from Auto-detect, then import the statement again.',
                    ),
            )
          else ...[
            Text(tr('{0} new entries', [r.added.length])),
            if (r.duplicates > 0)
              Text(tr('{0} already in the app (skipped)', [r.duplicates])),
            if (r.bills.isNotEmpty)
              Text(
                tr('Bill: {0} due {1}', [
                  formatRupees(r.bills.values.first.totalDue),
                  shortDate(r.bills.values.first.dueDate),
                ]),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: unknownHolding != null && r.added.isEmpty
              ? null
              : () => Navigator.pop(context, true),
          child: Text(tr('Import')),
        ),
      ],
    ),
  );
}

/// Opens a PDF shared or "opened with" Rupio.
Future<void> handleSharedPdf(BuildContext context, String path) async {
  final file = File(path);
  if (!await file.exists()) return;
  final bytes = await file.readAsBytes();
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final result = await importStatementPdf(context, bytes, path.split('/').last);
  if (result != null) {
    messenger.showSnackBar(
      SnackBar(content: Text(tr('Statement: {0}', [result]))),
    );
  }
}

/// Runs an SMS sync quietly (app start / resume) when it is turned on.
Future<SyncResult?> backgroundSmsSync(FinanceStore store) async {
  if (!SmsSync.available || !store.smsSync || !await SmsSync.hasPermission()) {
    return null;
  }
  try {
    return await SmsSync.run(store);
  } catch (_) {
    return null;
  }
}
