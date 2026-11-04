import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/native.dart';
import 'app/notifications.dart';
import 'app/scope.dart';
import 'app/store.dart';
import 'app/widget_data.dart';
import 'screens/auto_detect_screen.dart';
import 'screens/cards_screen.dart';
import 'screens/home_screen.dart';
import 'screens/more_screen.dart';
import 'screens/quick_add_sheet.dart';
import 'screens/transactions_screen.dart';
import 'widgets/design.dart';
import 'l10n/strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await FinanceStore.load();
  await store.postDueRecurring(today());
  runApp(RupeeTrackApp(store: store));
  // New bank SMS since the last visit (when turned on).
  backgroundSmsSync(store);
}

class RupeeTrackApp extends StatefulWidget {
  const RupeeTrackApp({super.key, required this.store, this.background = true});
  final FinanceStore store;

  /// Whether to schedule notifications (off in tests).
  final bool background;

  @override
  State<RupeeTrackApp> createState() => _RupeeTrackAppState();
}

class _RupeeTrackAppState extends State<RupeeTrackApp>
    with WidgetsBindingObserver {
  Timer? _debounce;
  // One navigator per language: switching language rebuilds the whole app
  // so that every label is redrawn in the new language.
  final _navigators = <String, GlobalKey<NavigatorState>>{};
  GlobalKey<NavigatorState> get _navigator => _navigators.putIfAbsent(
    widget.store.language,
    GlobalKey<NavigatorState>.new,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.addListener(_onChange);
    _refreshReminders();
    if (widget.background) _listenForShares();
  }

  /// Statement PDFs shared to (or opened with) Rupio.
  void _listenForShares() {
    void open(String? path) {
      final ctx = _navigator.currentContext;
      if (path == null || ctx == null) return;
      handleSharedPdf(ctx, path);
    }

    Native.listenForSharedPdfs(open);
    // Started by a share: wait for the first frame so a dialog can show.
    Native.takeSharedPdf().then(
      (path) => WidgetsBinding.instance.addPostFrameCallback((_) => open(path)),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(_onChange);
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // A new day may have made recurring entries due.
      widget.store.postDueRecurring(today());
      if (widget.background) backgroundSmsSync(widget.store);
      _refreshReminders();
    }
  }

  void _onChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _refreshReminders);
  }

  void _refreshReminders() {
    if (!widget.background) return;
    Reminders.refresh(widget.store);
    updateHomeWidget(widget.store);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return AppScope(
      store: store,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) => MaterialApp(
          key: ValueKey(store.language),
          navigatorKey: _navigator,
          locale: Locale(store.language),
          supportedLocales: [for (final l in appLanguages) Locale(l.code)],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          title: 'Rupio – ${tr('Expense Tracker')}',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: store.themeMode,
          home: const HomeShell(),
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  void _openTab(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onOpenTab: _openTab),
      const TransactionsScreen(),
      const CardsScreen(),
      const MoreScreen(),
    ];
    final empty = context.store.isEmpty;
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: empty
          ? null
          : _BottomBar(selected: _tab, onSelected: _openTab),
    );
  }
}

/// Four destinations with the round add button in the middle.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.selected, required this.onSelected});
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tab(int i, IconData icon, IconData active, String label) {
      final on = i == selected;
      final color = on ? scheme.onSurface : scheme.onSurfaceVariant;
      return Expanded(
        child: InkResponse(
          onTap: () => onSelected(i),
          radius: 36,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(on ? active : icon, color: color, size: 24),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              tab(0, Icons.home_outlined, Icons.home_rounded, tr('Home')),
              tab(
                1,
                Icons.receipt_long_outlined,
                Icons.receipt_long_rounded,
                tr('Activity'),
              ),
              const Expanded(child: Center(child: _AddButton())),
              tab(
                2,
                Icons.credit_card_outlined,
                Icons.credit_card_rounded,
                tr('Cards'),
              ),
              tab(
                3,
                Icons.grid_view_outlined,
                Icons.grid_view_rounded,
                tr('More'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round grey + button in the middle of the bottom bar.
class _AddButton extends StatelessWidget {
  const _AddButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 54,
      child: FloatingActionButton(
        tooltip: tr('Add entry'),
        heroTag: null,
        onPressed: () => showQuickAdd(context),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
    );
  }
}
