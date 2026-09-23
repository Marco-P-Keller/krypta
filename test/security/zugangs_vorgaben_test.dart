import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/core/constants/storage_keys.dart';
import 'package:kryptaapp/services/storage/secure_storage_service.dart';

/// Was gilt, solange niemand gefragt wurde.
///
/// Zwei Schalter sind am 22.09.2026 dazugekommen — die Vorschau in der
/// Chatliste und der Taschenrechner — und beide betreffen Geraete, die
/// laengst laufen. Deren Schluesselbund kennt die neuen Schluessel nicht.
///
/// Beim Rechner ist das die gefaehrliche Richtung: waere die Vorgabe „aus",
/// haette das Update bei **jedem** bestehenden Geraet die Zugangssperre
/// abgeschaltet, ohne dass jemand danach gefragt haette. Deshalb liest die
/// Abfrage `!= 'false'` und nicht `== 'true'` — und deshalb steht das hier
/// als Test und nicht nur als Kommentar.
///
/// Dieselbe Falle hat das Projekt schon einmal getroffen, beim Push-Schalter:
/// siehe StorageKeys.pushPrivacyMode, wo der Wert bis heute verkehrt herum
/// gespeichert wird, weil ein neuer Schluessel allen Nutzern ihre Einstellung
/// verdreht haette.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SpeicherAttrappe speicher;
  late SecureStorageService storage;

  setUp(() {
    speicher = _SpeicherAttrappe();
    FlutterSecureStoragePlatform.instance = speicher;
    storage = SecureStorageService();
  });

  group('Der Taschenrechner', () {
    test('ein Geraet ohne den Schluessel behaelt ihn', () async {
      expect(await storage.isCalculatorLockEnabled(), isTrue);
    });

    test('nur ein ausdrueckliches Nein schaltet ihn ab', () async {
      await storage.setCalculatorLockEnabled(false);
      expect(speicher.werte[StorageKeys.calculatorLockEnabled], 'false');
      expect(await storage.isCalculatorLockEnabled(), isFalse);
    });

    test('und ein Ja laesst sich wieder setzen', () async {
      await storage.setCalculatorLockEnabled(false);
      await storage.setCalculatorLockEnabled(true);
      expect(await storage.isCalculatorLockEnabled(), isTrue);
    });

    test('etwas Unlesbares im Schluesselbund heisst nicht „aus"', () async {
      // Fail-safe in die richtige Richtung: was nicht „false" ist, laesst die
      // Sperre stehen.
      speicher.werte[StorageKeys.calculatorLockEnabled] = 'vielleicht';
      expect(await storage.isCalculatorLockEnabled(), isTrue);
    });
  });

  group('Die Codes', () {
    test('ohne Einrichtung gibt es keinen Geheimcode', () async {
      expect(await storage.hasSecretCode(), isFalse);
    });

    test('nach dem Einrichten schon', () async {
      await storage.saveSecretCode('4711');
      expect(await storage.hasSecretCode(), isTrue);
    });

    test('das Abschalten raeumt beide Codes weg', () async {
      // Ein Loeschcode ohne Rechner waere ein Geheimnis ohne Tuer, und ein
      // Geheimcode eine Zugangsmoeglichkeit, von der die Einstellungen
      // behaupten, es gebe sie nicht mehr.
      await storage.saveSecretCode('4711');
      await storage.saveDeleteCode('1234');
      await storage.deleteAccessCodes();

      expect(await storage.hasSecretCode(), isFalse);
      expect(await storage.verifySecretCode('4711'), isFalse);
      expect(await storage.verifyDeleteCode('1234'), isFalse);
    });
  });

  group('Die Vorschau in der Chatliste', () {
    test('ist vorgegeben an, wie bei WhatsApp', () async {
      expect(await storage.isChatPreviewEnabled(), isTrue);
    });

    test('und laesst sich abschalten', () async {
      await storage.setChatPreviewEnabled(false);
      expect(await storage.isChatPreviewEnabled(), isFalse);
    });
  });

  test('beide Schluessel stehen in der Liste zum Wegraeumen', () {
    // Sonst ueberlebt eine Einstellung die Notfall-Loeschung, wenn `readAll`
    // scheitert und die Rueckfallebene greift.
    expect(StorageKeys.all, contains(StorageKeys.calculatorLockEnabled));
    expect(StorageKeys.all, contains(StorageKeys.chatPreviewEnabled));
  });
}

/// Ein Schluesselbund im Arbeitsspeicher.
class _SpeicherAttrappe extends FlutterSecureStoragePlatform {
  final Map<String, String> werte = {};

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      werte.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async =>
      werte.remove(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      werte.clear();

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      werte[key];

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map<String, String>.from(werte);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async =>
      werte[key] = value;
}
