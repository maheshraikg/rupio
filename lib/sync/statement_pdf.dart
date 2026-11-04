import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import 'statement_text.dart';
import 'sync.dart';

/// Thrown when a statement PDF needs a password, or the one given is wrong.
class StatementPasswordNeeded implements Exception {
  const StatementPasswordNeeded({required this.wrongPassword});
  final bool wrongPassword;
}

/// Text of every page of a PDF, unlocked with [password] when given.
/// Throws [StatementPasswordNeeded] for locked files.
Future<String> extractPdfText(Uint8List data, {String? password}) async {
  await pdfrxFlutterInitialize();
  final PdfDocument doc;
  try {
    doc = await PdfDocument.openData(
      data,
      passwordProvider: createSimplePasswordProvider(password),
      sourceName: 'statement-${data.length}-${password?.length ?? 0}',
    );
  } on PdfPasswordException {
    throw StatementPasswordNeeded(wrongPassword: password != null);
  }
  try {
    final buffer = StringBuffer();
    for (final page in doc.pages) {
      final text = await page.loadText();
      if (text != null) buffer.writeln(text.fullText.replaceAll('\r', ''));
    }
    return buffer.toString();
  } finally {
    await doc.dispose();
  }
}

/// A statement read from a PDF, ready to review and apply.
class StatementImportPlan {
  const StatementImportPlan(this.statement, this.events);
  final StatementText statement;
  final List<SourcedEvent> events;
}

/// Parses statement [text] into keyed events. Keys combine the statement
/// with each line so importing the same PDF twice adds nothing.
StatementImportPlan? planStatement(String text, {String source = 'pdf'}) {
  final s = parseStatementText(text);
  if (s == null) return null;
  final seen = <String, int>{};
  final events = <SourcedEvent>[];
  for (final e in s.events) {
    final base =
        '${s.digits}|${e.kind.name}|${e.date.toIso8601String()}|${e.amount}|${e.description}';
    // Identical lines on one statement are separate transactions.
    final n = seen.update(base, (v) => v + 1, ifAbsent: () => 0);
    events.add(SourcedEvent('$source:${stableHash('$base|$n')}', e));
  }
  return StatementImportPlan(s, events);
}
