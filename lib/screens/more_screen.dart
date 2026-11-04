import 'package:flutter/material.dart';

import '../widgets/design.dart';
import 'accounts_screen.dart';
import 'auto_detect_screen.dart';
import 'budgets_screen.dart';
import 'goals_screen.dart';
import 'home_screen.dart';
import 'import_screen.dart';
import 'insights_screen.dart';
import 'investments_screen.dart';
import 'loans_screen.dart';
import 'recurring_screen.dart';
import 'settings_screen.dart';
import '../l10n/strings.dart';
import '../sync/sms_sync.dart';

/// Every other part of the app, in three short groups.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget item(IconData icon, String label, Widget screen) => ListTile(
      leading: IconBadge(icon, size: 38),
      title: Text(label),
      trailing: Icon(Icons.chevron_right, color: scheme.outline),
      onTap: () => push(context, screen),
    );
    Widget group(String title, List<Widget> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: items),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(tr('More'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          group(tr('Money'), [
            item(
              Icons.account_balance_outlined,
              tr('Accounts'),
              const AccountsScreen(),
            ),
            item(
              Icons.trending_up_rounded,
              tr('Investments'),
              const InvestmentsScreen(),
            ),
            item(
              Icons.event_repeat_outlined,
              tr('Loans & EMIs'),
              const LoansScreen(),
            ),
            item(
              Icons.savings_outlined,
              tr('Savings goals'),
              const GoalsScreen(),
            ),
          ]),
          group(tr('Plan'), [
            item(
              Icons.donut_large_outlined,
              tr('Budgets'),
              const BudgetsScreen(),
            ),
            item(
              Icons.repeat_rounded,
              tr('Recurring'),
              const RecurringScreen(),
            ),
            item(
              Icons.insights_outlined,
              tr('Insights'),
              const InsightsScreen(),
            ),
          ]),
          group(tr('Data'), [
            item(
              Icons.auto_awesome_outlined,
              SmsSync.available
                  ? tr('Automatic (SMS, Gmail)')
                  : tr('Automatic (statements)'),
              const AutoDetectScreen(),
            ),
            item(
              Icons.upload_file_outlined,
              tr('Import statement'),
              const ImportScreen(),
            ),
            ListTile(
              leading: const IconBadge(Icons.translate, size: 38),
              title: Text(tr('Language')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentLanguageName(),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  Icon(Icons.chevron_right, color: scheme.outline),
                ],
              ),
              onTap: () => showLanguagePicker(context),
            ),
            item(
              Icons.settings_outlined,
              tr('Settings'),
              const SettingsScreen(),
            ),
          ]),
        ],
      ),
    );
  }
}
