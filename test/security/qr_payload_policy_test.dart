import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/logic/qr_payload_policy.dart';

/// Was der Scanner ablehnen muss, bevor er den Server befragt.
void main() {
  test('leere und uebergrosse Rohdaten werden abgelehnt', () {
    expect(QrPayloadPolicy.rohdatenPassen(''), isFalse);
    expect(QrPayloadPolicy.rohdatenPassen('x' * 300), isTrue);
    expect(QrPayloadPolicy.rohdatenPassen('x' * 2048), isTrue);
    expect(QrPayloadPolicy.rohdatenPassen('x' * 2049), isFalse);
  });

  test('nur genau 32 Byte gelten als Schluessel', () {
    expect(QrPayloadPolicy.schluesselPasst(32), isTrue);
    expect(QrPayloadPolicy.schluesselPasst(31), isFalse);
    expect(QrPayloadPolicy.schluesselPasst(33), isFalse);
    expect(QrPayloadPolicy.schluesselPasst(0), isFalse);
    // Der Fall, der vorher durchkam: nicht leer, aber auch kein Schluessel.
    expect(QrPayloadPolicy.schluesselPasst(1), isFalse);
  });

  test('Felder haben eine Obergrenze', () {
    expect(QrPayloadPolicy.feldPasst(''), isFalse);
    expect(QrPayloadPolicy.feldPasst('a' * 256), isTrue);
    expect(QrPayloadPolicy.feldPasst('a' * 257), isFalse);
  });

  group('Nutzerkennung', () {
    test('gueltige Kennungen', () {
      expect(QrPayloadPolicy.userIdPasst('abc123XYZ789'), isTrue);
      expect(QrPayloadPolicy.userIdPasst('a' * 128), isTrue);
    });

    test('zu kurz, zu lang, falsche Zeichen', () {
      expect(QrPayloadPolicy.userIdPasst('abc'), isFalse);
      expect(QrPayloadPolicy.userIdPasst('a' * 129), isFalse);
      expect(QrPayloadPolicy.userIdPasst('abc123/../etc'), isFalse,
          reason: 'Pfadwechsel darf nie an den Server gehen');
      expect(QrPayloadPolicy.userIdPasst('abc 123 456'), isFalse);
      expect(QrPayloadPolicy.userIdPasst('abc-123-456'), isFalse);
    });
  });
}
