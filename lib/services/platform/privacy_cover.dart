import 'dart:async';

import 'package:flutter/widgets.dart';

import 'platform_security_service.dart';

/// Die schwarze Abdeckung, die beim Verlassen der App über das Fenster geht.
///
/// Sie deckt zwei Dinge ab: die Vorschau im App-Umschalter, und die Rückkehr.
/// Der zweite Teil wird leicht übersehen. Die Umschaltung auf den
/// Taschenrechner passiert bei `paused`, und ab da zeichnet Flutter nicht
/// mehr — die Ebene darunter hält also weiter das letzte Bild von vor der
/// Pause, und das ist der Messenger. Beim Aufwachen ist die Abdeckung das
/// Einzige, was ihn verdeckt, bis das erste neue Bild abgeliefert ist.
///
/// Wer sie nach Zeit abnimmt, veranstaltet ein Wettrennen gegen dieses Bild.
/// Deshalb nimmt sie hier niemand ab, bevor eines steht.
class PrivacyCover {
  PrivacyCover(this._platform);

  final PlatformSecurityService _platform;

  /// Läuft schon ein Abnehmen? `resumed` kommt mehrfach — Anruf-Banner,
  /// Kontrollzentrum, Siri über der App.
  bool _pending = false;

  /// Nimmt die Abdeckung ab, sobald ein Bild auf dem Schirm steht.
  ///
  /// [afterwards] läuft direkt danach. Alles, was den Faden blockiert, gehört
  /// dorthin und nicht davor: solange hier gerechnet wird, entsteht kein
  /// neues Bild, und die Abdeckung bliebe liegen.
  void dismissWhenPainted({VoidCallback? afterwards}) {
    if (_pending) return;
    _pending = true;
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      // Hier ist das Bild gebaut und gemalt, aber der Rasterfaden hat es noch
      // nicht zwingend abgeliefert. Ein Bild später ist es unten angekommen.
      binding.addPostFrameCallback((_) {
        _pending = false;
        unawaited(_platform.dismissPrivacyCover());
        afterwards?.call();
      });
      binding.scheduleFrame();
    });
    // Beide `scheduleFrame` sind Pflicht, nicht Vorsicht: ein Rückruf für
    // „nach dem Bild" plant kein Bild ein. Nach einem Blick ins
    // Kontrollzentrum kehrt die App zurück, ohne dass sich etwas geändert
    // hat — kein Relock, nichts schmutzig, also auch kein Bild. Der Rückruf
    // liefe nie und die Abdeckung bliebe liegen, bis der Wachhund auf der
    // nativen Seite anschlägt: drei Sekunden schwarz für einen Blick auf die
    // Helligkeit.
    binding.scheduleFrame();
  }
}
