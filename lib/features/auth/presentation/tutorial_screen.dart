import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

/// Die Einfuehrung beim ersten Start, und Nachschlagewerk aus den
/// Einstellungen.
///
/// Umgebaut am 02.09.2026 auf Daniels Ansage: kurz und buendig, dafuer
/// vollstaendig. Vorher neun Seiten, von denen mehrere einer einzigen
/// Einstellung gewidmet waren, waehrend die Haelfte der App gar nicht
/// vorkam: Kontaktanfragen, QR und Sicherheitsnummer, Blockieren, der
/// Screenshot-Hinweis, Chat leeren gegen Chat loeschen, die Restzeit.
///
/// Jetzt sechs Seiten nach Thema. Jede traegt drei bis fuenf Zeilen mit
/// Symbol, Stichwort und genau einem Satz. Wer wischt, kommt schnell durch;
/// wer nachschlaegt, findet das Stichwort.
///
/// Zum Ton: kurze Hauptsaetze, keine Gedankenstriche. Ein Test haelt das
/// fest, sonst schleicht es sich wieder ein.
class TutorialScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const TutorialScreen({super.key, required this.onComplete});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  static const _pageCount = 6;

  static const _gruen = Color(0xFF30D158);
  static const _orange = Color(0xFFFF9F0A);

  static const _pageColors = [
    AppColors.accent,
    _gruen,
    AppColors.accent,
    _orange,
    AppColors.destructive,
    _gruen,
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _pageCount - 1) {
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
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLast = _currentPage == _pageCount - 1;
    final color = _pageColors[_currentPage];

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: _skip,
                  child: Text(
                    l10n.skip,
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _PageWelcome(isDark: isDark),
                  _PageAccess(isDark: isDark),
                  _PageContacts(isDark: isDark),
                  _PageMessages(isDark: isDark),
                  _PageProtection(isDark: isDark),
                  _PageReady(isDark: isDark),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding, 0, AppSpacing.screenPadding, 32),
              child: Row(
                children: [
                  Row(
                    children: List.generate(
                      _pageCount,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 5),
                        width: i == _currentPage ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _currentPage
                              ? color
                              : (isDark
                                  ? AppColors.textTertiaryDark
                                  : AppColors.textTertiaryLight),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Vorher stand hier ein Spacer und der Knopf trug eine
                  // Mindestbreite. Damit hatte er keine Obergrenze: bei
                  // grosser Systemschrift oder einer langen Uebersetzung lief
                  // die Zeile nach rechts heraus. Expanded begrenzt ihn auf
                  // den verbleibenden Platz, Align haelt ihn trotzdem rechts.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _next,
                        style: FilledButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          minimumSize: Size(isLast ? 140 : 100, 50),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusMd),
                          ),
                        ),
                        child: Text(
                          isLast ? l10n.tutStartSetup : l10n.next,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
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

// ── 1 Willkommen ────────────────────────────────────────────────────────────

class _PageWelcome extends StatelessWidget {
  final bool isDark;
  const _PageWelcome({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Layout(
      isDark: isDark,
      title: l10n.tutWelcomeTitle,
      description: l10n.tutWelcomeBody,
      // Die einzige Seite mit einem echten Nachbau. Der Taschenrechner ist
      // das, was Fremde von dieser App sehen, und damit ihr Kern.
      preview: const _CalculatorMock(),
      rows: [
        _FeatureRow(
          isDark: isDark,
          icon: Icons.calculate_rounded,
          color: AppColors.accent,
          title: l10n.calculator,
          description: l10n.tutDCalculator,
        ),
        _FeatureRow(
          isDark: isDark,
          icon: Icons.lock_rounded,
          color: Color(0xFF30D158),
          title: l10n.tutTEncrypted,
          description: l10n.tutDEncrypted,
        ),
        _FeatureRow(
          isDark: isDark,
          icon: Icons.language_rounded,
          color: Color(0xFFFF9F0A),
          title: l10n.language,
          description: l10n.tutDLanguage,
        ),
      ],
    );
  }
}

// ── 2 Zugang ────────────────────────────────────────────────────────────────

class _PageAccess extends StatelessWidget {
  final bool isDark;
  const _PageAccess({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Layout(
      isDark: isDark,
      title: l10n.tutAccessTitle,
      description: l10n.tutAccessIntro,
      preview: const _Badge(
          icon: Icons.lock_rounded, color: Color(0xFF30D158)),
      rows: [
        _FeatureRow(
          isDark: isDark,
          icon: Icons.pin_rounded,
          color: AppColors.accent,
          title: l10n.tutTSecretCode,
          description: l10n.tutDSecretCode,
        ),
        _FeatureRow(
          isDark: isDark,
          icon: Icons.delete_forever_rounded,
          color: AppColors.destructive,
          title: l10n.tutTDeleteCode,
          description: l10n.tutDDeleteCode,
        ),
        _FeatureRow(
          isDark: isDark,
          icon: Icons.shield_outlined,
          color: Color(0xFF30D158),
          title: l10n.vaultPassword,
          description: l10n.tutDVault,
        ),
        _FeatureRow(
          isDark: isDark,
          icon: Icons.face_rounded,
          color: Color(0xFFFF9F0A),
          title: l10n.biometricUnlock,
          description: l10n.tutDScreenLock,
        ),
      ],
    );
  }
}

// ── 3 Kontakte ──────────────────────────────────────────────────────────────

class _PageContacts extends StatelessWidget {
  final bool isDark;
  const _PageContacts({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Layout(
      isDark: isDark,
      title: l10n.tutAddContactsTitle,
      description: l10n.tutContactsIntro,
      preview: const _Badge(
          icon: Icons.person_add_alt_1_rounded, color: AppColors.accent),
      rows: [
        _FeatureRow(
          isDark: isDark,
          icon: Icons.tag_rounded,
          color: AppColors.accent,
          title: l10n.addContact,
          description: l10n.tutDAddById,
        ),
        _FeatureRow(
          isDark: isDark,
          icon: Icons.mark_email_unread_rounded,
          color: Color(0xFFFF9F0A),
          title: l10n.tutTRequest,
          description: l10n.tutDRequest,
        ),
        _FeatureRow(
          isDark: isDark,
          icon: Icons.qr_code_2_rounded,
          color: Color(0xFF30D158),
          title: l10n.scanQrCode,
          description: l10n.tutDQr,
        ),
        _FeatureRow(
          isDark: isDark,
          icon: Icons.verified_rounded,
          color: Color(0xFF30D158),
          title: l10n.safetyNumberTitle,
          description: l10n.tutDSafetyNumber,
        ),
      ],
    );
  }
}

// ── 4 Nachrichten ───────────────────────────────────────────────────────────

class _PageMessages extends StatelessWidget {
  final bool isDark;
  const _PageMessages({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Layout(
      isDark: isDark,
      title: l10n.tutChatFeaturesTitle,
      description: l10n.tutChatFeaturesIntro,
      preview: const _Badge(
          icon: Icons.forum_rounded, color: Color(0xFFFF9F0A)),
      rows: [
        _FeatureRow(
          isDark: isDark,
          icon: Icons.timer_rounded,
          color: AppColors.accent,
          title: l10n.autoDeleteTimer,
          description: l10n.tutAutoDeleteDesc,
        ),
        _FeatureRow(
          isDark: isDark,
          icon: Icons.visibility_off_rounded,
          color: AppColors.destructive,
          title: l10n.onceOnlyMessage,
          description: l10n.tutDOnceOnly,
        ),
        _FeatureRow(
          isDark: isDark,
          icon: Icons.lock_rounded,
          color: Color(0xFFFFD60A),
          title: l10n.lockMessage,
          description: l10n.tutLockMessageDesc,
        ),
      ],
    );
  }
}

// ── 5 Schutz ────────────────────────────────────────────────────────────────

class _PageProtection extends StatelessWidget {
  final bool isDark;
  const _PageProtection({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Layout(
      isDark: isDark,
      title: l10n.tutProtectTitle,
      description: l10n.tutProtectIntro,
      preview: const _Badge(
          icon: Icons.shield_rounded, color: AppColors.destructive),
      rows: [
        _FeatureRow(
          isDark: isDark,
          icon: Icons.photo_camera_rounded,
          color: Color(0xFFFF9F0A),
          title: l10n.screenshotNotice,
          description: l10n.tutDScreenshot,
        ),
        _FeatureRow(
          isDark: isDark,
          icon: Icons.block_rounded,
          color: AppColors.destructive,
          title: l10n.blockContact,
          description: l10n.tutDBlock,
        ),
        _FeatureRow(
          isDark: isDark,
          icon: Icons.cleaning_services_rounded,
          color: AppColors.accent,
          title: l10n.clearChat,
          description: l10n.tutDClear,
        ),
        _FeatureRow(
          isDark: isDark,
          icon: Icons.delete_outline_rounded,
          color: AppColors.destructive,
          title: l10n.deleteChat,
          description: l10n.tutDDeleteChat,
        ),
      ],
    );
  }
}

// ── 6 Fertig ────────────────────────────────────────────────────────────────

class _PageReady extends StatelessWidget {
  final bool isDark;
  const _PageReady({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Layout(
      isDark: isDark,
      title: l10n.tutReadyTitle,
      description: l10n.tutReadyBody,
      preview: const _Badge(
          icon: Icons.check_circle_rounded, color: Color(0xFF30D158)),
      rows: [
        // Die Notfall-Loeschung steht bewusst hier und nicht bei den uebrigen
        // Schutzfunktionen: sie soll als Letztes haengenbleiben.
        _FeatureRow(
          isDark: isDark,
          icon: Icons.emergency_rounded,
          color: AppColors.destructive,
          title: l10n.tutTEmergency,
          description: l10n.tutDEmergency,
        ),
        _FeatureRow(
          isDark: isDark,
          icon: Icons.settings_rounded,
          color: AppColors.accent,
          title: l10n.settings,
          description: l10n.tutDSettings,
        ),
        _FeatureRow(
          isDark: isDark,
          icon: Icons.menu_book_rounded,
          color: Color(0xFF30D158),
          title: l10n.tutTAgain,
          description: l10n.tutDAgain,
        ),
      ],
    );
  }
}

// ── Bausteine ───────────────────────────────────────────────────────────────

/// Das Geruest jeder Seite: Vorschau, Titel, ein Satz, dann die Zeilen.
class _Layout extends StatelessWidget {
  final bool isDark;
  final String title;
  final String description;
  final Widget preview;
  final List<Widget> rows;

  const _Layout({
    required this.isDark,
    required this.title,
    required this.description,
    required this.preview,
    this.rows = const [],
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        children: [
          const SizedBox(height: 8),
          preview,
          const SizedBox(height: 24),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  height: 1.5,
                ),
            textAlign: TextAlign.center,
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? AppColors.dividerDark
                      : AppColors.dividerLight,
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    rows[i],
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Eine Zeile: Symbol, Stichwort, ein Satz.
class _FeatureRow extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final Color color;
  final String title;
  final String description;

  const _FeatureRow({
    required this.isDark,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        // Expanded, damit lange Uebersetzungen und grosse Systemschrift
        // umbrechen statt seitlich herauszulaufen.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Das grosse Symbol oben auf den Seiten ohne eigenen Nachbau.
class _Badge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _Badge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Icon(icon, color: color, size: 44),
    );
  }
}

/// Der Taschenrechner, wie ihn Fremde sehen.
class _CalculatorMock extends StatelessWidget {
  const _CalculatorMock();

  static const _rows = [
    ['C', '±', '%', '÷'],
    ['7', '8', '9', '×'],
    ['4', '5', '6', '−'],
    ['1', '2', '3', '+'],
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.dividerDark, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            alignment: Alignment.centerRight,
            child: const Text(
              '0',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w300),
            ),
          ),
          const SizedBox(height: 4),
          for (final row in _rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: row.map((l) {
                  final isOp = ['÷', '×', '−', '+'].contains(l);
                  final isFunc = ['C', '±', '%'].contains(l);
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 32,
                      decoration: BoxDecoration(
                        color: isOp
                            ? AppColors.calculatorButtonAccent
                            : (isFunc
                                ? AppColors.calculatorButtonLight
                                : AppColors.calculatorButtonDark),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(l,
                            style: TextStyle(
                                color: isFunc ? Colors.black : Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
