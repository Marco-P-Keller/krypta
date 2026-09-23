import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/logic/einmalig_policy.dart';
import 'package:kryptaapp/features/messenger/logic/nachrichtenregel.dart';
import 'package:kryptaapp/features/messenger/logic/self_destruct_policy.dart';
import 'package:kryptaapp/features/messenger/logic/unread_policy.dart';

/// Die vier Löschregeln aus Daniels Liste vom 22.09.2026, **von beiden
/// Seiten gesehen**.
///
/// Sein Satz darunter lautet: „Alle vier Funktionen sind bereits
/// implementiert, enthalten aktuell jedoch noch Bugs bzw. funktionieren
/// teilweise nicht wie vorgesehen." Die Einzelregeln sind längst geprüft —
/// in self_destruct_test, einmalig_policy_test, loeschregel_test. Was nie
/// geprüft war, ist ihr **Zusammenspiel über zwei Geräte**: fast jeder Fehler
/// dieser Funktionen in den letzten Wochen war eine Asymmetrie. Beim
/// Empfänger weg, beim Absender noch da (04.09.), oder umgekehrt ungeöffnet
/// verschwunden (07.09.).
///
/// Deshalb hier ein Postfach mit zwei Geräten, das genau die Schritte geht,
/// die auch der Provider geht — und mit **denselben** Regeln, nicht mit
/// nachgebauten. Was hier steht, ist Daniels Liste als ausführbarer Text.
void main() {
  const ich = 'ich';
  const marco = 'marco';

  /// Ein Gerät: sein Verlauf und die Regel des Chats, wie sie dort steht.
  ///
  /// Die Regel gehört beiden Seiten und wird abgeglichen; hier wird sie auf
  /// beiden Geräten gleich gesetzt, weil genau das der Provider tut.
  Map<String, List<Message>> verlaeufe = {};
  late DateTime jetzt;
  late Duration? chatFrist;
  late DateTime? fristSeit;
  late bool chatNachLesen;

  setUp(() {
    verlaeufe = {ich: <Message>[], marco: <Message>[]};
    jetzt = DateTime(2026, 9, 22, 19, 4);
    chatFrist = null;
    fristSeit = null;
    chatNachLesen = false;
  });

  List<Message> bei(String geraet) => verlaeufe[geraet]!;

  Message? finde(String geraet, String id) {
    for (final m in bei(geraet)) {
      if (m.id == id) return m;
    }
    return null;
  }

  bool liegtBei(String geraet, String id) => finde(geraet, id) != null;

  /// Die Gegenseite meldet den Ablauf; das andere Gerät räumt, wenn es darf.
  void meldeAblauf(String von, String an, String id) {
    final liste = bei(an);
    final idx = liste.indexWhere((m) => m.id == id);
    if (idx == -1) return;
    final chatVergaenglich = chatFrist != null || chatNachLesen;
    if (!SelfDestructPolicy.acceptBurn(liste[idx], an,
        chatVergaenglich: chatVergaenglich)) {
      return;
    }
    liste.removeAt(idx);
  }

  /// Senden — die Regel entscheidet, was an der Nachricht hängt.
  String senden({
    required Nachrichtenregel regel,
    Duration? einzelFrist,
    String text = 'Kommst du?',
    String von = marco,
  }) {
    final auftrag = RegelPolicy.auftrag(
      regel: regel,
      einzelFrist: einzelFrist,
      chatFrist: chatFrist,
    );
    final id = 'm${bei(von).length + 1}_$von';
    bei(von).add(Message(
      id: id,
      chatId: 'c1',
      senderId: von,
      recipientId: von == ich ? marco : ich,
      encryptedContent: '',
      // Bei einer einmaligen Nachricht behält der Absender keinen Klartext.
      decryptedContent:
          EinmaligPolicy.klartextBeimAbsender(einmalig: auftrag.einmalig)
              ? text
              : null,
      timestamp: jetzt,
      status: MessageStatus.sent,
      selfDestructDuration: auftrag.frist,
      selfDestructFromChat: auftrag.vomChat,
      burnAfterRead: auftrag.nachAnsehen,
      einmalig: auftrag.einmalig,
    ));
    return id;
  }

  /// Zustellen: die Gegenseite holt sie ab, der Absender erfährt wann.
  void zustellen(String id, {bool chatOffen = false}) {
    final absender = bei(marco).any((m) => m.id == id) ? marco : ich;
    final empfaenger = absender == marco ? ich : marco;
    final quelle = finde(absender, id)!;

    final gelesen = UnreadPolicy.beiZustellungGelesen(
      senderId: absender,
      eigeneId: empfaenger,
      chatId: 'c1',
      offenerChat: chatOffen ? 'c1' : null,
      imVordergrund: true,
    );

    bei(empfaenger).add(Message(
      id: id,
      chatId: 'c1',
      senderId: absender,
      recipientId: empfaenger,
      encryptedContent: '',
      decryptedContent: 'Kommst du?',
      timestamp: jetzt,
      deliveredAt: jetzt,
      readAt: gelesen ? jetzt : null,
      status: gelesen ? MessageStatus.read : MessageStatus.delivered,
      selfDestructDuration: quelle.selfDestructDuration,
      selfDestructFromChat: quelle.selfDestructFromChat,
      burnAfterRead: quelle.burnAfterRead,
      einmalig: quelle.einmalig,
    ));

    // Und die Zustellbestätigung zurück an den Absender.
    final liste = bei(absender);
    final idx = liste.indexWhere((m) => m.id == id);
    liste[idx] = liste[idx].copyWith(
      deliveredAt: SelfDestructPolicy.zustellzeitpunkt(
        gemeldet: jetzt,
        gesendet: liste[idx].timestamp,
        jetzt: jetzt,
      ),
      status: MessageStatus.delivered,
    );
  }

  /// Der Empfänger öffnet den Chat: alles darin gilt als gelesen.
  void lesen({String wer = ich}) {
    final liste = bei(wer);
    for (var i = 0; i < liste.length; i++) {
      if (liste[i].senderId == wer || liste[i].readAt != null) continue;
      liste[i] = liste[i].copyWith(readAt: jetzt, status: MessageStatus.read);
    }
  }

  /// Der Empfänger verlässt den Chat — oder wischt die App weg, das ist
  /// dasselbe Ereignis.
  void verlassen({String wer = ich}) {
    final liste = bei(wer);
    final gegenseite = wer == ich ? marco : ich;
    final chatVergaenglich = chatFrist != null || chatNachLesen;
    final faellig = liste
        .where((m) =>
            (m.burnAfterRead && m.readAt != null) ||
            SelfDestructPolicy.nachLesenFaellig(m,
                regelNachLesen: chatNachLesen))
        .toList();
    for (final m in faellig) {
      if (SelfDestructPolicy.announceBurn(m, wer,
          chatVergaenglich: chatVergaenglich)) {
        meldeAblauf(wer, gegenseite, m.id);
      }
      liste.removeWhere((x) => x.id == m.id);
    }
  }

  /// Die Uhr weiterstellen und auf beiden Geräten aufräumen, wie es der
  /// Zeitgeber im Provider im Sekundentakt tut.
  void uhrVor(Duration d) {
    jetzt = jetzt.add(d);
    for (final geraet in [ich, marco]) {
      final liste = bei(geraet);
      final gegenseite = geraet == ich ? marco : ich;
      final chatVergaenglich = chatFrist != null || chatNachLesen;
      final faellig = liste
          .where((m) => SelfDestructPolicy.expired(m, jetzt,
              chatTimer: chatFrist, chatTimerSetAt: fristSeit))
          .toList();
      for (final m in faellig) {
        if (SelfDestructPolicy.announceBurn(m, geraet,
            chatVergaenglich: chatVergaenglich)) {
          meldeAblauf(geraet, gegenseite, m.id);
        }
        liste.removeWhere((x) => x.id == m.id);
      }
    }
  }

  /// Der Empfänger öffnet eine einmalige Nachricht. Gibt den Text zurück,
  /// oder `null`, wenn es nichts mehr zu öffnen gibt.
  String? oeffnen(String id, {String wer = ich}) {
    final liste = bei(wer);
    final idx = liste.indexWhere((m) => m.id == id);
    if (idx == -1) return null;
    final text = liste[idx].decryptedContent;
    if (text == null || text.isEmpty) return null;
    // Erst von der Platte, dann melden, dann anzeigen — die Reihenfolge ist
    // die Zusage: wer danach abstürzt, hat sie trotzdem verbraucht.
    liste.removeAt(idx);
    meldeAblauf(wer, wer == ich ? marco : ich, id);
    return text;
  }

  /// Die Regel des Chats umstellen. Sie gehört beiden Seiten, also stellen
  /// sich beide Geräte um.
  void regelSetzen({Duration? frist, bool nachLesen = false}) {
    chatFrist = frist;
    chatNachLesen = nachLesen;
    fristSeit = frist == null ? null : jetzt;
  }

  // ── 1. Selbstlösch-Timer für den gesamten Chat ─────────────────────────

  group('1. Der Timer für den ganzen Chat', () {
    test('Daniels Beispiel: 19:04 zugestellt, 5 Minuten, 19:09 weg', () {
      regelSetzen(frist: const Duration(minutes: 5));
      final id = senden(regel: Nachrichtenregel.chatregel);
      zustellen(id);

      uhrVor(const Duration(minutes: 4, seconds: 59));
      expect(liegtBei(ich, id), isTrue, reason: 'um 19:08:59 liegt sie noch');
      expect(liegtBei(marco, id), isTrue);

      uhrVor(const Duration(seconds: 2));
      expect(liegtBei(ich, id), isFalse, reason: 'um 19:09:01 ist sie weg');
      expect(liegtBei(marco, id), isFalse,
          reason: 'und zwar auf beiden Geräten');
    });

    test('die Uhr läuft ab Zustellung, nicht ab dem Senden', () {
      regelSetzen(frist: const Duration(minutes: 5));
      final id = senden(regel: Nachrichtenregel.chatregel);

      // Die Gegenseite ist offline. Zehn Minuten später ist die Nachricht
      // noch da: zugestellt wurde sie nie.
      uhrVor(const Duration(minutes: 10));
      expect(liegtBei(marco, id), isTrue,
          reason: 'was nie ankam, darf beim Absender nicht verschwinden');

      zustellen(id);
      uhrVor(const Duration(minutes: 5, seconds: 1));
      expect(liegtBei(marco, id), isFalse);
      expect(liegtBei(ich, id), isFalse);
    });

    test('auch Ungelesenes verschwindet', () {
      // Daniels Umkehr vom 02.09.2026. Vorher hing die Uhr am Lesen.
      regelSetzen(frist: const Duration(minutes: 5));
      final id = senden(regel: Nachrichtenregel.chatregel);
      zustellen(id);

      uhrVor(const Duration(minutes: 5, seconds: 1));
      expect(liegtBei(ich, id), isFalse);
    });

    test('nachträglich eingeschaltet räumt er nicht den ganzen Verlauf', () {
      // Ohne diese Ausnahme wäre mit einem Tipp alles Ältere im selben
      // Moment überfällig.
      final id = senden(regel: Nachrichtenregel.chatregel);
      zustellen(id);
      uhrVor(const Duration(hours: 3));

      regelSetzen(frist: const Duration(minutes: 5));
      expect(liegtBei(ich, id), isTrue, reason: 'die Frist läuft ab jetzt');

      uhrVor(const Duration(minutes: 5, seconds: 1));
      expect(liegtBei(ich, id), isFalse);
    });
  });

  // ── 2. Derselbe Timer für einzelne Nachrichten ─────────────────────────

  group('2. Der Timer für eine einzelne Nachricht', () {
    test('sie geht nach ihrer eigenen Frist, auf beiden Geräten', () {
      final id = senden(
        regel: Nachrichtenregel.frist,
        einzelFrist: const Duration(minutes: 30),
      );
      zustellen(id);

      uhrVor(const Duration(minutes: 29));
      expect(liegtBei(ich, id), isTrue);

      uhrVor(const Duration(minutes: 2));
      expect(liegtBei(ich, id), isFalse);
      expect(liegtBei(marco, id), isFalse);
    });

    test('die Nachricht daneben bleibt stehen', () {
      // Der Unterschied zum Chat-Timer: er gilt für alles, diese Frist nur
      // für diese eine.
      final mitFrist = senden(
        regel: Nachrichtenregel.frist,
        einzelFrist: const Duration(minutes: 5),
      );
      final ohne = senden(regel: Nachrichtenregel.chatregel);
      zustellen(mitFrist);
      zustellen(ohne);

      uhrVor(const Duration(minutes: 5, seconds: 1));
      expect(liegtBei(ich, mitFrist), isFalse);
      expect(liegtBei(ich, ohne), isTrue);
      expect(liegtBei(marco, ohne), isTrue);
    });

    test('sie behält ihre Frist, wenn der Chat umgestellt wird', () {
      regelSetzen(frist: const Duration(days: 7));
      final id = senden(
        regel: Nachrichtenregel.frist,
        einzelFrist: const Duration(minutes: 5),
      );
      zustellen(id);

      regelSetzen(frist: const Duration(hours: 24));
      uhrVor(const Duration(minutes: 5, seconds: 1));
      expect(liegtBei(ich, id), isFalse,
          reason: 'ihre eigene Frist gehört ihr, nicht dem Chat');
    });
  });

  // ── 3. Nach Ansehen löschen ────────────────────────────────────────────

  group('3. Nach Ansehen löschen', () {
    test('für eine einzelne Nachricht: gelesen und Chat verlassen', () {
      final id = senden(regel: Nachrichtenregel.nachAnsehen);
      zustellen(id);

      uhrVor(const Duration(hours: 5));
      expect(liegtBei(ich, id), isTrue,
          reason: 'ungelesen bleibt sie liegen, sie hat keine Uhr');

      lesen();
      expect(liegtBei(ich, id), isTrue,
          reason: 'während der Chat offen ist, verschwindet nichts unter '
              'den Augen dessen, der gerade liest');

      verlassen();
      expect(liegtBei(ich, id), isFalse);
      expect(liegtBei(marco, id), isFalse,
          reason: 'die Meldung räumt sie auch beim Absender');
    });

    test('für den ganzen Chat: dieselbe Regel, ohne Markierung je Nachricht',
        () {
      regelSetzen(nachLesen: true);
      final id = senden(regel: Nachrichtenregel.chatregel);
      zustellen(id);
      lesen();
      verlassen();

      expect(liegtBei(ich, id), isFalse);
      expect(liegtBei(marco, id), isFalse);
    });

    test('was nie gelesen wurde, überlebt das Verlassen', () {
      regelSetzen(nachLesen: true);
      final id = senden(regel: Nachrichtenregel.chatregel);
      zustellen(id);

      verlassen();
      expect(liegtBei(ich, id), isTrue);
      expect(liegtBei(marco, id), isTrue);
    });

    test('das Wegwischen der App zählt wie das Verlassen', () {
      // Genau der Fall, in dem sie am wenigsten liegen bleiben darf: das
      // Gerät wandert aus der Hand, während der Chat offen ist.
      final id = senden(regel: Nachrichtenregel.nachAnsehen);
      zustellen(id, chatOffen: true);
      expect(finde(ich, id)!.readAt, isNotNull,
          reason: 'bei offenem Chat gilt sie sofort als gelesen');

      verlassen();
      expect(liegtBei(ich, id), isFalse);
      expect(liegtBei(marco, id), isFalse);
    });
  });

  // ── 4. Die Nachricht zur einmaligen Ansicht ────────────────────────────

  group('4. Einmal ansehen', () {
    test('sie wird normal zugestellt und wartet, ohne Uhr', () {
      regelSetzen(frist: const Duration(minutes: 5));
      final id = senden(regel: Nachrichtenregel.einmalig);
      zustellen(id);

      // Der Fehler vom 07.09.2026: sie erbte die Chat-Frist und war nach
      // fünf Minuten fort, ungeöffnet, auf beiden Geräten.
      uhrVor(const Duration(days: 2));
      expect(liegtBei(ich, id), isTrue);
      expect(liegtBei(marco, id), isTrue);
    });

    test('auch „direkt nach dem Lesen" räumt sie nicht weg', () {
      // Ihr readAt steht schon bei der Zustellung, wenn der Chat offen ist —
      // gelesen ist dann die Blase mit dem Tor, nicht der Inhalt dahinter.
      regelSetzen(nachLesen: true);
      final id = senden(regel: Nachrichtenregel.einmalig);
      zustellen(id, chatOffen: true);

      verlassen();
      expect(liegtBei(ich, id), isTrue,
          reason: 'wer nur kurz hineinsah, hätte sie sonst nie gesehen');
    });

    test('das Öffnen verbraucht sie, auf beiden Geräten', () {
      final id = senden(regel: Nachrichtenregel.einmalig);
      zustellen(id);

      expect(oeffnen(id), 'Kommst du?');
      expect(liegtBei(ich, id), isFalse);
      expect(liegtBei(marco, id), isFalse,
          reason: 'der Fehler vom 04.09.: drüben weg, beim Absender noch da');
    });

    test('ein zweites Öffnen gibt es nicht', () {
      final id = senden(regel: Nachrichtenregel.einmalig);
      zustellen(id);

      oeffnen(id);
      expect(oeffnen(id), isNull);
    });

    test('der Absender behält ihren Text gar nicht erst', () {
      final id = senden(regel: Nachrichtenregel.einmalig, von: ich);
      expect(finde(ich, id)!.decryptedContent, isNull,
          reason: 'sonst liegt er im Auszug des Speichers, unsichtbar in der '
              'Blase, aber da');
    });
  });

  // ── Und das Zusammenspiel, das keine Regel allein beantwortet ──────────

  group('Zusammen', () {
    test('vier Nachrichten nebeneinander, jede nach ihrer eigenen Regel', () {
      regelSetzen(frist: const Duration(hours: 1));
      final imChat = senden(regel: Nachrichtenregel.chatregel);
      final eigene = senden(
          regel: Nachrichtenregel.frist,
          einzelFrist: const Duration(minutes: 5));
      final nachAnsehen = senden(regel: Nachrichtenregel.nachAnsehen);
      final einmal = senden(regel: Nachrichtenregel.einmalig);
      for (final id in [imChat, eigene, nachAnsehen, einmal]) {
        zustellen(id);
      }

      uhrVor(const Duration(minutes: 6));
      expect(liegtBei(ich, eigene), isFalse, reason: 'ihre fünf Minuten');
      expect(liegtBei(ich, imChat), isTrue, reason: 'die Stunde des Chats');
      expect(liegtBei(ich, nachAnsehen), isTrue, reason: 'keine Uhr');
      expect(liegtBei(ich, einmal), isTrue, reason: 'auch keine');

      lesen();
      verlassen();
      expect(liegtBei(ich, nachAnsehen), isFalse);
      expect(liegtBei(marco, nachAnsehen), isFalse);
      expect(liegtBei(ich, einmal), isTrue,
          reason: 'die einmalige geht mit dem Öffnen, nicht mit dem Lesen');

      uhrVor(const Duration(hours: 1));
      expect(liegtBei(ich, imChat), isFalse);
      expect(liegtBei(marco, imChat), isFalse);
      expect(liegtBei(ich, einmal), isTrue);

      expect(oeffnen(einmal), isNotNull);
      expect(bei(ich), isEmpty);
      expect(bei(marco), isEmpty,
          reason: 'am Ende liegt auf keinem der beiden Geräte noch etwas');
    });
  });
}
