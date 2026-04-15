import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';

void main() {
  group('Message Self-Destruct Logic', () {
    test('isExpired — not expired when readAt is null', () {
      final msg = Message(
        id: '1',
        chatId: 'c1',
        senderId: 's1',
        recipientId: 'r1',
        encryptedContent: '',
        timestamp: DateTime.now(),
        selfDestructDuration: const Duration(seconds: 30),
        readAt: null,
      );
      expect(msg.isExpired, false);
    });

    test('isExpired — not expired within duration', () {
      final msg = Message(
        id: '1',
        chatId: 'c1',
        senderId: 's1',
        recipientId: 'r1',
        encryptedContent: '',
        timestamp: DateTime.now(),
        selfDestructDuration: const Duration(hours: 1),
        readAt: DateTime.now(),
      );
      expect(msg.isExpired, false);
    });

    test('isExpired — expired after duration', () {
      final msg = Message(
        id: '1',
        chatId: 'c1',
        senderId: 's1',
        recipientId: 'r1',
        encryptedContent: '',
        timestamp: DateTime.now(),
        selfDestructDuration: const Duration(seconds: 1),
        readAt: DateTime.now().subtract(const Duration(seconds: 5)),
      );
      expect(msg.isExpired, true);
    });

    test('isExpired — no self-destruct duration means never expires', () {
      final msg = Message(
        id: '1',
        chatId: 'c1',
        senderId: 's1',
        recipientId: 'r1',
        encryptedContent: '',
        timestamp: DateTime.now(),
        readAt: DateTime.now().subtract(const Duration(days: 365)),
      );
      expect(msg.isExpired, false);
    });

    test('shouldBurn — burns after read when flag set', () {
      final msg = Message(
        id: '1',
        chatId: 'c1',
        senderId: 's1',
        recipientId: 'r1',
        encryptedContent: '',
        timestamp: DateTime.now(),
        burnAfterRead: true,
        readAt: DateTime.now(),
      );
      expect(msg.shouldBurn, true);
    });

    test('shouldBurn — does not burn if not read yet', () {
      final msg = Message(
        id: '1',
        chatId: 'c1',
        senderId: 's1',
        recipientId: 'r1',
        encryptedContent: '',
        timestamp: DateTime.now(),
        burnAfterRead: true,
        readAt: null,
      );
      expect(msg.shouldBurn, false);
    });

    test('shouldBurn — does not burn without flag', () {
      final msg = Message(
        id: '1',
        chatId: 'c1',
        senderId: 's1',
        recipientId: 'r1',
        encryptedContent: '',
        timestamp: DateTime.now(),
        readAt: DateTime.now(),
      );
      expect(msg.shouldBurn, false);
    });
  });

  group('Message Password Lock', () {
    test('isLocked when password-protected and not unlocked', () {
      final msg = Message(
        id: '1',
        chatId: 'c1',
        senderId: 's1',
        recipientId: 'r1',
        encryptedContent: '',
        timestamp: DateTime.now(),
        isPasswordProtected: true,
        passwordUnlocked: false,
      );
      expect(msg.isLocked, true);
    });

    test('not locked when password-protected and unlocked', () {
      final msg = Message(
        id: '1',
        chatId: 'c1',
        senderId: 's1',
        recipientId: 'r1',
        encryptedContent: '',
        timestamp: DateTime.now(),
        isPasswordProtected: true,
        passwordUnlocked: true,
      );
      expect(msg.isLocked, false);
    });
  });

  group('Message Serialization', () {
    test('toMap/fromMap roundtrip preserves all fields', () {
      final original = Message(
        id: 'msg123',
        chatId: 'chat456',
        senderId: 'sender789',
        recipientId: 'recipient012',
        encryptedContent: 'enc',
        decryptedContent: 'hello',
        timestamp: DateTime(2026, 4, 15, 12, 0),
        status: MessageStatus.delivered,
        selfDestructDuration: const Duration(minutes: 5),
        readAt: DateTime(2026, 4, 15, 12, 1),
        burnAfterRead: true,
        isPasswordProtected: true,
        passwordUnlocked: false,
      );

      final map = original.toMap();
      final restored = Message.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.chatId, original.chatId);
      expect(restored.senderId, original.senderId);
      expect(restored.recipientId, original.recipientId);
      expect(restored.decryptedContent, original.decryptedContent);
      expect(restored.status, original.status);
      expect(restored.selfDestructDuration, original.selfDestructDuration);
      expect(restored.burnAfterRead, original.burnAfterRead);
      expect(restored.isPasswordProtected, original.isPasswordProtected);
      expect(restored.passwordUnlocked, original.passwordUnlocked);
    });
  });
}
