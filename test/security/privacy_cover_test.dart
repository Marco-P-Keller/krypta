import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/services/platform/platform_security_service.dart';
import 'package:kryptaapp/services/platform/privacy_cover.dart';

/// Die schwarze Abdeckung, die beim Verlassen der App über das Fenster geht.
///
/// Sie ist beim Zurückkehren das Einzige, was den Messenger verdeckt: die
/// Umschaltung auf den Taschenrechner passiert bei `paused`, und ab da
/// zeichnet Flutter nicht mehr. Die Ebene darunter hält also weiter das
/// letzte Bild von vor der Pause — den Messenger. Wer die Abdeckung nach
/// Zeit abnimmt statt nach einem fertigen Bild, zeigt genau den her.
///
/// Deshalb: erst wenn ein Bild wirklich steht.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const securityChannel = MethodChannel('krypta/security');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> aufrufe;
  late PrivacyCover abdeckung;

  setUp(() {
    aufrufe = [];
    messenger.setMockMethodCallHandler(securityChannel, (call) async {
      aufrufe.add(call.method);
      return true;
    });
    abdeckung = PrivacyCover(PlatformSecurityService());
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(securityChannel, null);
  });

  testWidgets('nimmt sie nicht ab, solange kein Bild gezeichnet wurde',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    aufrufe.clear();

    abdeckung.dismissWhenPainted();

    expect(aufrufe, isEmpty,
        reason: 'sofort abnehmen zeigt das alte Bild darunter her');
  });

  testWidgets('nimmt sie ab, sobald ein Bild auf dem Schirm steht',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    aufrufe.clear();

    abdeckung.dismissWhenPainted();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(aufrufe, contains('dismissPrivacyCover'));
  });

  testWidgets('erzwingt das nächste Bild selbst', (tester) async {
    // Ohne eigenes Zutun plant Flutter nach dem Aufwachen kein weiteres
    // Bild, wenn sich nichts geändert hat. Dann käme der zweite Rückruf nie
    // und die Abdeckung bliebe liegen — schwarze App, bis der Wachhund auf
    // der nativen Seite anschlägt.
    await tester.pumpWidget(const SizedBox());
    aufrufe.clear();

    abdeckung.dismissWhenPainted();
    await tester.pumpAndSettle();

    expect(aufrufe, contains('dismissPrivacyCover'));
  });

  testWidgets('blockierende Arbeit laeuft erst nach dem Abnehmen',
      (tester) async {
    // `recheck` tastet beim Aufwachen das Dateisystem synchron ab. Solange
    // das laeuft, entsteht kein Bild — davor aufgerufen haelt es die
    // Abdeckung fest, statt sie fallen zu lassen.
    await tester.pumpWidget(const SizedBox());
    aufrufe.clear();
    var danach = false;

    abdeckung.dismissWhenPainted(afterwards: () => danach = true);
    expect(danach, isFalse);

    await tester.pumpAndSettle();

    expect(danach, isTrue);
  });

  testWidgets('doppelter Aufruf nimmt sie trotzdem nur einmal ab',
      (tester) async {
    // `resumed` kann mehrfach kommen (Anruf-Banner, Kontrollzentrum).
    await tester.pumpWidget(const SizedBox());
    aufrufe.clear();

    abdeckung.dismissWhenPainted();
    abdeckung.dismissWhenPainted();
    await tester.pumpAndSettle();

    expect(aufrufe.where((a) => a == 'dismissPrivacyCover'), hasLength(1));
  });
}
