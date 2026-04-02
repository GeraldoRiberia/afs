import 'package:flutter/material.dart';

import '../theme.dart';
import 'shared_widgets.dart';
import 'login_screen.dart';

/// Updated Extended Onboarding Flow — 3 step page view
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _ctrl = PageController();
  int _page = 0;

  static const List<_OnboardPage> _pages = [
    _OnboardPage(
      icon: Icons.track_changes_rounded,
      tag: 'AUTO FRAMING',
      headline: 'The camera finds you.',
      body:
          'No operator. No tripod wrestling. Just professional framing in every movement.',
    ),
    _OnboardPage(
      icon: Icons.center_focus_strong_rounded,
      tag: 'CENTER STAGE',
      headline: 'Always in the\nperfect shot.',
      body:
          'Our Center Stage engine calculates zoom and pan continuously so the subject is never lost — even at the edges.',
    ),
    _OnboardPage(
      icon: Icons.tune_rounded,
      tag: 'FULL CONTROL',
      headline: 'Your framing,\nyour rules.',
      body:
          'Switch between Single-face and Multi-group modes, adjust tracking sensitivity, and choose any connected camera.',
    ),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _pages.length - 1) {
      _ctrl.nextPage(
          duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AfsScaffold(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          children: [
            // AFS logo mark
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AfsTheme.neonGreen,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: AfsTheme.neonGreen.withAlpha(180),
                          blurRadius: 10)
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text('AFS', style: AfsTheme.monoMedium(AfsTheme.neonGreen)),
              ],
            ),

            const SizedBox(height: 32),

            // Page content
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _OnboardPageView(page: _pages[i]),
              ),
            ),

            const SizedBox(height: 32),

            // Dot indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 22 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? AfsTheme.neonGreen
                        : AfsTheme.surfaceBright,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            AfsPrimaryButton(
              label: _page == _pages.length - 1 ? 'Get Started' : 'Next',
              icon: _page == _pages.length - 1
                  ? Icons.rocket_launch_rounded
                  : Icons.arrow_forward_rounded,
              onPressed: _next,
            ),

            const SizedBox(height: 12),

            TextButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen())),
              child: Text(
                'Skip',
                style: AfsTheme.bodySmall(AfsTheme.ashGray.withAlpha(120)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardPage {
  final IconData icon;
  final String tag;
  final String headline;
  final String body;
  const _OnboardPage(
      {required this.icon,
      required this.tag,
      required this.headline,
      required this.body});
}

class _OnboardPageView extends StatelessWidget {
  final _OnboardPage page;
  const _OnboardPageView({required this.page});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Icon with glow
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AfsTheme.neonGreen.withAlpha(18),
            shape: BoxShape.circle,
            border: Border.all(
                color: AfsTheme.neonGreen.withAlpha(60), width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: AfsTheme.neonGreen.withAlpha(40),
                  blurRadius: 30,
                  spreadRadius: 6)
            ],
          ),
          child: Icon(page.icon, size: 42, color: AfsTheme.neonGreen),
        ),

        const SizedBox(height: 28),

        // Tag chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AfsTheme.neonGreen.withAlpha(20),
            borderRadius: BorderRadius.circular(999),
            border:
                Border.all(color: AfsTheme.neonGreen.withAlpha(60), width: 1),
          ),
          child: Text(page.tag, style: AfsTheme.monoSmall(AfsTheme.neonGreen)),
        ),

        const SizedBox(height: 20),

        Text(
          page.headline,
          textAlign: TextAlign.center,
          style: AfsTheme.displaySmall(AfsTheme.ashGray).copyWith(height: 1.2),
        ),

        const SizedBox(height: 16),

        Text(
          page.body,
          textAlign: TextAlign.center,
          style: AfsTheme.bodyMedium(AfsTheme.mintGreen),
        ),
      ],
    );
  }
}
