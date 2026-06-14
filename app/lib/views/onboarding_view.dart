import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kOnboardingDone = 'onboarding_done_v1';

/// Returns true if the user has already completed onboarding.
Future<bool> isOnboardingDone() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kOnboardingDone) ?? false;
}

/// Persists the onboarding-complete flag so [isOnboardingDone] returns true
/// on every subsequent launch.
Future<void> markOnboardingDone() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kOnboardingDone, true);
}

/// Multi-page introduction shown on first launch. Calls [onComplete] when the
/// user finishes or skips.
class OnboardingView extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingView({super.key, required this.onComplete});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.fitness_center,
      iconColor: Colors.redAccent,
      title: 'Welcome to RepIQ',
      body:
          'Your AI-powered lifting coach. Log workouts, get smarter '
          'recommendations every session, and break through plateaus.',
    ),
    _OnboardingPage(
      icon: Icons.add_circle_outline,
      iconColor: Colors.blueAccent,
      title: 'Log Every Set',
      body:
          'Add exercises and log each set with weight, reps, and optional notes. '
          'RepIQ builds your personal history automatically.',
    ),
    _OnboardingPage(
      icon: Icons.notes,
      iconColor: Colors.amber,
      title: 'Your Notes Matter',
      body:
          'Write what happened during a set — "forearm gave out", '
          '"form felt sloppy", "drop set". RepIQ reads these and adjusts '
          'your next session accordingly.',
    ),
    _OnboardingPage(
      icon: Icons.trending_up,
      iconColor: Colors.greenAccent,
      title: 'AI That Learns You',
      body:
          'Every session makes the recommendations smarter. '
          'RepIQ tracks 1RM trends, detects plateaus, and tells you '
          'exactly when to push and when to back off.',
    ),
  ];

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await markOnboardingDone();
    widget.onComplete();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;
    return Scaffold(
      backgroundColor: const Color(0xFF0E1117),
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Skip',
                    style: TextStyle(color: Colors.grey)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _pages[i],
              ),
            ),
            _DotsIndicator(count: _pages.length, current: _page),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(isLast ? 'Get Started' : 'Next',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

/// Single slide in the onboarding page view: icon, title, and body text.
class _OnboardingPage extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  const _OnboardingPage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: iconColor),
          ),
          const SizedBox(height: 36),
          Text(title,
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(body,
              style: const TextStyle(
                  fontSize: 15, color: Colors.grey, height: 1.6),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Animated page-position dots shown at the bottom of [OnboardingView].
/// The active dot expands horizontally to indicate the current page.
class _DotsIndicator extends StatelessWidget {
  final int count;
  final int current;
  const _DotsIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? Colors.redAccent : Colors.white24,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
