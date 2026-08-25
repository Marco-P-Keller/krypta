import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';

/// Systemeinträge im Chatverlauf: „Du hast einen Screenshot gemacht",
/// „*Name* nimmt den Bildschirm auf".
///
/// Der Screenshot-Schutz wurde entfernt — er beruhte auf undokumentiertem
/// Verhalten und wirkte auf iOS 26.6 nicht mehr. Statt einen Schutz zu
/// behaupten, den es nicht gibt, sagt die App jetzt Bescheid. Das ist auch
/// der Weg, den Snapchat und Signal gehen.
///
/// Der Eintrag trägt **keinen Text**, nur die Art des Ereignisses:
/// `decryptedContent` wird bewusst nie auf die Platte geschrieben, und ein
/// gespeicherter deutscher Satz würde nach einem Sprachwechsel deutsch
/// bleiben. So entsteht der Text erst beim Anzeigen.
void main() {
  Message bauen({
    SystemEventKind? ereignis,
    String senderId = 'ich',
  }) {
    return Message(
      id: 'm1',
      chatId: 'c1',
      senderId: senderId,
      recipientId: 'du',
      encryptedContent: '',
      timestamp: DateTime(2026, 8, 25, 13, 14),
      systemEvent: ereignis,
    );
  }

  group('Erkennung', () {
    test('eine gewöhnliche Nachricht ist kein Systemeintrag', () {
      expect(bauen().isSystemEvent, isFalse);
      expect(bauen().systemEvent, isNull);
    });

    test('ein Screenshot-Eintrag ist einer', () {
      final m = bauen(ereignis: SystemEventKind.screenshot);
      expect(m.isSystemEvent, isTrue);
      expect(m.systemEvent, SystemEventKind.screenshot);
    });

    test('eine Bildschirmaufnahme ebenfalls', () {
      expect(bauen(ereignis: SystemEventKind.screenRecording).isSystemEvent,
          isTrue);
    });
  });

  group('Speichern und Laden', () {
    test('die Art des Ereignisses übersteht beides', () {
      for (final k in SystemEventKind.values) {
        final wieder = Message.fromMap(bauen(ereignis: k).toMap());
        expect(wieder.systemEvent, k, reason: '$k');
      }
    });

    test('ein Eintrag ohne Ereignis bleibt eine gewöhnliche Nachricht', () {
      expect(Message.fromMap(bauen().toMap()).isSystemEvent, isFalse);
    });

    test('eine gespeicherte Nachricht ohne das neue Feld laedt sauber', () {
      // Migration: alles, was vor dieser Änderung auf der Platte lag.
      final alt = bauen().toMap()..remove('sysEvent');
      expect(Message.fromMap(alt).isSystemEvent, isFalse);
    });
  });

  group('Verhalten im Verlauf', () {
    test('ein Systemeintrag verfällt nicht von selbst', () {
      // Er trägt keine Selbstzerstörung — sonst verschwände der Hinweis
      // genau dann, wenn man ihn braucht.
      final m = bauen(ereignis: SystemEventKind.screenshot);
      expect(m.selfDestructDuration, isNull);
      expect(m.isExpired, isFalse);
      expect(m.burnAfterRead, isFalse);
    });

    test('er ist nie passwortgeschützt oder gesperrt', () {
      final m = bauen(ereignis: SystemEventKind.screenshot);
      expect(m.isPasswordProtected, isFalse);
      expect(m.isLocked, isFalse);
    });

    test('wer es ausgeloest hat, steht im Absender', () {
      // Daraus entscheidet die Anzeige zwischen „Du hast…" und „Name hat…".
      expect(bauen(ereignis: SystemEventKind.screenshot, senderId: 'ich')
          .senderId, 'ich');
      expect(bauen(ereignis: SystemEventKind.screenshot, senderId: 'du')
          .senderId, 'du');
    });
  });
}
