import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/data/models/chat_model.dart';

/// Was eine Nachricht ueberlebt, wenn die App geschlossen wird.
///
/// Bis Build 90 galt: Klartext wird **nie** auf die Platte geschrieben. Wer
/// die App verliess, fand danach in jedem Chat nur noch „••••••" — der
/// Verlauf war unlesbar, dauerhaft. Als Messenger ist das unbrauchbar.
///
/// Der Schutz liegt nicht darin, den Klartext wegzuwerfen, sondern darin, wo
/// er liegt: [EncryptedLocalStore] verschluesselt mit XChaCha20-Poly1305 unter
/// einem Schluessel aus dem Schluesselbund, nach Moeglichkeit in der Secure
/// Enclave verpackt und erst nach der ersten Entsperrung des Geraets lesbar.
/// Denselben Schluessel haelt die App ohnehin im Arbeitsspeicher — den
/// Klartext daneben wegzuwischen, waehrend der Schluessel danebenliegt,
/// schuetzt vor nichts.
///
/// Eine Ausnahme bleibt: passwortgeschuetzte Nachrichten. Ihr Klartext gehoert
/// hinter das Passwort, nicht auf die Platte.
void main() {
  Message nachricht({
    String? klartext = 'Hallo Marco',
    bool passwortgeschuetzt = false,
    bool entsperrt = false,
    SystemEventKind? ereignis,
  }) =>
      Message(
        id: 'm1',
        chatId: 'c1',
        senderId: 'ich',
        recipientId: 'du',
        encryptedContent: 'chiffre',
        decryptedContent: klartext,
        timestamp: DateTime(2026, 8, 25, 14, 30),
        status: MessageStatus.delivered,
        isPasswordProtected: passwortgeschuetzt,
        passwordUnlocked: entsperrt,
        systemEvent: ereignis,
      );

  Message durchLauf(Message m) => Message.fromMap(m.toMap());

  test('eine gewoehnliche Nachricht bleibt lesbar', () {
    expect(durchLauf(nachricht()).decryptedContent, 'Hallo Marco');
  });

  test('auch Umlaute und Zeilenumbrueche kommen heil an', () {
    final m = nachricht(klartext: 'Grüße\nüber\tzwei Zeilen — 😀');
    expect(durchLauf(m).decryptedContent, 'Grüße\nüber\tzwei Zeilen — 😀');
  });

  test('eine Nachricht ohne Klartext bleibt ohne', () {
    // Etwa eine, die nie entschluesselt werden konnte.
    expect(durchLauf(nachricht(klartext: null)).decryptedContent, isNull);
  });

  test('der Klartext einer passwortgeschuetzten Nachricht bleibt drausen', () {
    // Sonst waere das Passwort umsonst: wer die Datenbank liest, laese mit.
    final m = nachricht(klartext: 'geheim', passwortgeschuetzt: true, entsperrt: true);

    expect(durchLauf(m).decryptedContent, isNull);
    expect(durchLauf(m).isPasswordProtected, isTrue);
  });

  test('eine noch gesperrte bleibt aufsperrbar', () {
    // Solange sie gesperrt ist, steht in decryptedContent der mit dem
    // Passwort verschluesselte Block — der darf und muss bleiben, sonst
    // laesst sich die Nachricht nach einem Neustart nie wieder oeffnen.
    final m = nachricht(klartext: 'BLOCK-BASE64', passwortgeschuetzt: true);

    expect(durchLauf(m).decryptedContent, 'BLOCK-BASE64');
    expect(durchLauf(m).passwordUnlocked, isFalse);
  });

  test('ein Systemhinweis bringt keinen Text mit', () {
    // Sein Text entsteht beim Anzeigen aus der Uebersetzung und folgt damit
    // einem Sprachwechsel.
    final m = nachricht(klartext: null, ereignis: SystemEventKind.screenshot);
    final zurueck = durchLauf(m);

    expect(zurueck.isSystemEvent, isTrue);
    expect(zurueck.decryptedContent, isNull);
  });

  // ─── Einmalige Nachricht, ab 02.09.2026 ──────────────────────────────

  test('einmalig ueberlebt Speichern und Laden', () {
    final m = Message(
      id: 'e1',
      chatId: 'c1',
      senderId: 'marco',
      recipientId: 'ich',
      encryptedContent: 'x',
      timestamp: DateTime(2026, 9, 2, 12),
      einmalig: true,
    );
    expect(Message.fromMap(m.toMap()).einmalig, isTrue);
  });

  test('ein Bestandsdatensatz ohne das Feld ist gewoehnlich', () {
    // Nachrichten, die vor dieser Aenderung geschrieben wurden, kennen das
    // Feld nicht. Sie duerfen nicht ploetzlich als einmalig gelten und sich
    // beim ersten Oeffnen selbst entfernen.
    final m = Message(
      id: 'e2',
      chatId: 'c1',
      senderId: 'marco',
      recipientId: 'ich',
      encryptedContent: 'x',
      timestamp: DateTime(2026, 9, 2, 12),
    );
    final karte = Map<String, dynamic>.from(m.toMap())..remove('einmalig');
    expect(Message.fromMap(karte).einmalig, isFalse);
  });

  group('Die Loeschregel eines Chats ueberlebt den Rundlauf', () {
    Chat chat({Duration? frist, bool nachLesen = false, int version = 0}) =>
        Chat(
          id: 'c1',
          recipientId: 'marco',
          recipientName: 'Marco',
          defaultSelfDestruct: frist,
          loeschtNachLesen: nachLesen,
          regelVersion: version,
        );

    test('eine Frist mit ihrem Zaehler', () {
      final wieder = Chat.fromMap(
          chat(frist: const Duration(minutes: 5), version: 4).toMap());
      expect(wieder.defaultSelfDestruct, const Duration(minutes: 5));
      expect(wieder.regelVersion, 4);
      expect(wieder.loeschtNachLesen, isFalse);
    });

    test('„Direkt nach dem Lesen"', () {
      final wieder = Chat.fromMap(chat(nachLesen: true, version: 2).toMap());
      expect(wieder.loeschtNachLesen, isTrue);
      expect(wieder.defaultSelfDestruct, isNull);
      expect(wieder.regelVersion, 2);
    });

    test('ein Bestandsdatensatz kennt beide Felder nicht', () {
      // Ohne den Vorgabewert stuende ein alter Chat nach dem Update auf
      // „nach dem Lesen" und raeumte beim ersten Verlassen den Verlauf.
      final alt = chat(frist: const Duration(minutes: 5)).toMap()
        ..remove('sdNachLesen')
        ..remove('sdVersion');
      final wieder = Chat.fromMap(alt);
      expect(wieder.loeschtNachLesen, isFalse);
      expect(wieder.regelVersion, 0);
      expect(wieder.regelMachtVergaenglich, isTrue,
          reason: 'die Frist macht ihn weiterhin vergaenglich');
    });
  });
}
