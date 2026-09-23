import '../data/models/chat_model.dart';
import '../data/models/message_model.dart';

/// Was in der Chatliste unter dem Namen steht, in welcher Reihenfolge die
/// Chats stehen, und welche Form die Uhrzeit rechts annimmt.
///
/// Drei Fragen, eine Datei, und alle drei ohne Oberflaeche und ohne Firebase —
/// die Hausregel dieses Projekts, siehe UnreadPolicy und SelfDestructPolicy.
/// Der Provider braucht Firebase und laeuft darum nicht im Test; was hier
/// steht, laesst sich pruefen.

// ─── Die Vorschau ───────────────────────────────────────────────────────────

/// Welche Art von Vorschau unter dem Namen steht.
enum VorschauArt {
  /// Gar keine — der Schalter steht aus, der Chat ist leer, oder der Text
  /// liegt nicht (mehr) im Speicher.
  keine,

  /// Der Text der letzten Nachricht.
  text,

  /// Eine einmalige Nachricht. **Nie ihr Text**: sie geht mit dem Oeffnen,
  /// und in der Chatliste stuende sie sonst offen da, ohne je geoeffnet
  /// worden zu sein.
  einmalig,

  /// Eine passwortgeschuetzte Nachricht, noch nicht aufgeschlossen.
  passwort,

  /// Ein Hinweis statt einer Nachricht: Screenshot, Aufnahme, Fristwechsel,
  /// geloeschtes Konto. Die Art steht daneben, den Satz bildet die
  /// Oberflaeche — er muss uebersetzt sein.
  hinweis,
}

/// Die Vorschau einer Chatkachel.
///
/// [vonMir] traegt das „Du: " davor, wie bei WhatsApp. [ereignis] ist nur bei
/// [VorschauArt.hinweis] gesetzt, [text] nur bei [VorschauArt.text].
typedef Vorschau = ({
  VorschauArt art,
  String? text,
  bool vonMir,
  SystemEventKind? ereignis,
});

const Vorschau _leer =
    (art: VorschauArt.keine, text: null, vonMir: false, ereignis: null);

abstract final class VorschauPolicy {
  /// Wie viele Zeichen aus der Nachricht hoechstens in die Kachel wandern.
  ///
  /// Die Kachel schneidet ohnehin mit „…" ab. Der Schnitt hier ist trotzdem
  /// wichtig: ohne ihn wandert eine Nachricht von zehntausend Zeichen durch
  /// jeden Aufbau der Liste, nur um danach in einer Zeile zu verschwinden.
  static const int maxZeichen = 120;

  /// Die Vorschau fuer einen Chat.
  ///
  /// [messages] ist der Verlauf, wie er im Speicher liegt — die Chatliste
  /// leitet ihre Vorschau **daraus** ab und nie aus einem zweiten Feld auf
  /// der Platte. Genau das war der Grund, `lastMessagePreview` am 30.08.2026
  /// aus dem Modell zu werfen: der Klartext lag damit zweimal in
  /// verschluesselten Dateien, im Nachrichtenspeicher und noch einmal in
  /// `chats.enc`. Zwei Kopien schuetzen nicht besser als eine, sie
  /// vergroessern nur die Flaeche.
  ///
  /// [zeigen] ist der Schalter aus den Einstellungen. Steht er aus, gibt es
  /// keine Vorschau — die Chatliste ist die eine Ansicht, die jemand zu sehen
  /// bekommt, ohne einen Chat zu oeffnen.
  static Vorschau fuer(
    Iterable<Message> messages, {
    required String? eigeneId,
    required bool zeigen,
  }) {
    if (!zeigen) return _leer;

    final letzte = juengste(messages);
    if (letzte == null) return _leer;

    final vonMir = eigeneId != null && letzte.senderId == eigeneId;

    if (letzte.isSystemEvent) {
      return (
        art: VorschauArt.hinweis,
        text: null,
        vonMir: vonMir,
        ereignis: letzte.systemEvent,
      );
    }

    // Eine einmalige Nachricht zuerst: sie darf unter keinen Umstaenden als
    // Text in der Liste stehen — auch nicht beim Absender, der ihren Text
    // ohnehin nicht mehr gespeichert hat.
    if (letzte.einmalig) {
      return (
        art: VorschauArt.einmalig,
        text: null,
        vonMir: vonMir,
        ereignis: null
      );
    }

    if (letzte.isLocked) {
      return (
        art: VorschauArt.passwort,
        text: null,
        vonMir: vonMir,
        ereignis: null
      );
    }

    final text = letzte.decryptedContent;
    if (text == null || text.trim().isEmpty) return _leer;

    return (
      art: VorschauArt.text,
      text: kuerzen(text),
      vonMir: vonMir,
      ereignis: null,
    );
  }

  /// Die juengste Nachricht eines Chats, oder `null`, wenn er leer ist.
  ///
  /// Eine eigene Funktion, weil **zwei** Stellen sie brauchen: die Vorschau
  /// und das Haekchen daneben. Liefe die Suche zweimal verschieden, gehoerte
  /// der Zustellstand zu einer anderen Nachricht als der Text darunter — und
  /// genau das faellt niemandem auf, bis es einmal falsch dasteht.
  ///
  /// Gesucht wird ueber die ganze Liste und nicht einfach das letzte Element
  /// genommen: die Liste im Provider ist nach Zustellung sortiert, und eine
  /// nachgereichte Nachricht kann hinten stehen und trotzdem aelter sein.
  static Message? juengste(Iterable<Message> messages) {
    Message? letzte;
    for (final m in messages) {
      if (letzte == null || !m.timestamp.isBefore(letzte.timestamp)) letzte = m;
    }
    return letzte;
  }

  /// Zeilenumbrueche raus, dann abschneiden.
  ///
  /// Ein Umbruch im Text macht die Kachel sonst hoeher als ihre Nachbarn —
  /// oder, mit `maxLines: 1`, verschluckt alles nach der ersten Zeile.
  static String kuerzen(String roh) {
    final eineZeile = roh.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (eineZeile.length <= maxZeichen) return eineZeile;
    return eineZeile.substring(0, maxZeichen);
  }
}

// ─── Die Reihenfolge ────────────────────────────────────────────────────────

abstract final class ChatOrder {
  /// Die Chatliste nach Aktualitaet ordnen, neueste zuoberst.
  ///
  /// Vorher hing die Reihenfolge allein daran, dass `_touchChat` den Chat an
  /// den Anfang schob. Das ging schief, sobald sich eine Uhrzeit aenderte,
  /// ohne dass etwas ankam: beim Loeschen einer einzelnen Nachricht etwa
  /// sprang ein Monate alter Chat nach oben, weil dieselbe Funktion beides
  /// tat. Und lief eine Nachricht ab, blieb der Chat oben stehen, obwohl
  /// darunter nichts Neues mehr lag.
  ///
  /// Sortiert wird an Ort und Stelle, wie die Liste auch im Provider liegt.
  /// Ein Chat ohne Nachricht steht unten, nicht oben: er ist frisch angelegt
  /// und hat noch nichts zu zeigen — aber er verdraengt keinen Verlauf.
  static void sortiere(List<Chat> chats) {
    chats.sort(vergleiche);
  }

  /// Der Vergleich als eigene Funktion, damit er sich pruefen laesst.
  ///
  /// Gleichstand wird ueber die Kennung aufgeloest und nicht offen gelassen:
  /// zwei Chats mit derselben Uhrzeit sollen bei jedem Aufbau in derselben
  /// Reihenfolge stehen, sonst springt die Liste.
  static int vergleiche(Chat a, Chat b) {
    final ta = a.lastMessageTime;
    final tb = b.lastMessageTime;
    if (ta == null && tb == null) return a.id.compareTo(b.id);
    if (ta == null) return 1;
    if (tb == null) return -1;
    final nachZeit = tb.compareTo(ta);
    return nachZeit != 0 ? nachZeit : a.id.compareTo(b.id);
  }
}

// ─── Die Uhrzeit ────────────────────────────────────────────────────────────

/// In welcher Form die Uhrzeit rechts in der Kachel steht.
enum ZeitForm {
  /// Heute: `14:32`.
  uhrzeit,

  /// Gestern: das Wort.
  gestern,

  /// Diese Woche: der Wochentag.
  wochentag,

  /// Aelter: das Datum.
  datum,
}

abstract final class ChatlistZeit {
  /// Welche Form die Uhrzeit dieses Zeitpunkts annimmt.
  ///
  /// Gerechnet wird in **Kalendertagen**, nicht in Vierundzwanzig-Stunden-
  /// Schritten. Vorher stand da `now.difference(time).inDays == 0` — und das
  /// ist um zehn nach Mitternacht fuer eine Nachricht von gestern 23:50 immer
  /// noch null. In der Liste stand dann `23:50`, als waere sie von heute.
  /// Derselbe Fehler eine Stufe hoeher liess „Dienstag" bis Mittwochabend
  /// stehen.
  ///
  /// [jetzt] wird hereingereicht statt selbst geholt — sonst laesst sich die
  /// Regel nicht pruefen.
  static ZeitForm form(DateTime zeit, DateTime jetzt) {
    final tage = tagesAbstand(zeit, jetzt);
    if (tage <= 0) return ZeitForm.uhrzeit;
    if (tage == 1) return ZeitForm.gestern;
    if (tage < 7) return ZeitForm.wochentag;
    return ZeitForm.datum;
  }

  /// Wie viele Kalendertage zwischen den beiden liegen.
  ///
  /// Negativ, wenn der Zeitpunkt in der Zukunft liegt — das kann vorkommen,
  /// wenn die Uhr der Gegenseite vorgeht. Dann gilt „heute": eine Uhrzeit ist
  /// immer noch besser als ein Datum von morgen.
  static int tagesAbstand(DateTime zeit, DateTime jetzt) {
    final a = DateTime(zeit.year, zeit.month, zeit.day);
    final b = DateTime(jetzt.year, jetzt.month, jetzt.day);
    return b.difference(a).inDays;
  }
}
