import '../data/models/message_model.dart';

/// Wann eine Nachricht verschwindet — und bei wem.
///
/// **Jede Frist laeuft ab der Zustellung.** Seit dem 02.09.2026 gilt das auch
/// fuer den Chat-Timer; vorher hing er am Lesen. Daniels Beispiel: Frist zehn
/// Minuten, Zustellung um 18:00, geloescht um 18:10, unabhaengig davon, ob
/// die Nachricht geoeffnet wurde.
///
/// Die Folge ist beabsichtigt: **auch Ungelesenes verschwindet**. Bis zum
/// 01.09. war es umgekehrt, damit nichts verfaellt, was niemand gesehen hat.
/// Die Umkehr ist seine Entscheidung.
///
/// Damit spielt es fuer die Zeitrechnung keine Rolle mehr, ob die Frist von
/// der Nachricht selbst oder vom Chat stammt. `selfDestructFromChat` bleibt
/// nur, weil das Feld noch auf der Leitung reist und aeltere Geraete es
/// erwarten.
///
/// **Eine Ausnahme bleibt und ist wichtig:** wird der Chat-Timer
/// nachtraeglich eingeschaltet, rechnet die Uhr ab dem **Einschalten**, nicht
/// ab der Zustellung. Ohne das waeren beim Umlegen des Schalters alle
/// aelteren Nachrichten im selben Moment ueberfaellig und der ganze sichtbare
/// Verlauf verschwaende mit einem Tipp.
///
/// Auf dem Geraet des Empfaengers ist `timestamp` der Zustellzeitpunkt, beim
/// Absender der Sendezeitpunkt. Die beiden liegen ein paar Sekunden
/// auseinander, weil der Abruf gestreut ist. Wartet die Nachricht laenger auf
/// dem Server, laeuft die Fassung des Absenders zuerst ab; anders geht es
/// nicht, solange sie dort auf ihn wartet.
abstract final class SelfDestructPolicy {
  /// Ob diese Nachricht abgelaufen ist.
  ///
  /// [now] wird hereingereicht statt selbst geholt — sonst laesst sich die
  /// Regel nicht pruefen. [chatTimer] und [chatTimerSetAt] beschreiben den
  /// Chat-Timer, wie er **jetzt** gesetzt ist; er wird bei jeder Runde neu
  /// ausgewertet und wirkt deshalb auch auf Nachrichten, die es schon vor dem
  /// Einschalten gab.
  static bool expired(
    Message m,
    DateTime now, {
    Duration? chatTimer,
    DateTime? chatTimerSetAt,
  }) {
    final ablauf =
        deadline(m, chatTimer: chatTimer, chatTimerSetAt: chatTimerSetAt);
    return ablauf != null && now.isAfter(ablauf);
  }

  /// Wann diese Nachricht faellig ist, oder `null`, wenn nie.
  static DateTime? deadline(
    Message m, {
    Duration? chatTimer,
    DateTime? chatTimerSetAt,
  }) {
    // Ein Hinweis im Verlauf laeuft nie ab. Die Dauer steht bei einem
    // Fristwechsel am Hinweis, damit der Text sie nennen kann — sie darf ihn
    // aber nicht selbst wegraeumen. Ein Hinweis, der ausgerechnet dann
    // verschwindet, wenn man ihn braucht, waere sinnlos.
    if (m.isSystemEvent) return null;

    // Welche Frist gilt.
    //
    // Kam sie vom Chat, gilt die **aktuelle** Einstellung des Chats: sie
    // gehoert beiden Seiten und wird zwischen ihnen abgeglichen. Waere
    // stattdessen die mitgereiste Zahl massgeblich, liefe nach jeder
    // Aenderung jede Seite mit dem, was zufaellig in ihren alten Nachrichten
    // steht. Die mitgereiste Zahl bleibt der Rueckfall — geht die Meldung
    // ueber die neue Einstellung verloren, wird nach der alten Frist
    // geloescht und nicht gar nicht.
    //
    // Eine Nachricht mit **eigener** Frist behaelt sie: der Absender hat sie
    // dieser einen Nachricht mitgegeben, nicht dem Chat.
    final frist = m.selfDestructFromChat
        ? (chatTimer ?? m.selfDestructDuration)
        : (m.selfDestructDuration ?? chatTimer);
    if (frist == null) return null;

    // Gerechnet wird ab der **Zustellung**, und zwar ab der wirklichen: dem
    // Zeitpunkt, den beide Geraete gleich lesen. `timestamp` taugte dafuer
    // nicht — beim Absender ist er der Sendezeitpunkt, beim Empfaenger der
    // des Abholens, und dazwischen liegt die Wartezeit auf dem Server.
    //
    // Noch nicht zugestellt heisst: keine Uhr. Was die Gegenseite nie
    // bekommen hat, darf beim Absender nicht verschwinden.
    final zugestellt = m.deliveredAt;
    if (zugestellt == null) return null;

    // `readAt` spielt keine Rolle: wer erst nach neun von zehn Minuten
    // hineinschaut, hat noch eine.
    //
    // Die einzige Verschiebung ist der nachtraeglich eingeschaltete
    // Chat-Timer. Ohne sie waeren beim Umlegen des Schalters alle aelteren
    // Nachrichten sofort ueberfaellig, und der ganze sichtbare Verlauf
    // verschwaende mit einem Tipp.
    final start = chatTimerSetAt != null && chatTimerSetAt.isAfter(zugestellt)
        ? chatTimerSetAt
        : zugestellt;
    return start.add(frist);
  }

  /// Welcher Zustellzeitpunkt aus einer Meldung der Gegenseite gilt.
  ///
  /// Die Meldung ist signiert, aber sie kommt von einer fremden Uhr. Geht sie
  /// vor, liefe meine Nachricht nie ab; geht sie nach, waere sie
  /// rueckwirkend faellig. Beides wird hier gekappt: nicht vor dem Senden —
  /// frueher kann sie nicht angekommen sein — und nicht in der Zukunft.
  static DateTime zustellzeitpunkt({
    required DateTime gemeldet,
    required DateTime gesendet,
    required DateTime jetzt,
  }) {
    if (gemeldet.isBefore(gesendet)) return gesendet;
    if (gemeldet.isAfter(jetzt)) return jetzt;
    return gemeldet;
  }

  /// Bestand ohne Zustellzeitpunkt nachtragen. Meldet, ob etwas geschrieben
  /// werden muss.
  ///
  /// Alles von vor dem 04.09.2026 kennt das Feld nicht, und ohne Zeitpunkt
  /// laeuft keine Uhr — der ganze Bestand laege sonst fuer immer da.
  ///
  /// Zwei Faelle sind nachweislich zugestellt: was von drueben kam (ich habe
  /// es ja) und was als zugestellt gemeldet war. Der Sendezeitpunkt ist die
  /// beste Schaetzung, die davon noch uebrig ist.
  ///
  /// **Nicht** angefasst wird mein eigener Postausgang: eine Nachricht, deren
  /// Zustellung nie gemeldet wurde, bekaeme sonst bei jedem Start einen
  /// erfundenen Zeitpunkt und liefe ab, ohne je angekommen zu sein.
  static bool zustellungNachtragen(List<Message> messages, String eigeneId) {
    var geaendert = false;
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (m.deliveredAt != null || m.isSystemEvent) continue;
      final zugestellt = m.senderId != eigeneId ||
          m.status == MessageStatus.delivered ||
          m.status == MessageStatus.read;
      if (!zugestellt) continue;
      messages[i] = m.copyWith(deliveredAt: m.timestamp);
      geaendert = true;
    }
    return geaendert;
  }

  /// Ob der Ablauf dieser Nachricht der Gegenseite mitzuteilen ist.
  ///
  /// Nur der Empfaenger meldet: bei „Direkt nach dem Lesen" weiss auch nur er,
  /// wann es soweit ist — naemlich wenn er den Chat verlaesst.
  ///
  /// [chatVergaenglich] sagt, dass die **Regel des Chats** diese Nachricht
  /// vergaenglich macht. Sie traegt dann keine eigene Markierung, und ohne
  /// diesen Hinweis bliebe sie beim Absender stehen.
  static bool announceBurn(Message m, String myId,
          {bool chatVergaenglich = false}) =>
      (_vergaenglich(m) || (chatVergaenglich && !m.isSystemEvent)) &&
      m.senderId != myId;

  /// Die kuerzeste Frist, die eine Gegenseite mir vorgeben darf.
  ///
  /// Die Frist steht in ihrer Nachricht. Ohne Untergrenze koennte sie eine
  /// schicken, die nach einer Millisekunde verschwindet — bei einem
  /// sendegebundenen Timer sogar, bevor ich sie ueberhaupt gesehen habe.
  /// Ihre Nachricht zurueckzunehmen ist ihr gutes Recht; mir die Gelegenheit
  /// zum Lesen zu stehlen nicht.
  static const Duration mindestFrist = Duration(seconds: 10);

  /// Die laengste Frist. Laenger liegt ohnehin nichts auf dem Server.
  static const Duration maximalFrist = Duration(days: 30);

  /// Eine von der Gegenseite vorgegebene Frist in vertretbare Grenzen
  /// bringen. `null` heisst: kein Timer.
  static Duration? clampFremdeFrist(int rohMs) {
    if (rohMs <= 0) return null;
    if (rohMs < mindestFrist.inMilliseconds) return mindestFrist;
    if (rohMs > maximalFrist.inMilliseconds) return maximalFrist;
    return Duration(milliseconds: rohMs);
  }

  /// Ob eine Ablaufmeldung der Gegenseite diese Nachricht entfernen darf.
  ///
  /// Zwei Bedingungen, und beide muessen halten: es muss **meine** Nachricht
  /// sein — die Gegenseite meldet ja den Ablauf dessen, was ich ihr geschickt
  /// habe — und sie muss einen Timer getragen haben. Ohne die zweite koennte
  /// eine Gegenseite mit erfundenen Ablaufmeldungen beliebige Nachrichten von
  /// meinem Geraet raeumen. Entfernt werden darf nur, was ich selbst als
  /// vergaenglich markiert habe.
  ///
  /// [chatVergaenglich] oeffnet die Schranke fuer die **Regel des Chats**:
  /// steht sie auf einer Frist oder auf „Direkt nach dem Lesen", ist das
  /// dieselbe Zusage wie eine Markierung an der Nachricht — nur eben fuer den
  /// ganzen Chat, und sie gehoert beiden Seiten. Ohne das bliebe eine
  /// Nachricht beim Absender stehen, waehrend sie drueben verschwindet;
  /// genau dieser Fehler steckte bis zum 04.09.2026 in der einmaligen
  /// Nachricht.
  static bool acceptBurn(Message m, String myId,
          {bool chatVergaenglich = false}) =>
      m.senderId == myId &&
      (_vergaenglich(m) || (chatVergaenglich && !m.isSystemEvent));

  /// Ob diese Nachricht faellig ist, weil der Chat auf „Direkt nach dem
  /// Lesen" steht und der Empfaenger sie gelesen hat.
  ///
  /// Keine Uhr, sondern ein Ereignis: geraeumt wird beim Verlassen des Chats.
  /// Waehrend er offen ist, bleibt die Nachricht stehen — sonst verschwaende
  /// sie unter den Augen dessen, der gerade liest.
  ///
  /// `readAt` setzt der Empfaenger fuer sich, **unabhaengig von der
  /// Lesebestaetigung**. Die entscheidet nur, ob die Gegenseite davon
  /// erfaehrt; ob geloescht wird, haengt nicht daran.
  static bool nachLesenFaellig(Message m, {required bool regelNachLesen}) =>
      regelNachLesen && !m.isSystemEvent && m.readAt != null;

  /// Ob ich diese Nachricht selbst als vergaenglich markiert habe.
  ///
  /// Nur solche darf eine Ablaufmeldung der Gegenseite entfernen. Ohne diese
  /// Schranke koennte sie mit erfundenen Meldungen beliebige Nachrichten von
  /// meinem Geraet raeumen.
  ///
  /// `einmalig` zaehlt mit, und das fehlte bis zum 04.09.2026. Eine einmalige
  /// Nachricht traegt bewusst keine Frist — sie geht mit dem Oeffnen, nicht
  /// mit der Uhr — und `burnAfterRead` wird seit dem 02.09. nicht mehr
  /// gesetzt. Damit traf die Ablaufmeldung des Empfaengers hier auf zwei
  /// falsche Antworten und wurde verworfen: die Nachricht verschwand drueben,
  /// blieb aber beim Absender stehen. Genau das war der zugesagte Fall nicht.
  static bool _vergaenglich(Message m) =>
      !m.isSystemEvent &&
      (m.selfDestructDuration != null || m.burnAfterRead || m.einmalig);

  // ─── Der Hinweis bei einer geaenderten Chat-Frist ──────────────────────

  /// Der Anfang der Art, unter der eine geaenderte Chat-Frist reist.
  static const String artChatFrist = 'sdChanged';

  /// Die Art fuer eine Kontrollnachricht, die die neue Regel des Chats
  /// meldet.
  ///
  /// Alles steckt **in der Art**: `sdChanged:<wert>:<zaehler>`, wobei der
  /// Wert `off`, `read` oder eine Zahl in Millisekunden ist. Eigene Felder
  /// haetten jede Signatur veraendert — ein Geraet mit einer aelteren Fassung
  /// wuerde danach auch Screenshot-Hinweise verwerfen. Die Art ist ohnehin
  /// Teil der Signatur, also faelschungssicher, und eine unbekannte Art wird
  /// von aelteren Fassungen schlicht ignoriert.
  ///
  /// Der Zaehler steigt bei jeder Aenderung. Er entscheidet, welche von zwei
  /// Aenderungen gewinnt — die Wanduhr taugt dafuer nicht, siehe
  /// [fremdeRegelUebernehmen].
  static String artFuerRegel({
    Duration? frist,
    bool nachLesen = false,
    required int version,
  }) {
    final wert = nachLesen
        ? 'read'
        : (frist == null ? 'off' : '${frist.inMilliseconds}');
    return '$artChatFrist:$wert:$version';
  }

  /// Ob diese Art eine geaenderte Chat-Regel meldet.
  static bool istChatFristAenderung(String art) =>
      art.startsWith('$artChatFrist:');

  /// Die Regel aus der Art herauslesen, oder `null`, wenn es keine ist.
  ///
  /// Fail-closed: was sich nicht lesen laesst, gilt als ausgeschaltet. Lieber
  /// keine Frist als eine erfundene, die den halben Verlauf raeumt.
  ///
  /// Bestand: die alte Form ohne Zaehler (`sdChanged:300000`) wird weiter
  /// gelesen und zaehlt als Version null — Build 100 schickt sie noch, und
  /// jede spaetere Aenderung soll sie ueberstimmen.
  static ({Duration? frist, bool nachLesen, int version})? regelAusArt(
      String art) {
    if (!istChatFristAenderung(art)) return null;
    final teile = art.substring(artChatFrist.length + 1).split(':');
    final wert = teile.first;
    final version = teile.length > 1 ? (int.tryParse(teile[1]) ?? 0) : 0;
    if (wert == 'read') {
      return (frist: null, nachLesen: true, version: version);
    }
    final ms = int.tryParse(wert);
    return (
      frist: ms == null || ms <= 0 ? null : clampFremdeFrist(ms),
      nachLesen: false,
      version: version,
    );
  }

  /// Ob die gemeldete Regel der Gegenseite meine ersetzt.
  ///
  /// Der hoehere Zaehler gewinnt. Bei Gleichstand die groessere Kennung —
  /// nicht weil sie mehr wert waere, sondern weil beide Geraete dieselbe
  /// Antwort brauchen. Ohne diese Regel bleiben sie nach zwei gleichzeitigen
  /// Aenderungen dauerhaft verschieden eingestellt: jeder haette die des
  /// anderen uebernommen und die eigene verworfen.
  ///
  /// Bewusst **nicht** nach Uhrzeit: geht eine der beiden Uhren nach, wuerden
  /// ihre Aenderungen fuer immer verworfen.
  static bool fremdeRegelUebernehmen({
    required int meineVersion,
    required int fremdeVersion,
    required String meineId,
    required String fremdeId,
  }) {
    if (fremdeVersion != meineVersion) return fremdeVersion > meineVersion;
    return fremdeId.compareTo(meineId) > 0;
  }
}
