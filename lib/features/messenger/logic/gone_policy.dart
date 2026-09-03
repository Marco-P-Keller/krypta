import '../data/models/contact_model.dart';

/// Wie lange ein geloeschtes Konto noch sichtbar bleibt.
///
/// Loescht die Gegenseite ihr Konto, ist der Kontakt nicht sofort weg. Er
/// bleibt einen Tag stehen, der Chat ebenfalls, und im Chat steht, dass es
/// das Konto nicht mehr gibt. Der Grund ist schlicht: verschwaende der
/// Verlauf im selben Augenblick, saehe es aus wie ein Fehler der App. Ein
/// Tag reicht, um es zu bemerken und zu lesen, was noch dasteht.
///
/// Gerechnet wird ab der **Loeschung**, nicht ab dem Moment, in dem ich die
/// Meldung lese. Die Meldung traegt ihren eigenen Zeitstempel, ist
/// HMAC-signiert und ueberlebt ein langes Offline (30 Tage, siehe
/// [ControlMessagePolicy]). Wer eine Nacht offline war, bekommt den Kontakt
/// also nicht noch einmal volle 24 Stunden vorgesetzt — und eine Meldung,
/// die aelter als ein Tag ist, raeumt sofort ab.
abstract final class GonePolicy {
  /// Wie lange ein geloeschtes Konto noch in der Kontaktliste steht.
  static const Duration sichtbarkeit = Duration(hours: 24);

  /// Der Zeitpunkt, ab dem die Frist laeuft.
  ///
  /// [gemeldetMs] ist der Zeitstempel aus der Kontrollnachricht. Er kommt von
  /// der Gegenseite; ein Dritter kann ihn nicht faelschen (HMAC), die
  /// Gegenseite selbst schon. Deshalb die Klemme nach oben: ein Zeitstempel
  /// in der Zukunft wuerde den Eintrag sonst beliebig lange stehen lassen.
  /// Nach unten wird nicht geklemmt — eine alte Meldung *soll* sofort
  /// abraeumen.
  static DateTime loeschzeitpunkt(int gemeldetMs, DateTime jetzt) {
    final gemeldet = DateTime.fromMillisecondsSinceEpoch(gemeldetMs);
    return gemeldet.isAfter(jetzt) ? jetzt : gemeldet;
  }

  /// Ob die Sichtbarkeitsfrist dieses Kontakts abgelaufen ist.
  ///
  /// Ohne [Contact.goneAt] wird nichts geraeumt. Das betrifft Kontakte, die
  /// vor dieser Fassung als fort markiert wurden; sie bekommen den
  /// Zeitpunkt beim Start nachgetragen — siehe [brauchtNachtrag].
  static bool abgelaufen(Contact contact, DateTime jetzt) {
    if (!contact.isGone) return false;
    final seit = contact.goneAt;
    if (seit == null) return false;
    return !jetzt.isBefore(seit.add(sichtbarkeit));
  }

  /// Die Kennungen aller Kontakte, deren Frist abgelaufen ist.
  static List<String> abgelaufene(List<Contact> contacts, DateTime jetzt) =>
      contacts.where((c) => abgelaufen(c, jetzt)).map((c) => c.id).toList();

  /// Ob einem als fort markierten Kontakt der Zeitpunkt fehlt.
  ///
  /// Bestandsdaten aus der Zeit vor der Frist. Sie sofort wegzuwerfen waere
  /// falsch — der Nutzer hat den Hinweis vielleicht noch nicht gesehen.
  /// Sie bekommen den Zeitpunkt beim ersten Start nachgetragen und damit
  /// ihren Tag.
  static bool brauchtNachtrag(Contact contact) =>
      contact.isGone && contact.goneAt == null;
}
