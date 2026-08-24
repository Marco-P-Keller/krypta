import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/services/platform/platform_security_service.dart';

/// Der Gerätefund an Build 85 (iPhone, iOS 26.6): Screenshots im entsperrten
/// Messenger zeigten den echten Inhalt, während in den Einstellungen der
/// Schalter „Screenshot-Schutz" auf **an** stand.
///
/// Zwei getrennte Fehler steckten dahinter:
///
/// 1. Nativ schlägt die Installation der Maske auf iOS 26 fehl. Das ist
///    fail-closed und insofern korrekt — es schützt nur nichts mehr.
/// 2. Dart hielt den Zustand als Kopie vom letzten `enable`-Aufruf. Der
///    native Watchdog kann die Maske danach abbauen, ohne dass Dart davon je
///    erfährt; der Einstellungs-Schalter zeigte den Wert obendrein gar nicht
///    an, sondern ein fest verdrahtetes `true`.
///
/// Fehler 2 ist der gefährlichere: eine App, die einen Schutz behauptet, den
/// sie nicht hat, ist schlechter als eine, die ehrlich sagt, dass sie ihn
/// nicht hat. Diese Tests decken ihn ab.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const securityChannel = MethodChannel('krypta/security');
  const captureChannel = MethodChannel('krypta/capture_events');

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late PlatformSecurityService service;

  /// Antworten, die der native Teil geben soll. Pro Methodenname eine
  /// Funktion, damit ein Test die Antwort mitten im Ablauf ändern kann —
  /// genau das simuliert den Watchdog, der die Maske später abbaut.
  late Map<String, dynamic Function(MethodCall)> handlers;

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
    // Der EventChannel meldet sich über seinen eigenen MethodChannel an.
    messenger.setMockMethodCallHandler(captureChannel, (call) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(securityChannel, null);
    messenger.setMockMethodCallHandler(captureChannel, null);
  });

  /// Ein Ereignis auf dem Aufnahme-EventChannel einspeisen.
  Future<void> emitCapture(bool captured) async {
    const codec = StandardMethodCodec();
    await messenger.handlePlatformMessage(
      captureChannel.name,
      codec.encodeSuccessEnvelope(captured),
      (_) {},
    );
  }

  group('enableScreenshotProtection', () {
    test('meldet den geprüften Zustand der nativen Seite, nicht den Wunsch',
        () async {
      handlers['enableSecureFlag'] = (_) => true;
      expect(await service.enableScreenshotProtection(), isTrue);
      expect(service.isScreenshotProtectionActive, isTrue);
    });

    test('nativ fehlgeschlagen heißt aus — nicht optimistisch an', () async {
      // Genau der iOS-26.6-Fall: die Maske lässt sich nicht installieren.
      handlers['enableSecureFlag'] = (_) => false;
      expect(await service.enableScreenshotProtection(), isFalse);
      expect(service.isScreenshotProtectionActive, isFalse);
    });

    test('reicht den lokalisierten Hinweis für die Aufnahme-Abdeckung durch',
        () async {
      // Die Abdeckung wird nativ gezeichnet, der Text muss aber in den
      // .arb-Dateien bleiben — sonst entsteht eine zweite Textquelle, die
      // niemand nachpflegt.
      handlers['enableSecureFlag'] = (_) => true;
      await service.enableScreenshotProtection(
        captureNotice: 'Bildschirmaufnahme erkannt',
      );
      final call = calls.firstWhere((c) => c.method == 'enableSecureFlag');
      expect(
        (call.arguments as Map)['captureNotice'],
        'Bildschirmaufnahme erkannt',
      );
    });
  });

  group('refreshScreenshotProtectionState', () {
    test('korrigiert eine veraltete Kopie, wenn die Maske abgebaut wurde',
        () async {
      // Das ist der Kern des Fehlers aus Build 85: erst klappt es, dann baut
      // der Watchdog die Maske ab, und Dart glaubt weiter an den alten Wert.
      handlers['enableSecureFlag'] = (_) => true;
      await service.enableScreenshotProtection();
      expect(service.isScreenshotProtectionActive, isTrue);

      handlers['isScreenshotProtectionActive'] = (_) => false;
      expect(await service.refreshScreenshotProtectionState(), isFalse);
      expect(service.isScreenshotProtectionActive, isFalse);
    });

    test('bestätigt einen weiterhin aktiven Schutz', () async {
      handlers['isScreenshotProtectionActive'] = (_) => true;
      expect(await service.refreshScreenshotProtectionState(), isTrue);
      expect(service.isScreenshotProtectionActive, isTrue);
    });

    test('ohne native Antwort gilt: kein Schutz', () async {
      // handlers ist leer -> MissingPluginException. Lieber ehrlich „aus"
      // als eine Zusage, die niemand geprüft hat.
      expect(await service.refreshScreenshotProtectionState(), isFalse);
      expect(service.isScreenshotProtectionActive, isFalse);
    });
  });

  group('Bildschirmaufnahme und Spiegelung', () {
    test('isScreenCaptured gibt den nativen Zustand weiter', () async {
      handlers['isScreenCaptured'] = (_) => true;
      expect(await service.isScreenCaptured(), isTrue);

      handlers['isScreenCaptured'] = (_) => false;
      expect(await service.isScreenCaptured(), isFalse);
    });

    test('ohne native Antwort wird keine Aufnahme behauptet', () async {
      // Hier ist die sichere Richtung die andere herum: eine erfundene
      // Aufnahme würde die App grundlos schwarz schalten.
      expect(await service.isScreenCaptured(), isFalse);
    });

    test('der Strom meldet Beginn und Ende einer Aufnahme', () async {
      final seen = <bool>[];
      final sub = service.onScreenCaptureChanged.listen(seen.add);
      addTearDown(sub.cancel);

      await emitCapture(true);
      await emitCapture(false);
      await Future<void>.delayed(Duration.zero);

      expect(seen, [true, false]);
    });
  });

  group('Diagnose', () {
    test('reicht den nativen Bericht unverändert durch', () async {
      handlers['diagnoseScreenshotMask'] = (_) => <Object?, Object?>{
            'iosVersion': '26.6',
            'sublayerCount': 2,
            'candidates': <Object?>[
              <Object?, Object?>{'index': 0, 'verifies': false},
            ],
          };
      final report = await service.diagnoseScreenshotMask();
      expect(report['iosVersion'], '26.6');
      expect(report['sublayerCount'], 2);
      expect((report['candidates'] as List), hasLength(1));
    });

    test('ohne native Antwort kommt ein leerer Bericht, kein Absturz',
        () async {
      expect(await service.diagnoseScreenshotMask(), isEmpty);
    });

    test('forceSecureMaskCandidate reicht den Index durch', () async {
      handlers['forceSecureMaskCandidate'] = (call) =>
          (call.arguments as Map)['index'] == 1;
      expect(await service.forceSecureMaskCandidate(1), isTrue);
      expect(await service.forceSecureMaskCandidate(0), isFalse);
    });
  });
}
