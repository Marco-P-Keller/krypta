import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../theme/app_colors.dart';
import '../../data/models/message_model.dart';

/// Ein Hinweis im Chatverlauf — keine Nachricht, sondern eine Feststellung.
///
/// Steht mittig zwischen den Blasen, wie bei Snapchat und Signal: er gehört
/// niemandem, sondern beiden.
///
/// Der Text entsteht hier und nicht beim Speichern. Ein festgeschriebener
/// deutscher Satz bliebe nach einem Sprachwechsel deutsch — so wechselt auch
/// ein alter Eintrag mit.
class SystemEventRow extends StatelessWidget {
  const SystemEventRow({
    super.key,
    required this.message,
    required this.isMine,
    required this.peerName,
  });

  final Message message;

  /// Ob ich es selbst ausgelöst habe. Entscheidet zwischen „Du hast…" und
  /// „*Name* hat…".
  final bool isMine;

  /// Anzeigename der Gegenseite, für den Fall, dass sie es war.
  final String peerName;

  String _text(AppLocalizations l10n) {
    switch (message.systemEvent!) {
      case SystemEventKind.screenshot:
        return isMine
            ? l10n.screenshotByYou
            : l10n.screenshotByPeer(peerName);
      case SystemEventKind.screenRecording:
        return isMine
            ? l10n.recordingByYou
            : l10n.recordingByPeer(peerName);
      case SystemEventKind.accountDeleted:
        // Immer über die Gegenseite: das eigene Konto zu löschen räumt auch
        // den eigenen Verlauf ab, ein Hinweis an mich selbst hätte niemanden,
        // der ihn liest.
        return l10n.accountGone(peerName);
      case SystemEventKind.selfDestructChanged:
        final dauer = message.selfDestructDuration;
        return dauer == null
            ? l10n.selfDestructTurnedOff
            : l10n.selfDestructSetTo(_knapp(dauer));
    }
  }

  /// Knapp und ohne Uebersetzung: die Einheiten sind in allen sieben Sprachen
  /// dieselben Kuerzel.
  static String _knapp(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds} s';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 24) return '${d.inHours} h';
    return '${d.inDays} d';
  }

  IconData get _icon => switch (message.systemEvent!) {
        SystemEventKind.screenshot => Icons.screenshot_rounded,
        SystemEventKind.screenRecording => Icons.videocam_rounded,
        SystemEventKind.accountDeleted => Icons.person_off_rounded,
        SystemEventKind.selfDestructChanged => Icons.timer_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final farbe =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.surfaceElevatedDark
                : AppColors.surfaceElevatedLight,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, size: 14, color: farbe),
              const SizedBox(width: 8),
              // Flexible, damit ein langer Kontaktname umbricht statt die
              // Pille über den Rand zu schieben.
              Flexible(
                child: Text(
                  _text(l10n),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: farbe,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
