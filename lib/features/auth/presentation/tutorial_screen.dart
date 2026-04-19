import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

class TutorialScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const TutorialScreen({super.key, required this.onComplete});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  static const _pages = [
    _TutorialPage(
      icon: Icons.calculate_rounded,
      color: AppColors.accent,
      title: 'Hidden in Plain Sight',
      description:
          'To everyone else, this is just a calculator.\n\nYour private messenger is hidden behind it — invisible until you unlock it.',
    ),
    _TutorialPage(
      icon: Icons.lock_open_rounded,
      color: Color(0xFF30D158),
      title: 'Your Secret Code',
      description:
          'Type your Secret Code on the calculator and press =\n\nThis opens your encrypted messenger. Only you know the code.',
    ),
    _TutorialPage(
      icon: Icons.delete_forever_rounded,
      color: AppColors.destructive,
      title: 'Emergency Delete',
      description:
          'Type your Delete Code and press =\n\nEverything is instantly wiped — messages, keys, account. Gone in seconds.',
    ),
    _TutorialPage(
      icon: Icons.shield_rounded,
      color: AppColors.accent,
      title: 'End-to-End Encrypted',
      description:
          'Every message is encrypted before it leaves your device.\n\nNot even we can read your messages. No one can.',
    ),
    _TutorialPage(
      icon: Icons.timer_rounded,
      color: Color(0xFFFF9F0A),
      title: 'Self-Destructing Messages',
      description:
          'Set a timer and messages disappear automatically after being read.\n\nOr use Burn After Read for one-time viewing.',
    ),
    _TutorialPage(
      icon: Icons.lock_rounded,
      color: Color(0xFFFFD60A),
      title: 'Password-Protected Messages',
      description:
          'Lock individual messages with a password.\n\nThe recipient needs the password to read it — an extra layer of security.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      widget.onComplete();
    }
  }

  void _skip() => widget.onComplete();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: _skip,
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.screenPadding + 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: page.color.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusXl),
                          ),
                          child: Icon(page.icon, color: page.color, size: 40),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          page.title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page.description,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: isDark
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textSecondaryLight,
                                    height: 1.6,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Dots + Next button
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding, 0, AppSpacing.screenPadding, 32),
              child: Row(
                children: [
                  // Page dots
                  Row(
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 6),
                        width: i == _currentPage ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _currentPage
                              ? _pages[_currentPage].color
                              : (isDark
                                  ? AppColors.textTertiaryDark
                                  : AppColors.textTertiaryLight),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Next / Get Started button
                  FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: _pages[_currentPage].color,
                      foregroundColor: Colors.white,
                      minimumSize: Size(isLast ? 140 : 100, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                    ),
                    child: Text(
                      isLast ? 'Get Started' : 'Next',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialPage {
  final IconData icon;
  final Color color;
  final String title;
  final String description;

  const _TutorialPage({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });
}
