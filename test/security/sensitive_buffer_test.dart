import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/memory/sensitive_buffer.dart';

void main() {
  group('SensitiveBuffer', () {
    test('bytes accessible before dispose', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final buf = SensitiveBuffer(data);
      expect(buf.bytes, data);
      expect(buf.length, 5);
      expect(buf.isDisposed, isFalse);
      buf.dispose();
    });

    test('dispose zeros all bytes', () {
      final data = Uint8List.fromList([0xFF, 0xAB, 0xCD, 0xEF]);
      final buf = SensitiveBuffer(data);
      buf.dispose();

      // The original array should be zeroed
      expect(data, equals([0, 0, 0, 0]));
      expect(buf.isDisposed, isTrue);
    });

    test('bytes throws after dispose', () {
      final buf = SensitiveBuffer(Uint8List.fromList([1, 2, 3]));
      buf.dispose();
      expect(() => buf.bytes, throwsStateError);
    });

    test('double dispose is safe', () {
      final buf = SensitiveBuffer(Uint8List.fromList([1, 2, 3]));
      buf.dispose();
      buf.dispose(); // Should not throw
      expect(buf.isDisposed, isTrue);
    });

    test('copy constructor creates independent copy', () {
      final original = Uint8List.fromList([10, 20, 30]);
      final buf = SensitiveBuffer.copy(original);

      // Modifying original should not affect buffer
      original[0] = 99;
      expect(buf.bytes[0], 10);

      buf.dispose();
      // Original should be unaffected by dispose
      expect(original[0], 99);
    });
  });

  group('SensitiveBuffer.zeroBytes', () {
    test('zeros all bytes in a Uint8List', () {
      final data = Uint8List.fromList([0xFF, 0xAB, 0xCD, 0xEF, 0x12]);
      SensitiveBuffer.zeroBytes(data);
      expect(data, equals([0, 0, 0, 0, 0]));
    });

    test('handles empty array', () {
      final data = Uint8List(0);
      SensitiveBuffer.zeroBytes(data);
      expect(data.length, 0);
    });

    test('handles single byte', () {
      final data = Uint8List.fromList([42]);
      SensitiveBuffer.zeroBytes(data);
      expect(data, equals([0]));
    });
  });

  group('SensitiveBuffer.zeroAll', () {
    test('zeros multiple buffers', () {
      final a = Uint8List.fromList([1, 2, 3]);
      final b = Uint8List.fromList([4, 5, 6, 7]);
      final c = Uint8List.fromList([8]);

      SensitiveBuffer.zeroAll([a, b, c]);

      expect(a, equals([0, 0, 0]));
      expect(b, equals([0, 0, 0, 0]));
      expect(c, equals([0]));
    });
  });

  group('SensitiveBuffer.zeroAndReplace', () {
    test('zeros original and returns empty', () {
      final data = Uint8List.fromList([10, 20, 30]);
      final replaced = SensitiveBuffer.zeroAndReplace(data);

      expect(data, equals([0, 0, 0]));
      expect(replaced.length, 0);
    });
  });

  group('RAM Minimization Constants', () {
    test('32-byte key is fully zeroed', () {
      // Simulates a 256-bit AES/ECDH key
      final key = Uint8List(32);
      for (var i = 0; i < 32; i++) key[i] = i + 1;

      SensitiveBuffer.zeroBytes(key);

      for (var i = 0; i < 32; i++) {
        expect(key[i], 0, reason: 'Byte $i should be zero');
      }
    });

    test('large buffer (1KB) is fully zeroed', () {
      final buf = Uint8List(1024);
      for (var i = 0; i < buf.length; i++) buf[i] = 0xFF;

      SensitiveBuffer.zeroBytes(buf);

      for (var i = 0; i < buf.length; i++) {
        expect(buf[i], 0, reason: 'Byte $i should be zero');
      }
    });
  });
}
