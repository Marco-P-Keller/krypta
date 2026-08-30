import 'package:flutter/foundation.dart';

/// Wie der einmalige Aufräumlauf ausgegangen ist.
enum LegacyCleanupOutcome {
  /// Der Merker lag schon — auf diesem Gerät ist aufgeräumt.
  alreadyDone,

  /// Reste gefunden und geräumt.
  cleaned,

  /// Nichts zu räumen. Der Merker wird trotzdem gesetzt.
  nothingFound,

  /// Etwas ist schiefgegangen. Der Merker bleibt aus, der nächste Start
  /// versucht es erneut.
  failed,
}

/// Räumt die Reste des ausgebauten Tarn-Messengers weg.
///
/// Krypta hatte einmal einen zweiten, falschen Messenger: ein eigener Code im
/// Rechner öffnete eine harmlos aussehende Chat-App, vorbefüllt mit erfundenen
/// Nachrichten. Das gehörte zum alten Tarn-Konzept, das mit der Entscheidung
/// vom 24.08.2026 weggefallen ist — die App heißt wieder Krypta ECC, und der
/// Rechner ist eine Zugangssperre, keine Verkleidung.
///
/// Den Code zu löschen räumt auf bestehenden Geräten aber nichts weg. Dort
/// liegen weiter `decoy_chats` mit den erfundenen Chats und im Schlüsselbund
/// ein `krypta_code_decoy`. Und das ist schlechter als nichts: eine Datei mit
/// erfundenen Chats sagt jemandem, der das Gerät auswertet, dass diese App
/// einen Tarnmodus hat oder hatte. Ein Hinweis ohne Gegenwert, für einen
/// Modus, den es nicht mehr gibt.
///
/// **Die Reihenfolge ist anders als beim `FreshInstallGuard`.** Dort wird der
/// Merker VOR dem Räumen gesetzt, weil ein Dauerlauf die App nie über die
/// Einrichtung kommen liesse. Hier ist es umgekehrt richtig: Löschen ist
/// wiederholbar und folgenlos, und die Reste dürfen nicht liegen bleiben, nur
/// weil ein Lauf schiefging. Also erst räumen, dann merken.
///
/// Alle Abhängigkeiten kommen als Funktionen herein, damit der Ablauf ohne
/// Dateisystem und Schlüsselbund prüfbar ist.
class LegacyCleanup {
  LegacyCleanup({
    required this.markerSet,
    required this.setMarker,
    required this.purgeFiles,
    required this.deleteLegacyKeys,
  });

  /// Ob auf diesem Gerät schon aufgeräumt wurde.
  final Future<bool> Function() markerSet;

  /// Hält fest, dass aufgeräumt ist.
  final Future<void> Function() setMarker;

  /// Löscht die `decoy_*`-Dateien. Gibt zurück, wie viele es waren.
  final Future<int> Function() purgeFiles;

  /// Löscht die Schlüsselbund-Einträge, die es nicht mehr gibt.
  final Future<void> Function() deleteLegacyKeys;

  Future<LegacyCleanupOutcome> run() async {
    try {
      if (await markerSet()) return LegacyCleanupOutcome.alreadyDone;

      final geraeumt = await purgeFiles();
      await deleteLegacyKeys();
      await setMarker();

      return geraeumt > 0
          ? LegacyCleanupOutcome.cleaned
          : LegacyCleanupOutcome.nothingFound;
    } catch (e) {
      // Kein Grund, den Start zu verhindern. Der naechste Versuch kommt.
      if (kDebugMode) debugPrint('Aufraeumen der Altlasten fehlgeschlagen: $e');
      return LegacyCleanupOutcome.failed;
    }
  }
}
