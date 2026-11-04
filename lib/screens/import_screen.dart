import 'package:flutter/material.dart';

import '../app/files.dart';
import '../app/scope.dart';
import '../app/store.dart';
import '../data/csv.dart';
import '../models/money.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import '../l10n/strings.dart';

/// Import a bank or credit card statement (CSV): choose where it belongs,
/// pick the file, review what will be added, confirm.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  Source? _target;
  StatementImport? _result;
  String? _error;
  bool _busy = false;

  Future<void> _pick() async {
    final target = _target;
    if (target == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final text = await pickTextFile();
      if (text == null || !mounted) return;
      final result = importStatement(
        text,
        accountId: target.accountId,
        cardId: target.cardId,
        existing: context.ledger,
      );
      setState(() => _result = result);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = tr('Could not read the file: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final r = _result!;
    await context.store.addImported(r.txns);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('Imported {0} transactions', [r.txns.length]))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.ledger;
    final t = Theme.of(context).textTheme;
    final result = _result;
    final out = result?.txns.where((x) => txnDirection(x) < 0) ?? const [];
    final inn = result?.txns.where((x) => txnDirection(x) > 0) ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(tr('Import statement'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('1. Which account or card is it for?'),
                  style: t.titleSmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final a in l.accounts)
                      ChoiceChip(
                        showCheckmark: false,
                        avatar: Icon(iconForAccount(a.kind), size: 18),
                        label: Text(a.name),
                        selected: _target == Source.account(a.id),
                        onSelected: (_) => setState(() {
                          _target = Source.account(a.id);
                          _result = null;
                        }),
                      ),
                    for (final c in l.cards)
                      ChoiceChip(
                        showCheckmark: false,
                        avatar: const Icon(Icons.credit_card, size: 18),
                        label: Text(c.displayName),
                        selected: _target == Source.card(c.id),
                        onSelected: (_) => setState(() {
                          _target = Source.card(c.id);
                          _result = null;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(tr('2. Choose the CSV file'), style: t.titleSmall),
                const SizedBox(height: 4),
                Text(
                  tr(
                    'Download the statement as CSV (or Excel saved as CSV) from your net banking. Debit/Credit or Amount columns are detected automatically.',
                  ),
                  style: t.bodySmall,
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _target == null || _busy ? null : _pick,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file),
                  label: Text(tr('Choose file')),
                ),
              ],
            ),
          ),
          if (_error != null)
            Panel(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Text(_error!),
            ),
          if (result != null) ...[
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('3. Review'), style: t.titleSmall),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Figure(tr('New'), '${result.txns.length}'),
                      ),
                      Expanded(
                        child: Figure(
                          tr('Already in app'),
                          '${result.duplicates}',
                        ),
                      ),
                      Expanded(
                        child: Figure(tr('Skipped'), '${result.skipped}'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr('Money out {0} · money in {1}', [
                      formatRupees(out.fold(0, (s, x) => s + x.amount)),
                      formatRupees(inn.fold(0, (s, x) => s + x.amount)),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      'Categories are guessed from the description; tap any entry later to change it.',
                    ),
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: result.txns.isEmpty ? null : _confirm,
                    child: Text(
                      tr('Import {0} transactions', [result.txns.length]),
                    ),
                  ),
                ],
              ),
            ),
            if (result.txns.isNotEmpty)
              Panel(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final x in result.txns.take(30)) TxnTile(x),
                    if (result.txns.length > 30)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          tr('…and {0} more', [result.txns.length - 30]),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
