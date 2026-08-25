import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/services/platform/platform_security_service.dart';

/// Die Erkennung von Screenshots und Bildschirmaufnahmen.
///
/// Geschützt wird nichts mehr. Der frühere Versuch, den Inhalt zu schwärzen,
/// beruhte auf undokumentiertem Verhalten von `isSecureTextEntry` und wirkte
/// ab iOS 26 nicht mehr — die App behauptete einen Schutz, den sie nicht
/// hatte, und der Schalter in den Einstellungen zeigte trotzdem „an".
///
/// Verhindern lässt sich ein Screenshot auf iOS ohnehin nicht: das System
/// meldet ihn erst danach. Ehrlich ist deshalb, beiden Seiten Bescheid zu
/// sagen — so machen es Snapchat und Signal auch.
///
/// Diese Tests decken die Plattformbrücke ab: was ein- und ausgeschaltet wird
/// und was aus den Ereignisströmen herauskommt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const securityChannel = MethodChannel('krypta/security');
  const screenshotChannel = MethodChannel('krypta/screenshot_events');
  const captureChannel = MethodChannel('krypta/capture_events');

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late Map<String, dynamic Function(MethodCall)> handlers;
  late PlatformSecurityService service;

  setUp(() {
    calls = [];
    handlers = {};
    service = PlatformSecurityService();
    messenger.setMockMethodCallHandler(securityChannel, (call) async {
      calls.add(call);
      final handler = handlers[call.method];
      if (handler == null) {
        throw MissingPluginException('kein Handler für ${call.method}');
      }
      return handler(call);
    });
    for (final c in [screenshotChannel, captureChannel]) {
      messenger.setMockMethodCallHandler(c, (call) async => null);
    }
  });

  tearDown(() {
    for (final c in [securityChannel, screenshotChannel, captureChannel]) {
      messenger.setMockMethodCallHandler(c, null);
    }
  });

  Future<void> sende(MethodChannel channel, bool wert) async {
    const codec = StandardMethodCodec();
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeSuccessEnvelope(wert),
      (_) {},
    );
  }

  group('Erkennung ein- und ausschalten', () {
    test('einschalten meldet, ob die Plattform mitspielt', () async {
      handlers['enableSecureFlag'] = (_) => true;
      expect(await service.enableScreenshotProtection(), isTrue);
      expect(service.isScreenshotProtectionActive, isTrue);
    });

    test('ohne native Antwort gilt: nicht aktiv', () async {
      // handlers ist leer -> MissingPluginException. Lieber ehrlich „aus"
      // als eine Zusage, die niemand geprüft hat.
      expect(await service.enableScreenshotProtection(), isFalse);
      expect(service.isScreenshotProtectionActive, isFalse);
    });

    test('einschalten reicht keine Argumente mehr durch', () async {
      // Der Hinweistext für die frühere Abdeckung ist entfallen — es gibt
      // keine Abdeckung mehr.
      handlers['enableSecureFlag'] = (_) => true;
      await service.enableScreenshotProtection();
      final call = calls.firstWhere((c) => c.method == 'enableSecureFlag');
      expect(call.arguments, isNull);
    });

    test('ausschalten setzt den Zustand zurück', () async {
      handlers['enableSecureFlag'] = (_) => true;
      handlers['disableSecureFlag'] = (_) => true;
      await service.enableScreenshotProtection();

      await service.disableScreenshotProtection();

      expect(service.isScreenshotProtectionActive, isFalse);
      expect(calls.map((c) => c.method), contains('disableSecureFlag'));
    });
  });

  group('Screenshot-Ereignisse', () {
    test('der Strom meldet jeden Screenshot', () async {
      handlers['enableSecureFlag'] = (_) => true;
      await service.enableScreenshotProtection();
      final gesehen = <bool>[];
      final sub = service.onScreenshotDetected.listen(gesehen.add);
      addTearDown(sub.cancel);

      await sende(screenshotChannel, false);
      await sende(screenshotChannel, false);
      await Future<void>.delayed(Duration.zero);

      // Zwei Ereignisse. Der Wert ist immer false — blockiert wurde nichts,
      // das ist der Punkt. Das Ereignis selbst ist die Nachricht.
      expect(gesehen, hasLength(2));
      expect(gesehen.every((b) => b == false), isTrue);
    });
  });

  group('Aufnahme-Sitzungen', () {
    // Der Chat-Bildschirm wird beim Wechseln neu gebaut und horcht dann neu.
    // Der Zustandsstrom meldet daraufhin die laufende Aufnahme erneut — ohne
    // eine Kennung der Sitzung wuerde die Gegenseite fuer EINE Aufnahme
    // mehrfach „Aufnahme gestartet" angezeigt bekommen. Deshalb beobachtet
    // der Dienst durchgehend und vergibt je Aufnahme eine Nummer.
    setUp(() async {
      handlers['enableSecureFlag'] = (_) => true;
      await service.enableScreenshotProtection();
    });

    test('ohne Aufnahme gibt es keine Sitzung', () {
      expect(service.captureSession, 0);
    });

    test('dieselbe Aufnahme behaelt ihre Nummer', () async {
      await sende(captureChannel, true);
      final erste = service.captureSession;
      expect(erste, isNonZero);

      // Wieder derselbe Zustand — etwa weil ein neuer Horcher dazukommt.
      await sende(captureChannel, true);

      expect(service.captureSession, erste);
    });

    test('eine neue Aufnahme bekommt eine neue Nummer', () async {
      await sende(captureChannel, true);
      final erste = service.captureSession;

      await sende(captureChannel, false);
      expect(service.captureSession, 0);

      await sende(captureChannel, true);

      expect(service.captureSession, isNot(erste));
      expect(service.captureSession, isNonZero);
    });

    test('onScreenRecordingStarted meldet nur den Beginn', () async {
      final gemeldet = <int>[];
      final sub = service.onScreenRecordingStarted.listen(gemeldet.add);
      addTearDown(sub.cancel);

      await sende(captureChannel, true);
      await sende(captureChannel, true);
      await sende(captureChannel, false);
      await sende(captureChannel, true);
      await Future<void>.delayed(Duration.zero);

      expect(gemeldet, hasLength(2));
      expect(gemeldet.first, isNot(gemeldet.last));
    });

    test('ausschalten beendet die Beobachtung', () async {
      handlers['disableSecureFlag'] = (_) => true;
      await sende(captureChannel, true);
      expect(service.captureSession, isNonZero);

      await service.disableScreenshotProtection();

      expect(service.captureSession, 0);
    });

    test('nach dem Ausschalten wird nichts mehr gemeldet', () async {
      // „Aus" ist eine Zusage an den Nutzer: niemand erfaehrt etwas, auch
      // die Gegenseite nicht. Ein Ereignis, das nach dem Abschalten noch
      // hereinkommt, darf sie nicht brechen.
      handlers['disableSecureFlag'] = (_) => true;
      final gemeldet = <int>[];
      final sub = service.onScreenRecordingStarted.listen(gemeldet.add);
      addTearDown(sub.cancel);

      await service.disableScreenshotProtection();
      await sende(captureChannel, true);
      await Future<void>.delayed(Duration.zero);

      expect(gemeldet, isEmpty);
      expect(service.captureSession, 0);
    });
  });

  group('Screenshot-Erkennung folgt dem Schalter', () {
    test('ausgeschaltet erreicht kein Screenshot mehr die App', () async {
      // Der native Ereigniskanal wird geoeffnet, sobald ein Chat zuhoert —
      // unabhaengig davon, ob der Hinweis eingeschaltet ist. Ohne diese
      // Sperre wuerde die Gegenseite eine Meldung bekommen, obwohl der
      // Nutzer den Hinweis abgeschaltet hat.
      final gesehen = <bool>[];
      final sub = service.onScreenshotDetected.listen(gesehen.add);
      addTearDown(sub.cancel);

      await sende(screenshotChannel, false);
      await Future<void>.delayed(Duration.zero);
      expect(gesehen, isEmpty, reason: 'nie eingeschaltet');

      handlers['enableSecureFlag'] = (_) => true;
      await service.enableScreenshotProtection();
      await sende(screenshotChannel, false);
      await Future<void>.delayed(Duration.zero);
      expect(gesehen, hasLength(1));

      handlers['disableSecureFlag'] = (_) => true;
      await service.disableScreenshotProtection();
      await sende(screenshotChannel, false);
      await Future<void>.delayed(Duration.zero);
      expect(gesehen, hasLength(1), reason: 'nach dem Ausschalten nichts mehr');
    });
  });

  group('Bildschirmaufnahme', () {
    test('isScreenCaptured gibt den nativen Zustand weiter', () async {
      handlers['isScreenCaptured'] = (_) => true;
      expect(await service.isScreenCaptured(), isTrue);

      handlers['isScreenCaptured'] = (_) => false;
      expect(await service.isScreenCaptured(), isFalse);
    });

    test('ohne native Antwort wird keine Aufnahme behauptet', () async {
      // Eine erfundene Aufnahme würde der Gegenseite eine Meldung schicken,
      // die nie passiert ist.
      expect(await service.isScreenCaptured(), isFalse);
    });

    test('der Strom meldet Beginn und Ende', () async {
      final gesehen = <bool>[];
      final sub = service.onScreenCaptureChanged.listen(gesehen.add);
      addTearDown(sub.cancel);

      await sende(captureChannel, true);
      await sende(captureChannel, false);
      await Future<void>.delayed(Duration.zero);

      expect(gesehen, [true, false]);
    });
  });
}
