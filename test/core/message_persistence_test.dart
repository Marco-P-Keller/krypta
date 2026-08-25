import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';

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
}
