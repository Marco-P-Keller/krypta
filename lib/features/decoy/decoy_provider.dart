import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../messenger/data/models/chat_model.dart';
import '../messenger/data/models/message_model.dart';
import '../../services/storage/encrypted_local_store.dart';

/// Manages the decoy messenger state. Completely separate from the real
/// messenger -- all data is local-only, never touches Firebase.
/// Persisted in its own encrypted storage namespace ('decoy_chats', 'decoy_msg_*').
class DecoyProvider extends ChangeNotifier {
  final EncryptedLocalStore _store;
  final _uuid = const Uuid();

  List<Chat> _chats = [];
  final Map<String, List<Message>> _messagesByChat = {};
  bool _isInitialized = false;

  static const _selfId = 'decoy_self';

  DecoyProvider({required EncryptedLocalStore store}) : _store = store;

  List<Chat> get chats => List.unmodifiable(_chats);
  bool get isInitialized => _isInitialized;

  List<Message> messagesForChat(String chatId) =>
      List.unmodifiable(_messagesByChat[chatId] ?? []);

  Chat? chatById(String chatId) {
    for (final c in _chats) {
      if (c.id == chatId) return c;
    }
    return null;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _chats = await _loadDecoyChats();
    for (final chat in _chats) {
      _messagesByChat[chat.id] = await _loadDecoyMessages(chat.id);
    }
    // Always persist decoy data so the encrypted files exist on disk.
    // Prevents forensic distinguishing: "decoy files exist only when
    // real messenger is also set up" would leak information.
    await _saveDecoyChats();
    _isInitialized = true;
    notifyListeners();
  }

  /// Ensure decoy files exist on disk (call during app init, before any code entry).
  /// This makes the file system indistinguishable whether or not the real messenger
  /// has been used.
  Future<void> ensureDecoyFilesExist() async {
    final existing = await _store.loadDecoyData('decoy_chats');
    if (existing == null) {
      final defaults = _defaultChats();
      await _store.saveDecoyData(
        'decoy_chats',
        defaults.map((c) => c.toMap()).toList(),
      );
    }
  }

  Chat createChat(String contactName) {
    final chat = Chat(
      id: _uuid.v4(),
      recipientId: 'decoy_${_uuid.v4().substring(0, 8)}',
      recipientName: contactName,
      lastMessageTime: DateTime.now(),
    );
    _chats.insert(0, chat);
    _messagesByChat[chat.id] = [];
    _saveDecoyChats();
    notifyListeners();
    return chat;
  }

  void sendMessage({
    required String chatId,
    required String text,
  }) {
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx == -1) return;

    final message = Message(
      id: _uuid.v4(),
      chatId: chatId,
      senderId: _selfId,
      recipientId: _chats[idx].recipientId,
      encryptedContent: '',
      decryptedContent: text,
      timestamp: DateTime.now(),
      status: MessageStatus.read,
    );

    _messagesByChat.putIfAbsent(chatId, () => []);
    _messagesByChat[chatId]!.add(message);

    _chats[idx] = _chats[idx].copyWith(
      lastMessagePreview: text,
      lastMessageTime: DateTime.now(),
    );

    _sortChats();
    _saveDecoyChats();
    _saveDecoyMessages(chatId);
    notifyListeners();
  }

  void deleteChat(String chatId) {
    _chats.removeWhere((c) => c.id == chatId);
    _messagesByChat.remove(chatId);
    _saveDecoyChats();
    _store.deleteMessages('decoy_$chatId');
    notifyListeners();
  }

  void renameChat(String chatId, String newName) {
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx == -1) return;
    _chats[idx] = _chats[idx].copyWith(recipientName: newName);
    _saveDecoyChats();
    notifyListeners();
  }

  void deleteMessage(String chatId, String messageId) {
    final msgs = _messagesByChat[chatId];
    if (msgs == null) return;
    msgs.removeWhere((m) => m.id == messageId);

    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx != -1) {
      _chats[idx] = _chats[idx].copyWith(
        lastMessagePreview: msgs.isNotEmpty ? msgs.last.decryptedContent : null,
      );
    }

    _saveDecoyChats();
    _saveDecoyMessages(chatId);
    notifyListeners();
  }

  bool isMine(Message msg) => msg.senderId == _selfId;

  void _sortChats() {
    _chats.sort((a, b) {
      final aTime = a.lastMessageTime ?? DateTime(2000);
      final bTime = b.lastMessageTime ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });
  }

  // --- Persistence (using the same EncryptedLocalStore but with 'decoy_' prefix) ---

  Future<List<Chat>> _loadDecoyChats() async {
    try {
      final data = await _store.loadDecoyData('decoy_chats');
      if (data == null) return _defaultChats();
      final list = data as List;
      if (list.isEmpty) return [];
      return list.map((e) => Chat.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return _defaultChats();
    }
  }

  Future<List<Message>> _loadDecoyMessages(String chatId) async {
    try {
      final data = await _store.loadDecoyData('decoy_msg_$chatId');
      if (data == null) return [];
      final list = data as List;
      return list.map((e) => Message.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveDecoyChats() async {
    await _store.saveDecoyData(
      'decoy_chats',
      _chats.map((c) => c.toMap()).toList(),
    );
  }

  Future<void> _saveDecoyMessages(String chatId) async {
    final msgs = _messagesByChat[chatId] ?? [];
    await _store.saveDecoyData(
      'decoy_msg_$chatId',
      msgs.map((m) => m.toMap()).toList(),
    );
  }

  /// Pre-seeded chats for first launch so the decoy doesn't look empty.
  List<Chat> _defaultChats() {
    final now = DateTime.now();
    return [
      Chat(
        id: 'decoy_default_1',
        recipientId: 'decoy_c1',
        recipientName: 'Mom',
        lastMessagePreview: 'Did you buy milk?',
        lastMessageTime: now.subtract(const Duration(hours: 2)),
        unreadCount: 1,
      ),
      Chat(
        id: 'decoy_default_2',
        recipientId: 'decoy_c2',
        recipientName: 'Alex',
        lastMessagePreview: 'See you later!',
        lastMessageTime: now.subtract(const Duration(hours: 5)),
      ),
    ];
  }
}
