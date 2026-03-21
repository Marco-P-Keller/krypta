import '../messenger/data/models/chat_model.dart';
import '../messenger/data/models/message_model.dart';

/// Generates harmless-looking fake chats and messages for the decoy messenger.
abstract final class DecoyData {
  static List<Chat> get chats => [
        Chat(
          id: 'decoy_1',
          recipientId: 'decoy_contact_1',
          recipientName: 'Mom',
          lastMessagePreview: 'Did you buy milk?',
          lastMessageTime: DateTime.now().subtract(const Duration(hours: 2)),
          unreadCount: 1,
        ),
        Chat(
          id: 'decoy_2',
          recipientId: 'decoy_contact_2',
          recipientName: 'Alex',
          lastMessagePreview: 'See you later!',
          lastMessageTime: DateTime.now().subtract(const Duration(hours: 5)),
        ),
        Chat(
          id: 'decoy_3',
          recipientId: 'decoy_contact_3',
          recipientName: 'Work Group',
          lastMessagePreview: 'Meeting at 3pm',
          lastMessageTime: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ];

  static List<Message> messagesForChat(String chatId) {
    switch (chatId) {
      case 'decoy_1':
        return [
          Message(
            id: 'd1_m1',
            chatId: 'decoy_1',
            senderId: 'decoy_contact_1',
            recipientId: 'self',
            encryptedContent: '',
            decryptedContent: 'Hey, are you coming home soon?',
            timestamp: DateTime.now().subtract(const Duration(hours: 3)),
            status: MessageStatus.read,
          ),
          Message(
            id: 'd1_m2',
            chatId: 'decoy_1',
            senderId: 'self',
            recipientId: 'decoy_contact_1',
            encryptedContent: '',
            decryptedContent: 'Yes, in about an hour',
            timestamp: DateTime.now().subtract(const Duration(hours: 2, minutes: 45)),
            status: MessageStatus.read,
          ),
          Message(
            id: 'd1_m3',
            chatId: 'decoy_1',
            senderId: 'decoy_contact_1',
            recipientId: 'self',
            encryptedContent: '',
            decryptedContent: 'Did you buy milk?',
            timestamp: DateTime.now().subtract(const Duration(hours: 2)),
            status: MessageStatus.delivered,
          ),
        ];
      case 'decoy_2':
        return [
          Message(
            id: 'd2_m1',
            chatId: 'decoy_2',
            senderId: 'self',
            recipientId: 'decoy_contact_2',
            encryptedContent: '',
            decryptedContent: 'Want to grab coffee?',
            timestamp: DateTime.now().subtract(const Duration(hours: 6)),
            status: MessageStatus.read,
          ),
          Message(
            id: 'd2_m2',
            chatId: 'decoy_2',
            senderId: 'decoy_contact_2',
            recipientId: 'self',
            encryptedContent: '',
            decryptedContent: 'See you later!',
            timestamp: DateTime.now().subtract(const Duration(hours: 5)),
            status: MessageStatus.read,
          ),
        ];
      default:
        return [];
    }
  }
}
