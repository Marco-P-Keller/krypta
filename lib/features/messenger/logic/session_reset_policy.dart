import '../data/models/contact_model.dart';

/// Wann die eigene Sitzung mit einem Kontakt verworfen gehoert.
///
/// Der Handschlag-Kopf `ek` geht nur mit der **ersten** Nachricht einer
/// Sitzung mit. Wer eine laufende Sitzung hat, schickt ihn nie wieder — und
/// wenn die Gegenseite ihre Haelfte verloren hat (Chat geloescht, App neu
/// aufgesetzt), kann sie nichts mehr entschluesseln. Die Nachrichten
/// verschwinden bei ihr stumm, und der Zustand heilt von allein nicht mehr:
/// meine Sitzung lebt ja.
///
/// Der Ausweg ist immer derselbe — die eigene Sitzung wegwerfen, damit die
/// naechste Nachricht wieder einen Handschlag traegt. Hier steht, wann das
/// zu geschehen hat.
abstract final class SessionResetPolicy {
  /// Ob das erneute Hinzufuegen eines bereits bekannten Kontakts die Sitzung
  /// verwerfen muss.
  ///
  /// Ja — wer jemanden erneut hinzufuegt, den er schon hat, meint „fang mit
  /// dem von vorn an". Bisher passierte dabei nichts: [ContactRequestPolicy]
  /// laesst einen angenommenen Kontakt unveraendert, und der QR-Pfad schickte
  /// daraufhin nicht einmal eine Anfrage los. Gemeldet wurde trotzdem
  /// „verifiziert" — eine Erfolgsmeldung fuer eine Handlung, die nichts tat.
  ///
  /// **Ausnahme: blockiert.** Mit jemandem, den ich ausdruecklich gesperrt
  /// habe, still eine neue Sitzung aufzubauen waere das Gegenteil dessen, was
  /// die Sperre soll. Blockiert bleibt blockiert.
  static bool onReAdd(Contact existing) => !existing.isBlocked;

  /// Wie viele Sitzungskennungen der Gegenseite pro Chat aufgehoben werden.
  ///
  /// Ohne Deckel wuechse die Spur mit jedem Neuaufbau weiter und landete in
  /// dieser Groesse auf der Platte. Zwanzig deckt jeden realen Verlauf ab —
  /// so oft baut niemand eine Sitzung neu auf.
  static const int maxLineage = 20;

  /// Die Spur der gesehenen Sitzungskennungen, die ein Verwerfen ueberlebt.
  ///
  /// `peerSeenPsids` haelt fest, welche Sitzungskennungen die Gegenseite
  /// schon benutzt hat, damit ein alter Handschlag nicht ein zweites Mal
  /// durchgeht (C5). Die Liste lebt im Sitzungszustand und wird beim
  /// Neuaufbau von dort uebernommen — wird die Sitzung aber **verworfen**,
  /// faellt der Zustand weg und die Spur mit ihm. Deshalb wird sie getrennt
  /// aufgehoben und hier wieder zusammengefuehrt.
  ///
  /// Reihenfolge ist alt nach neu; laeuft die Liste ueber, faellt vorne das
  /// Aelteste heraus.
  static List<String> mergeLineage(
    Iterable<String> aufgehoben,
    Iterable<String> ausDerSitzung,
  ) {
    final spur = <String>[];
    for (final kennung in [...aufgehoben, ...ausDerSitzung]) {
      if (spur.contains(kennung)) continue;
      spur.add(kennung);
    }
    if (spur.length <= maxLineage) return spur;
    return spur.sublist(spur.length - maxLineage);
  }
}
