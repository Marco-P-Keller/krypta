import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/logic/chatliste_policy.dart';

/// Was in der Chatliste unter dem Namen steht.
///
/// Der Anlass ist Daniels Liste vom 22.09.2026: „Die Vorschau bzw. Anzeige
/// der Nachrichten in der Chatliste soll vom Prinzip her wie bei WhatsApp
/// funktionieren."
///
/// Am 30.08.2026 war die Vorschau ausgebaut worden, und der Grund dafuer gilt
/// weiter: der Klartext lag damals **zweimal** verschluesselt auf der Platte,
/// im Nachrichtenspeicher und noch einmal als `lastMessagePreview` in
/// `chats.enc`. Deshalb steht sie jetzt nirgends gespeichert, sondern wird
/// bei jedem Aufbau aus dem Verlauf im Speicher abgeleitet — das ist, was
/// diese Datei prueft.
///
/// Und zwei Nachrichtenarten zeigen ihren Inhalt **nie**: die einmalige und
/// die passwortgeschuetzte. Sonst stuende in der Liste, was im Chat erst nach
/// einer Bestaetigung oder einem Passwort zu sehen ist.
void main() {
  final t0 = DateTime(2026, 9, 22, 14, 0);

  Message nachricht({
    String id = 'm1',
    String von = 'marco',
    String? text = 'Kommst du?',
    int minute = 0,
    bool einmalig = false,
    bool passwort = false,
    bool aufgeschlossen = false,
    SystemEventKind? hinweis,
  }) =>
      Message(
        id: id,
        chatId: 'c1',
        senderId: von,
        recipientId: von == 'ich' ? 'marco' : 'ich',
        encryptedContent: '',
        decryptedContent: text,
        timestamp: t0.add(Duration(minutes: minute)),
        einmalig: einmalig,
        isPasswordProtected: passwort,
        passwordUnlocked: aufgeschlossen,
        systemEvent: hinweis,
      );

  Vorschau vorschau(List<Message> messages, {bool zeigen = true}) =>
      VorschauPolicy.fuer(messages, eigeneId: 'ich', zeigen: zeigen);

  group('Der Schalter', () {
    test('steht er aus, gibt es keine Vorschau', () {
      final v = vorschau([nachricht()], zeigen: false);
      expect(v.art, VorschauArt.keine);
      expect(v.text, isNull);
    });

    test('steht er an, steht dort die letzte Nachricht', () {
      final v = vorschau([nachricht()]);
      expect(v.art, VorschauArt.text);
      expect(v.text, 'Kommst du?');
    });
  });

  group('Welche Nachricht gilt', () {
    test('die neueste, nicht die zuletzt angehaengte', () {
      // Die Liste im Provider ist nach Zustellung sortiert, nicht garantiert
      // nach Uhrzeit: eine nachgereichte Nachricht kann hinten stehen und
      // trotzdem aelter sein.
      final v = vorschau([
        nachricht(id: 'neu', text: 'zuletzt', minute: 5),
        nachricht(id: 'alt', text: 'zuerst', minute: 1),
      ]);
      expect(v.text, 'zuletzt');
    });

    test('ein leerer Chat zeigt nichts', () {
      expect(vorschau([]).art, VorschauArt.keine);
    });

    test('ohne Klartext steht dort nichts statt einer leeren Zeile', () {
      // Nach dem Verlassen des Chats raeumt der Provider den Klartext aus dem
      // Speicher. Dann ist die richtige Antwort „nichts", nicht „".
      expect(vorschau([nachricht(text: null)]).art, VorschauArt.keine);
      expect(vorschau([nachricht(text: '   ')]).art, VorschauArt.keine);
    });
  });

  group('Was nie im Klartext dasteht', () {
    test('die einmalige Nachricht', () {
      final v = vorschau([nachricht(text: 'Kontonummer', einmalig: true)]);
      expect(v.art, VorschauArt.einmalig);
      expect(v.text, isNull,
          reason: 'sie ist einmal zu oeffnen, nicht einmal zu lesen und '
              'einmal in der Liste');
    });

    test('auch die eigene einmalige Nachricht', () {
      final v = vorschau(
          [nachricht(von: 'ich', text: 'Kontonummer', einmalig: true)]);
      expect(v.art, VorschauArt.einmalig);
      expect(v.text, isNull);
    });

    test('die passwortgeschuetzte, solange sie zu ist', () {
      final v = vorschau([nachricht(text: 'blob', passwort: true)]);
      expect(v.art, VorschauArt.passwort);
      expect(v.text, isNull);
    });

    test('ist sie aufgeschlossen, ist sie eine gewoehnliche Nachricht', () {
      // Der Empfaenger hat das Passwort eingegeben; der Text steht im Chat
      // offen da. Ihn in der Liste zu verstecken waere Kosmetik.
      final v = vorschau(
          [nachricht(text: 'offen', passwort: true, aufgeschlossen: true)]);
      expect(v.art, VorschauArt.text);
      expect(v.text, 'offen');
    });
  });

  group('Hinweise', () {
    test('ein Screenshot steht als Art da, nicht als Satz', () {
      // Der ganze Satz aus dem Verlauf („Marco hat einen Screenshot vom Chat
      // gemacht") wuerde in der Kachel abgeschnitten. Die Oberflaeche bildet
      // aus der Art eine kurze, uebersetzte Zeile.
      final v = vorschau([nachricht(text: null, hinweis: SystemEventKind.screenshot)]);
      expect(v.art, VorschauArt.hinweis);
      expect(v.ereignis, SystemEventKind.screenshot);
    });
  });

  group('Von wem', () {
    test('meine eigene Nachricht bekommt die Markierung', () {
      expect(vorschau([nachricht(von: 'ich')]).vonMir, isTrue);
    });

    test('die der Gegenseite nicht', () {
      expect(vorschau([nachricht(von: 'marco')]).vonMir, isFalse);
    });

    test('ohne angemeldete Kennung gilt nichts als meins', () {
      final v = VorschauPolicy.fuer([nachricht(von: 'ich')],
          eigeneId: null, zeigen: true);
      expect(v.vonMir, isFalse);
    });
  });

  group('Kuerzen', () {
    test('Zeilenumbrueche werden zu Leerzeichen', () {
      // Sonst waere die Kachel hoeher als ihre Nachbarn, oder alles nach der
      // ersten Zeile verschwaende.
      expect(VorschauPolicy.kuerzen('zwei\nZeilen'), 'zwei Zeilen');
    });

    test('lange Nachrichten wandern nicht in voller Laenge durch die Liste',
        () {
      final lang = 'a' * 5000;
      expect(VorschauPolicy.kuerzen(lang).length,
          VorschauPolicy.maxZeichen);
    });

    test('kurze bleiben unangetastet', () {
      expect(VorschauPolicy.kuerzen('kurz'), 'kurz');
    });
  });
}
