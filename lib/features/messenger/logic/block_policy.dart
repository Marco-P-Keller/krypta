import '../data/models/contact_model.dart';

/// Was das Aufheben einer Blockierung wiederherstellt.
///
/// Bisher landete jeder entblockte Kontakt auf [TrustState.keyChanged] und
/// musste erst wieder bestaetigt werden. Der Gedanke dahinter ist richtig: wer
/// wegen eines Schluesselwechsels blockiert wurde, soll ueber Blockieren und
/// Entblocken nicht an der Bestaetigung vorbeikommen.
///
/// Nur traf es eben auch jeden anderen. Wer einen ganz normalen, bestaetigten
/// Kontakt kurz sperrt, will danach schreiben koennen und nicht erst wieder
/// eine Sicherheitsnummer vergleichen.
///
/// Deshalb merkt sich der Kontakt beim Blockieren, wie es vorher stand, und
/// genau das kommt zurueck. Die Sperre gegen den Umweg bleibt damit erhalten:
/// war er vorher `keyChanged`, ist er es danach wieder.
abstract final class BlockPolicy {
  /// Der Vertrauenszustand nach dem Aufheben der Blockierung.
  ///
  /// Fail-closed ohne Erinnerung: Bestandskontakte, die vor dieser Aenderung
  /// blockiert wurden, tragen den Vermerk nicht und behalten das bisherige
  /// Verhalten.
  static TrustState afterUnblock(Contact contact) {
    if (contact.trustState != TrustState.blocked) return contact.trustState;
    final vorher = contact.trustBeforeBlock;
    if (vorher == null || vorher == TrustState.blocked) {
      return TrustState.keyChanged;
    }
    return vorher;
  }
}
