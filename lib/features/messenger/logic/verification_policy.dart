import '../data/models/contact_model.dart';

/// Zwei Invarianten rund um das Bestaetigen eines Kontakts.
///
/// Der Anlass: Daniel wollte das Verifizieren verbessern und hat Code und
/// Bildschirmfotos extern begutachten lassen. Zwei Funde halten der
/// Gegenprobe am Quelltext stand, und beide betreffen dieselbe Schwaeche —
/// „bestaetigt" und „blockiert" hingen an einem einzigen Enum-Wert, der sich
/// gegenseitig ueberschreiben liess.
abstract final class VerificationPolicy {
  /// Ob ein Kontakt wirklich als bestaetigt gilt.
  ///
  /// `trustState == verified` allein genuegt nicht. Bestaetigt wurde immer ein
  /// **bestimmter** Schluessel, und genau der muss noch derselbe sein.
  /// [Contact.verifiedFingerprint] hielt das fest, wurde aber an fuenf
  /// Stellen geschrieben und **nirgends gelesen** — der Beweis lag ungenutzt
  /// herum, waehrend die Anzeige allein am Enum hing.
  ///
  /// Fehlt der Fingerprint oder passt er nicht, gilt der Kontakt als
  /// **unbestaetigt**. Fail-closed in die sichere Richtung: ein
  /// Bestandsdatensatz oder ein beschaedigter Zustand darf nie als bestaetigt
  /// durchgehen. Der Preis ist, dass ein alter Kontakt ohne festgehaltenen
  /// Fingerprint erneut bestaetigt werden will — das ist der richtige Preis.
  /// Die Regel selbst steht in [Contact.isVerified] — dort, wo die sechs
  /// Aufrufstellen der Oberflaeche sie ohnehin lesen. Hier steht sie nur
  /// benannt, damit sie zusammen mit [nachSchluesselwechsel] gepruefbar ist.
  static bool giltAlsBestaetigt(Contact contact) => contact.isVerified;

  /// Der Kontakt, nachdem ein Schluesselwechsel festgestellt wurde.
  ///
  /// Die Erkennung setzte bisher bedingungslos `trustState = keyChanged` —
  /// auch bei einem **blockierten** Kontakt. Damit hob ein Schluesselwechsel
  /// die Blockierung auf: `isBlocked` war danach falsch, und der Kontakt
  /// konnte wieder schreiben.
  ///
  /// Blockieren ist eine Entscheidung ueber die Verbindung, ein
  /// Schluesselwechsel eine Feststellung ueber den Schluessel. Das eine darf
  /// das andere nicht ueberschreiben. Bei einem blockierten Kontakt bleibt
  /// die Sperre deshalb stehen, und der Wechsel wandert in die Erinnerung —
  /// nach dem Entblocken steht die Warnung dann da, statt verloren zu sein
  /// (siehe [BlockPolicy.afterUnblock]).
  static Contact nachSchluesselwechsel(Contact contact) {
    if (contact.trustState == TrustState.blocked) {
      return contact.copyWith(trustBeforeBlock: TrustState.keyChanged);
    }
    return contact.copyWith(trustState: TrustState.keyChanged);
  }
}
