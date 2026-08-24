import '../data/models/contact_model.dart';

/// Warum eine eingehende Kontaktanfrage nicht angenommen wird.
///
/// Der Absender erfährt keinen dieser Gründe. Für ihn sieht jede Ablehnung
/// gleich aus — nämlich nach nichts. Ihm mitzuteilen „du wurdest blockiert"
/// würde eine Entscheidung verraten, die allein dem Empfänger gehört.
enum RequestRejection {
  /// Der Absender ist blockiert. Schlägt alles, unbegrenzt.
  blocked,

  /// Zu viele unbeantwortete Anfragen liegen schon herum.
  tooManyOpen,

  /// Von diesem Absender wurde schon zu oft abgelehnt.
  tooManyDeclines,
}

/// Die Zustandslogik der Kontaktanfragen — rein, ohne Firebase.
///
/// Bis hierher galt: eine Nachricht von jemandem, den man nicht hinzugefügt
/// hatte, wurde verworfen **und vom Server gelöscht**. Fügte der Empfänger den
/// Absender später hinzu, kam sie nicht nach; sie war endgültig weg.
///
/// Jetzt ist eine Kontaktanfrage vorgeschaltet, und geschrieben wird erst nach
/// der Annahme. Damit kann keine Nachricht mehr verloren gehen — zum Zeitpunkt
/// der Anfrage gibt es noch keine.
///
/// Der Entwurf mit Begründungen steht in `docs/KONTAKTANFRAGEN.md`.
abstract final class ContactRequestPolicy {
  /// Wie viele unbeantwortete Anfragen gleichzeitig offen sein dürfen.
  ///
  /// Nach dem Umbau kann jeder, der eine User-ID kennt, einen Eintrag in der
  /// Chatliste des anderen erzeugen — das ist der Preis dafür, dass Fremde
  /// einen überhaupt erreichen können. Diese Grenze ist eine der Bremsen.
  static const int maxOpenRequests = 20;

  /// Wie oft derselbe Absender abgelehnt werden darf, bevor nichts mehr
  /// durchkommt. Jemand kann sich vertippt haben; im Minutentakt anklopfen
  /// soll er nicht.
  static const int maxDeclines = 3;

  /// Ob eine eingehende Anfrage abzuweisen ist — und warum.
  ///
  /// `null` heißt: annehmen. [existing] ist der bereits bekannte Kontakt oder
  /// `null`, wenn der Absender völlig unbekannt ist. [openIncomingCount] zählt
  /// die derzeit unbeantworteten Anfragen.
  static RequestRejection? rejectIncoming({
    required Contact? existing,
    required int openIncomingCount,
  }) {
    if (existing != null) {
      if (existing.isBlocked) return RequestRejection.blocked;

      // Ein bereits angenommener Kontakt zählt nicht gegen die Obergrenze.
      // Sonst könnte ein voller Anfragenkorb den laufenden Betrieb mit
      // bestehenden Kontakten lahmlegen.
      if (existing.requestState == ContactRequestState.established) {
        return null;
      }

      if (existing.declineCount >= maxDeclines) {
        return RequestRejection.tooManyDeclines;
      }
    }

    if (openIncomingCount >= maxOpenRequests) {
      return RequestRejection.tooManyOpen;
    }
    return null;
  }

  /// Der Anfragezustand, nachdem eine Anfrage eingegangen ist.
  ///
  /// Aufzurufen erst, wenn [rejectIncoming] `null` geliefert hat.
  static ContactRequestState stateAfterIncoming(Contact? existing) {
    if (existing == null) return ContactRequestState.incoming;

    switch (existing.requestState) {
      // Beide haben sich hinzugefügt — damit sind beide einverstanden, und es
      // braucht keinen Knopf mehr.
      case ContactRequestState.outgoing:
        return ContactRequestState.established;

      // Ein bestehender Kontakt bleibt bestehen. Eine Anfrage von ihm ist
      // dann bedeutungslos, etwa nach einer Neuinstallation auf seiner Seite.
      case ContactRequestState.established:
        return ContactRequestState.established;

      // Abgelehnt, darf aber erneut fragen — die Zählung hat rejectIncoming
      // bereits geprüft.
      case ContactRequestState.declined:
      case ContactRequestState.incoming:
        return ContactRequestState.incoming;
    }
  }

  /// Der Kontakt, nachdem ich ihn selbst hinzugefügt habe.
  static Contact afterLocalAdd(Contact existing) {
    switch (existing.requestState) {
      // Er hat mich schon gefragt, ich füge ihn hinzu: beide sind
      // einverstanden. Ihn danach noch auf „Annehmen" zu schicken wäre eine
      // Rückfrage nach einer bereits getroffenen Entscheidung.
      case ContactRequestState.incoming:
        return existing.copyWith(
          requestState: ContactRequestState.established,
        );

      // Ich hatte ihn abgelehnt und will jetzt doch. Der Ablehnungszähler
      // bremst fremdes Anklopfen, nicht meine eigene Meinungsänderung.
      case ContactRequestState.declined:
        return existing.copyWith(
          requestState: ContactRequestState.outgoing,
          declineCount: 0,
        );

      case ContactRequestState.established:
      case ContactRequestState.outgoing:
        return existing;
    }
  }

  /// Der Kontakt, nachdem ich seine Anfrage angenommen habe.
  ///
  /// Ändert die kryptografische Vertrauenslage bewusst **nicht**: eine
  /// Anfrage anzunehmen heißt „ich kenne die Person", nicht „ich habe ihren
  /// Schlüssel geprüft". Verifikation bleibt ein eigener Schritt.
  static Contact afterAccept(Contact contact) =>
      contact.copyWith(requestState: ContactRequestState.established);

  /// Der Kontakt, nachdem ich seine Anfrage abgelehnt habe.
  ///
  /// Es wird nichts zurückgeschickt — siehe [RequestRejection].
  static Contact afterDecline(Contact contact) => contact.copyWith(
        requestState: ContactRequestState.declined,
        declineCount: contact.declineCount + 1,
      );

  /// Wie viele unbeantwortete Anfragen offen sind.
  static int openIncomingCount(Iterable<Contact> contacts) =>
      contacts.where((c) => c.isIncomingRequest).length;
}
