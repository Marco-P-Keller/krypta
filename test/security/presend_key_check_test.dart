import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/logic/messenger_provider.dart';

/// Die Vorab-Prüfung des Empfängerschlüssels vor dem Senden.
///
/// Sie fängt einen Schlüsselwechsel ab, der zwischen zwei Posteingängen
/// passiert ist. Übersprungen werden darf sie nur dort, wo der Aufrufer
/// denselben Schlüssel gerade selbst geholt hat und der Kontakt aus genau
/// dieser Antwort gebaut wurde — dann kann das Nachfragen nichts liefern,
/// was die erste Antwort nicht schon enthielt.
///
/// Die Bedingung ist mit Absicht die Gleichheit der Bytes und nicht ein
/// Zeitfenster: wer sich irrt, fragt nach. Ein stiller Verzicht auf die
/// Prüfung ist so nicht möglich.
void main() {
  group('needsServerKeyCheck', () {
    const schluessel = 'AAAAb3BlbnNzaC1rZXk=';

    test('ohne vorab geholten Schlüssel wird gefragt', () {
      expect(
        MessengerProvider.needsServerKeyCheck(
          preverified: null,
          contactKey: schluessel,
        ),
        isTrue,
      );
    });

    test('bei abweichendem Schlüssel wird gefragt', () {
      expect(
        MessengerProvider.needsServerKeyCheck(
          preverified: 'BBBBb3BlbnNzaC1rZXk=',
          contactKey: schluessel,
        ),
        isTrue,
        reason: 'Abweichung ist genau der Fall, den die Prüfung sucht',
      );
    });

    test('bei identischen Bytes wird nicht noch einmal gefragt', () {
      expect(
        MessengerProvider.needsServerKeyCheck(
          preverified: schluessel,
          contactKey: schluessel,
        ),
        isFalse,
      );
    });

    test('leerer Schlüssel zählt nicht als Übereinstimmung', () {
      // Ein leerer Wert entstünde aus einer fehlgeschlagenen Kodierung.
      // Er darf die Prüfung nicht abschalten.
      expect(
        MessengerProvider.needsServerKeyCheck(
          preverified: '',
          contactKey: schluessel,
        ),
        isTrue,
      );
      expect(
        MessengerProvider.needsServerKeyCheck(
          preverified: '',
          contactKey: '',
        ),
        isTrue,
      );
    });
  });
}
