import '../data/models/message_model.dart';

/// Wann eine Nachricht, die nicht rausging, noch einmal geschickt werden
/// kann.
///
/// Bis zum 25.09.2026 gab es dafuer keinen Weg. Eine fehlgeschlagene
/// Nachricht trug ein rotes Ausrufezeichen, und das war alles: der Text war
/// aus dem Eingabefeld verschwunden, und wer ihn trotzdem schicken wollte,
/// musste ihn neu tippen. Das passiert oefter, als man denkt — die
/// Schluesselpruefung vor dem Senden ist fail-closed und scheitert schon an
/// einem Funkloch.
///
/// Die Entscheidung steht hier und nicht im Provider, weil der Firebase
/// braucht und darum nicht im Test laeuft.
abstract final class ErneutSendenPolicy {
  /// Ob [nachricht] sich erneut senden laesst.
  ///
  /// Nur eigene, nur gescheiterte, und nur solche, deren Text hier noch
  /// liegt. Zwei Arten fallen damit heraus, und zwar mit Absicht:
  ///
  /// * die **einmalige** — ihr Klartext wird beim Absender gar nicht erst
  ///   gespeichert, siehe EinmaligPolicy.klartextBeimAbsender;
  /// * die **passwortgeschuetzte** — ihr Passwort ist nirgends gespeichert,
  ///   und ohne es noch einmal zu erfragen wuerde sie ungeschuetzt
  ///   rausgehen.
  ///
  /// [eigeneId] ist die angemeldete Kennung. Fehlt sie, geht nichts.
  static bool moeglich(Message nachricht, String? eigeneId) {
    if (eigeneId == null || nachricht.senderId != eigeneId) return false;
    if (nachricht.status != MessageStatus.failed) return false;
    if (nachricht.isSystemEvent) return false;
    if (nachricht.einmalig || nachricht.isPasswordProtected) return false;
    final text = nachricht.decryptedContent;
    return text != null && text.isNotEmpty;
  }
}
