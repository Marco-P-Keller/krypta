import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

/// Die Ansicht einer einmaligen Nachricht.
///
/// Sie bekommt den Text als Zeichenkette und kennt weder Provider noch
/// Nachricht. Das ist Absicht und der Kern der Zusage: zu dem Zeitpunkt, an
/// dem diese Ansicht erscheint, ist die Nachricht bereits von der Platte
/// fort. Es gibt nichts mehr nachzuladen, und niemand kann sie versehentlich
/// ein zweites Mal holen. Was hier steht, liegt nur noch im Arbeitsspeicher.
///
/// Schliessen, Anruf, Absturz und leerer Akku fuehren darum zum selben
/// Ergebnis, ohne dass diese Ansicht etwas dafuer tun muesste.
class EinmaligeNachrichtScreen extends StatelessWidget {
  final String text;

  const EinmaligeNachrichtScreen({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.onceOnlyHiddenHint,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding, vertical: 24),
          child: SingleChildScrollView(
            child: SizedBox(
              width: double.infinity,
              // Kein Markieren und damit kein Kopieren, wie im uebrigen Chat
              // auch. Ein Screenshot bleibt trotzdem moeglich; das steht so
              // in der Rueckfrage, statt hier etwas zu behaupten.
              child: SelectionContainer.disabled(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.5,
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
