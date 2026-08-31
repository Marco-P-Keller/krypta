import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/logic/remote_clear_policy.dart';

/// Was ein „Chat leeren" der Gegenseite auf meinem Gerät entfernen darf.
///
/// Wer seinen Chat leert, nimmt seine eigenen Nachrichten zurück — auf beiden
/// Geräten. Meine eigenen bleiben: sonst könnte mir jeder Kontakt jederzeit
/// meinen halben Verlauf löschen, ohne dass ich zustimme.
///
/// Dieselbe Regel gilt seit dem 31.08. auch, wenn die Gegenseite den ganzen
/// Chat **löscht** (Kontrollnachricht "chatGone"): auch dann nimmt sie nur
/// das Eigene zurück. Diese Datei trägt also zwei Wege, nicht mehr nur einen.
void main() {
  const marco = 'marco';
  const ich = 'ich';

  Message nachricht({
    required String von,
    SystemEventKind? ereignis,
  }) =>
      Message(
        id: 'm-$von-${ereignis?.name ?? 'text'}',
        chatId: 'c1',
        senderId: von,
        recipientId: von == ich ? marco : ich,
        encryptedContent: 'x',
        timestamp: DateTime(2026, 8, 25),
        systemEvent: ereignis,
      );

  test('was Marco geschrieben hat, verschwindet', () {
    expect(removedByPeerClear(nachricht(von: marco), marco), isTrue);
  });

  test('was ich geschrieben habe, bleibt', () {
    // Sonst loescht mir jeder Kontakt meinen halben Verlauf.
    expect(removedByPeerClear(nachricht(von: ich), marco), isFalse);
  });

  test('ein Screenshot-Hinweis bleibt, auch wenn Marco ihn ausgeloest hat', () {
    // Sonst waere der Hinweis wertlos: wer einen Screenshot macht, leert
    // danach den Chat und die Spur ist weg. Der Hinweis ist keine Nachricht,
    // sondern eine Feststellung ueber das Gespraech.
    final hinweis = nachricht(von: marco, ereignis: SystemEventKind.screenshot);

    expect(removedByPeerClear(hinweis, marco), isFalse);
  });

  test('auch ein Aufnahme-Hinweis bleibt', () {
    final hinweis =
        nachricht(von: marco, ereignis: SystemEventKind.screenRecording);

    expect(removedByPeerClear(hinweis, marco), isFalse);
  });

  test('ein fremder Absender aendert nichts', () {
    // Die Kontrollnachricht ist an den Absender gebunden; kaeme sie doch
    // einmal mit einer anderen Kennung an, darf sie nichts anfassen.
    expect(removedByPeerClear(nachricht(von: marco), 'jemand-anders'), isFalse);
  });
}
