import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'settings_screen.dart';

/// First-run tour: four pages with an app screen, a title and one line,
/// with Skip at the top and Next / Get started at the bottom.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  /// Called after the last page or on Skip.
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Page {
  const _Page(this.image, this.title, this.accent, this.text);
  final String image;
  final String title;
  final String accent;
  final String text;
}

List<_Page> get _pages => [
  _Page(
    'assets/onboarding/1-home.webp',
    tr('Know where every'),
    tr('rupee goes'),
    tr(
      'Your month in one number and one clear graph. Red for spending, green for income.',
    ),
  ),
  _Page(
    'assets/onboarding/7-cards.webp',
    tr('Never miss a'),
    tr('card bill'),
    tr('Bills, due dates and reminders for every credit card.'),
  ),
  _Page(
    'assets/onboarding/5-loans.webp',
    tr('Every EMI and goal,'),
    tr('tracked'),
    tr(
      'See the EMIs left, the month you become debt-free and how much to save.',
    ),
  ),
  _Page(
    'assets/onboarding/4-insights.webp',
    tr('Private, offline,'),
    tr('in your language'),
    tr('No sign-up and no bank login. Your data stays on your phone.'),
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _pages.length - 1) {
      widget.onDone();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => showLanguagePicker(context),
                    icon: const Icon(Icons.translate, size: 18),
                    label: Text(currentLanguageName()),
                  ),
                  const Spacer(),
                  if (!last)
                    TextButton(
                      onPressed: widget.onDone,
                      child: Text(
                        tr('Skip'),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        Expanded(
                          child: Image.asset(
                            p.image,
                            fit: BoxFit.contain,
                            semanticLabel: p.title,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text.rich(
                          TextSpan(
                            text: '${p.title}\n',
                            children: [
                              TextSpan(
                                text: p.accent,
                                style: TextStyle(color: scheme.primary),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          style: t.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          p.text,
                          textAlign: TextAlign.center,
                          style: t.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(last ? tr('Get started') : tr('Next')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
