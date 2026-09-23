import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';

/// Die Sperre, wenn kein Taschenrechner davorsteht.
///
/// Der Rechner ist seit dem 22.09.2026 freiwillig — Daniels Liste: „TR soll
/// optional sein und in den Einstellungen jederzeit ein- und ausgeschaltet
/// werden können." Wer ihn abschaltet, verliert damit aber nicht den Schutz:
/// Tresor-Passwort und Face ID bleiben, und dieser Bildschirm ist das, was
/// dann davorsteht.
///
/// Er sagt offen, was er ist. Das ist der ganze Unterschied zum Rechner:
/// dessen Sinn war, nicht auszusehen wie eine Sperre. Wer ihn abschaltet, hat
/// sich gegen die Verkleidung entschieden, nicht gegen das Schloss — eine
/// halbe Tarnung waere hier das Schlechteste von beidem.
///
/// Gibt es **weder** Tresor-Passwort **noch** Face ID, kommt dieser
/// Bildschirm gar nicht vor: die App oeffnet dann direkt den Messenger, siehe
/// KryptaShell. Eine Sperre, die jeder Fingertipp oeffnet, ist keine.
///
/// **Keine Notfall-Loeschung hier**, und das war eine Entscheidung gegen den
/// ersten Entwurf. Ein Knopf dafuer stand hier schon, mit Rueckfrage. Aber
/// vor dem Entsperren gibt es in dieser App bisher keine Zerstoerung ohne
/// Wissen: am Rechner braucht sie den Loeschcode, am Tresor-Bildschirm
/// passiert sie erst nach fuenf falschen Passwoertern. Ein Knopf haette
/// jedem, der das gesperrte Telefon in die Hand bekommt, mit zwei Tipps das
/// Konto vernichtet — samt der Meldung an alle Kontakte, dass es einen nicht
/// mehr gibt.
///
/// Der Zwangsfall bleibt bedient, und zwar deniabler als ein Knopf: fuenf
/// falsche Tresor-Passwoerter loeschen alles, und das sieht aus wie jemand,
/// der sein Passwort nicht mehr weiss.
class LockScreen extends StatelessWidget {
  const LockScreen({
    super.key,
    required this.onUnlock,
    this.laeuft = false,
  });

  /// Entsperren: Face ID, danach gegebenenfalls das Tresor-Passwort.
  final VoidCallback onUnlock;

  /// Ob gerade geprueft wird. Der Knopf bleibt dann stehen, zeigt aber, dass
  /// etwas laeuft: Face ID kann ein paar Sekunden brauchen.
  final bool laeuft;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(Icons.lock_rounded,
                          size: 34, color: AppColors.accent),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      l10n.appName,
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.lockedHint,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: laeuft ? null : onUnlock,
                        icon: laeuft
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.lock_open_rounded, size: 20),
                        label: Text(l10n.unlockAction),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
