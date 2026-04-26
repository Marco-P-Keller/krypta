import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
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

  static const _pageCount = 9;

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

  static const _pageColors = [
    AppColors.accent,
    AppColors.accent,
    AppColors.destructive,
    Color(0xFF30D158),
    Color(0xFF30D158),
    AppColors.accent,
    AppColors.destructive,
    Color(0xFFFF9F0A),
    AppColors.accent,
  ];

  @override
  Widget build(BuildContext context) {
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
                    AppLocalizations.of(context)!.skip,
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
                  _Page1Welcome(isDark: isDark),
                  _Page2SetupCodes(isDark: isDark),
                  _Page3DeleteCode(isDark: isDark),
                  _Page4OpenMessenger(isDark: isDark),
                  _Page5VaultPassword(isDark: isDark),
                  _Page6AddContacts(isDark: isDark),
                  _Page7EmergencyButtons(isDark: isDark),
                  _Page8ChatFeatures(isDark: isDark),
                  _Page9Ready(isDark: isDark),
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
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      minimumSize: Size(isLast ? 140 : 100, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                    ),
                    child: Text(
                      isLast ? 'Setup starten' : 'Weiter',
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

// ── Page 1: Welcome — Was ist diese App? ────────────────────────────────────

class _Page1Welcome extends StatelessWidget {
  final bool isDark;
  const _Page1Welcome({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _Layout(
      isDark: isDark,
      title: 'Willkommen bei Krypta',
      description:
          'Krypta ist ein geheimer Messenger.\n\nFür alle anderen sieht die App aus wie ein ganz normaler Taschenrechner — niemand wird vermuten, dass sich dahinter ein verschlüsselter Chat versteckt.\n\nWir empfehlen, dieses Tutorial ausführlich zu lesen.',
      preview: Container(
        width: 200,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.dividerDark, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              alignment: Alignment.centerRight,
              child: const Text(
                '0',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w300),
              ),
            ),
            const SizedBox(height: 6),
            for (final row in [
              ['C', '±', '%', '÷'],
              ['7', '8', '9', '×'],
              ['4', '5', '6', '−'],
              ['1', '2', '3', '+'],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: row.map((l) {
                    final isOp = ['÷', '×', '−', '+'].contains(l);
                    final isFunc = ['C', '±', '%'].contains(l);
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: 34,
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
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Page 2: Setup — Geheimcode festlegen ────────────────────────────────────

class _Page2SetupCodes extends StatelessWidget {
  final bool isDark;
  const _Page2SetupCodes({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _Layout(
      isDark: isDark,
      title: 'Dein Geheimcode',
      description:
          'Beim Einrichten legst du einen Zahlencode fest.\n\nDieser Code ist dein Schlüssel — nur damit kannst du den versteckten Messenger öffnen.',
      preview: Container(
        width: 220,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.lock_outline_rounded,
                  color: AppColors.accent, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              'Secret Code',
              style: TextStyle(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceElevatedDark
                    : AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '• • • • •',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiaryLight,
                    fontSize: 24,
                    letterSpacing: 8,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page 3: Delete-Code ─────────────────────────────────────────────────────

class _Page3DeleteCode extends StatelessWidget {
  final bool isDark;
  const _Page3DeleteCode({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _Layout(
      isDark: isDark,
      title: 'Notfall-Code',
      description:
          'Der zweite Code ist für den Notfall.\n\nWenn du diesen Code eingibst, wird sofort alles gelöscht — Nachrichten, Schlüssel, Account. Unwiderruflich.\n\nNur im Ernstfall verwenden!',
      preview: Container(
        width: 220,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.destructive.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.destructive.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.destructive.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.delete_forever_rounded,
                  color: AppColors.destructive, size: 28),
            ),
            const SizedBox(height: 14),
            const Text(
              'Delete Code',
              style: TextStyle(
                color: AppColors.destructive,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Alles wird sofort gelöscht.\nKeine Wiederherstellung möglich.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.destructive.withValues(alpha: 0.7),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page 4: Messenger öffnen ────────────────────────────────────────────────

class _Page4OpenMessenger extends StatelessWidget {
  final bool isDark;
  const _Page4OpenMessenger({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _Layout(
      isDark: isDark,
      title: 'Messenger öffnen',
      description:
          'Um deinen Messenger zu öffnen:\n\n1. Gib deinen Geheimcode im Taschenrechner ein\n2. Drücke die = Taste\n\nDer Messenger öffnet sich sofort.',
      preview: Container(
        width: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.dividerDark, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Display with code
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              alignment: Alignment.centerRight,
              child: const Text(
                '••••',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 8),
              ),
            ),
            const SizedBox(height: 10),
            // = Button highlighted
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF30D158).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app_rounded,
                          color: Color(0xFF30D158), size: 14),
                      SizedBox(width: 4),
                      Text('Drücke =',
                          style: TextStyle(
                              color: Color(0xFF30D158),
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.calculatorButtonAccent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.calculatorButtonAccent
                            .withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text('=',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w500)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF30D158).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF30D158).withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_open_rounded,
                      color: Color(0xFF30D158), size: 14),
                  SizedBox(width: 5),
                  Text('Messenger entsperrt',
                      style: TextStyle(
                          color: Color(0xFF30D158),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page 5: Tresor-Passwort ─────────────────────────────────────────────────

class _Page5VaultPassword extends StatelessWidget {
  final bool isDark;
  const _Page5VaultPassword({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _Layout(
      isDark: isDark,
      title: 'Tresor-Passwort',
      description:
          'In den Einstellungen kannst du ein zusätzliches Passwort aktivieren.\n\nNach dem Geheimcode wird dann noch das Tresor-Passwort abgefragt — doppelte Sicherheit.\n\nWir empfehlen das aus Sicherheitsgründen.',
      preview: Container(
        width: 220,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF30D158).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.shield_rounded,
                  color: Color(0xFF30D158), size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              'Vault Password',
              style: TextStyle(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            // Password field mock
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceElevatedDark
                    : AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 18,
                      color: isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiaryLight),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '••••••••',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiaryLight,
                        fontSize: 16,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF30D158).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Empfohlen',
                style: TextStyle(
                  color: Color(0xFF30D158),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page 6: Kontakte hinzufügen ─────────────────────────────────────────────

class _Page6AddContacts extends StatelessWidget {
  final bool isDark;
  const _Page6AddContacts({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _Layout(
      isDark: isDark,
      title: 'Kontakte hinzufügen',
      description:
          'Du kannst Kontakte auf zwei Arten hinzufügen:\n\n• QR-Code scannen — schnell und einfach\n• User-ID eingeben — wenn ihr nicht am selben Ort seid\n\nDanach kannst du der Person einen Namen geben.',
      preview: Container(
        width: 240,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // QR option
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceElevatedDark
                    : AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.qr_code_rounded,
                        color: AppColors.accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('QR-Code scannen',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            )),
                        Text('Schnell & einfach',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                              fontSize: 11,
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // ID option
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceElevatedDark
                    : AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person_add_rounded,
                        color: AppColors.accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('User-ID eingeben',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            )),
                        Text('Für Fernkontakte',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                              fontSize: 11,
                            )),
                      ],
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

// ── Page 7: Emergency Buttons (rot) ─────────────────────────────────────────

class _Page7EmergencyButtons extends StatelessWidget {
  final bool isDark;
  const _Page7EmergencyButtons({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _Layout(
      isDark: isDark,
      title: 'Notfall-Knöpfe',
      description:
          'In der App findest du rote Notfall-Knöpfe.\n\nSie löschen sofort alles — genau wie der Delete-Code. Verwende sie nur im Ernstfall.',
      preview: Container(
        width: 240,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // AppBar mock with emergency button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceElevatedDark
                    : AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.arrow_back_ios_new_rounded,
                      size: 16,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Chats',
                        style: TextStyle(
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                  // Emergency button mock
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.destructive.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.destructive.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(Icons.warning_amber_rounded,
                        size: 16,
                        color:
                            AppColors.destructive.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Arrow pointing to button
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.destructive.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Notfall-Knopf',
                    style: TextStyle(
                      color: AppColors.destructive,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_upward_rounded,
                    size: 14, color: AppColors.destructive.withValues(alpha: 0.6)),
              ],
            ),
            const SizedBox(height: 12),
            // Settings emergency button mock
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.destructive.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.destructive.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.destructive.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.delete_forever_rounded,
                        color: AppColors.destructive, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Emergency Delete',
                            style: TextStyle(
                                color: AppColors.destructive,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        Text('In den Einstellungen',
                            style: TextStyle(
                                color: AppColors.destructive,
                                fontSize: 10)),
                      ],
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

// ── Page 8: Chat-Funktionen ─────────────────────────────────────────────────

class _Page8ChatFeatures extends StatelessWidget {
  final bool isDark;
  const _Page8ChatFeatures({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _Layout(
      isDark: isDark,
      title: 'Chat-Funktionen',
      description:
          'Im Chat hast du drei besondere Funktionen:',
      preview: Container(
        width: 260,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Feature 1: Password lock
            _FeatureRow(
              isDark: isDark,
              icon: Icons.lock_outline_rounded,
              activeIcon: Icons.lock_rounded,
              color: const Color(0xFFFFD60A),
              title: 'Nachrichten sperren',
              description: 'Einzelne Nachrichten mit Passwort schützen',
            ),
            const SizedBox(height: 10),
            // Feature 2: Auto-delete timer
            _FeatureRow(
              isDark: isDark,
              icon: Icons.timer_outlined,
              activeIcon: Icons.timer_rounded,
              color: AppColors.accent,
              title: 'Auto-Delete Timer',
              description: 'Nachrichten löschen sich nach einer Zeit automatisch',
            ),
            const SizedBox(height: 10),
            // Feature 3: Burn after read
            _FeatureRow(
              isDark: isDark,
              icon: Icons.local_fire_department_rounded,
              activeIcon: Icons.local_fire_department_rounded,
              color: AppColors.destructive,
              title: 'Burn After Read',
              description: 'Nachricht wird nach dem Lesen sofort gelöscht',
            ),
            const SizedBox(height: 14),
            // Input bar mock showing the buttons
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.backgroundDark
                    : AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  // Lock button
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD60A).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.lock_outline_rounded,
                        size: 16,
                        color: const Color(0xFFFFD60A).withValues(alpha: 0.8)),
                  ),
                  const SizedBox(width: 4),
                  // Timer button
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.timer_outlined,
                        size: 16,
                        color: AppColors.accent.withValues(alpha: 0.8)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.surfaceElevatedDark
                            : AppColors.surfaceElevatedLight,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Text('Nachricht...',
                          style: TextStyle(
                            color: isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiaryLight,
                            fontSize: 12,
                          )),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_upward_rounded,
                        color: Colors.white, size: 16),
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

class _FeatureRow extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final IconData activeIcon;
  final Color color;
  final String title;
  final String description;

  const _FeatureRow({
    required this.isDark,
    required this.icon,
    required this.activeIcon,
    required this.color,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(activeIcon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  )),
              Text(description,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                    fontSize: 10.5,
                    height: 1.3,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Page 9: Bereit ──────────────────────────────────────────────────────────

class _Page9Ready extends StatelessWidget {
  final bool isDark;
  const _Page9Ready({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _Layout(
      isDark: isDark,
      title: 'Alles klar!',
      description:
          'Du weisst jetzt alles was du brauchst.\n\nIm nächsten Schritt richtest du deine Codes ein — danach ist dein Messenger einsatzbereit.',
      preview: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded, color: AppColors.accent, size: 48),
      ),
    );
  }
}

// ── Shared Layout ───────────────────────────────────────────────────────────

class _Layout extends StatelessWidget {
  final bool isDark;
  final String title;
  final String description;
  final Widget preview;

  const _Layout({
    required this.isDark,
    required this.title,
    required this.description,
    required this.preview,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        children: [
          const SizedBox(height: 8),
          preview,
          const SizedBox(height: 28),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  height: 1.6,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
