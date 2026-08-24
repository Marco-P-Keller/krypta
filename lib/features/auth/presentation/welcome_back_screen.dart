import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';

/// Der Übergang zwischen Taschenrechner und Messenger.
///
/// Er hat zwei Aufgaben. Sichtbar ist die Begrüßung; die eigentliche ist, dass
/// der Messenger dahinter fertig laden darf. Vorher stand der Rechner still,
/// solange Schlüssel geladen und der Aufnahmeschutz eingerichtet wurden — auf
/// einem langsamen Gerät sah das aus, als sei der Code nicht angekommen.
///
/// Der Text kommt aus der Übersetzung, nicht aus einer Konstanten: wird die
/// Sprache in den Einstellungen umgestellt, ändert sich dieser Bildschirm
/// beim nächsten Entsperren mit.
class WelcomeBackScreen extends StatelessWidget {
  const WelcomeBackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.lock_open_rounded,
                  size: 32, color: AppColors.accent),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.welcomeBack,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(
                  AppColors.accent.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
