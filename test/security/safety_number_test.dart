import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/verification/safety_number.dart';

void main() {
  group('SafetyNumber', () {
    test('generates 60-digit string', () async {
      final pubA = Uint8List.fromList(List.generate(32, (i) => i));
      final pubB = Uint8List.fromList(List.generate(32, (i) => 255 - i));

      final sn = await SafetyNumber.generate(
        localUserId: 'userA',
        localIdentityPublic: pubA,
        remoteUserId: 'userB',
        remoteIdentityPublic: pubB,
      );

      expect(sn.length, 60);
      expect(RegExp(r'^\d{60}$').hasMatch(sn), true);
    });

    test('is symmetric — both sides generate the same number', () async {
      final pubA = Uint8List.fromList(List.generate(32, (i) => i));
      final pubB = Uint8List.fromList(List.generate(32, (i) => 255 - i));

      final snFromA = await SafetyNumber.generate(
        localUserId: 'userA',
        localIdentityPublic: pubA,
        remoteUserId: 'userB',
        remoteIdentityPublic: pubB,
      );

      final snFromB = await SafetyNumber.generate(
        localUserId: 'userB',
        localIdentityPublic: pubB,
        remoteUserId: 'userA',
        remoteIdentityPublic: pubA,
      );

      expect(snFromA, snFromB);
    });

    test('different keys produce different numbers', () async {
      final pubA = Uint8List.fromList(List.generate(32, (i) => i));
      final pubB = Uint8List.fromList(List.generate(32, (i) => 255 - i));
      final pubC = Uint8List.fromList(List.generate(32, (i) => i + 50));

      final sn1 = await SafetyNumber.generate(
        localUserId: 'userA',
        localIdentityPublic: pubA,
        remoteUserId: 'userB',
        remoteIdentityPublic: pubB,
      );

      final sn2 = await SafetyNumber.generate(
        localUserId: 'userA',
        localIdentityPublic: pubA,
        remoteUserId: 'userC',
        remoteIdentityPublic: pubC,
      );

      expect(sn1, isNot(equals(sn2)));
    });

    test('formatForDisplay adds spaces every 5 digits', () {
      final formatted = SafetyNumber.formatForDisplay('123456789012345678901234567890123456789012345678901234567890');
      expect(formatted, contains(' '));
      final parts = formatted.split(' ');
      expect(parts.length, 12); // 60 / 5 = 12 groups
      for (final part in parts) {
        expect(part.length, 5);
      }
    });
  });
}
