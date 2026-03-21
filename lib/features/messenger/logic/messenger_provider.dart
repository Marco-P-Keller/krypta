import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../security/encryption/encryption_service.dart';
import '../../../security/encryption/key_pair_model.dart';
import '../../../security/key_management/key_manager.dart';
import '../../../services/firebase/auth_service.dart';
import '../../../services/firebase/firestore_service.dart';
import '../../../services/notification/notification_service.dart';
import '../../../services/storage/encrypted_local_store.dart';
import '../data/models/chat_model.dart';
import '../data/models/contact_model.dart';
import '../data/models/message_model.dart';

/// Central messenger state. Handles: contacts, chats, messages,
/// E2E encryption, real-time sync, typing, self-destruct, acks.
class MessengerProvider extends ChangeNotifier {
  final EncryptionService _encryption;
  final KeyManager _keyManager;
  final AuthService _auth;
  final FirestoreService _firestore;
  final EncryptedLocalStore _localStore;
  final NotificationService _notifications;
  final _uuid = const Uuid();

  List<Chat> _chats = [];
  List<Contact> _contacts = [];
  final Map<String, List<Message>> _messagesByChat = {};
  final Map<String, bool> _typingStates = {};
  String? _activeChatId;

  StreamSubscription? _inboxSub;
  StreamSubscription? _ackSub;
  StreamSubscription? _typingSub;
  Timer? _selfDestructTimer;
  Timer? _typingDebounce;
  bool _isSyncing = false;
  bool _isInitialized = false;

  MessengerProvider({
    required EncryptionService encryption,
    required KeyManager keyManager,
    required AuthService auth,
    required FirestoreService firestore,
    required EncryptedLocalStore localStore,
    required NotificationService notifications,
  })  : _encryption = encryption,
        _keyManager = keyManager,
        _auth = auth,
        _firestore = firestore,
        _localStore = localStore,
        _notifications = notifications;

  // --- Getters ---

  String? get userId => _auth.userId;
  List<Chat> get chats => List.unmodifiable(_chats);
  List<Contact> get contacts => List.unmodifiable(_contacts);
  String? get activeChatId => _activeChatId;
  bool get isInitialized => _isInitialized;

  List<Message> messagesForChat(String chatId) =>
      List.unmodifiable(_messagesByChat[chatId] ?? []);

  bool isTyping(String contactId) => _typingStates[contactId] ?? false;

  Contact? contactForId(String id) {
    for (final c in _contacts) {
      if (c.id == id) return c;
    }
    return null;
  }

  Chat? chatForContact(String contactId) {
    for (final c in _chats) {
      if (c.recipientId == contactId) return c;
    }
    return null;
  }

  // --- Initialization ---

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Ensure authenticated
    if (!_auth.isSignedIn) {
      await _auth.signInAnonymously();
    }

    // Init local store and load persisted data
    await _localStore.init();
    _chats = await _localStore.loadChats();
    _contacts = await _localStore.loadContacts();

    for (final chat in _chats) {
      _messagesByChat[chat.id] = await _localStore.loadMessages(chat.id);
    }

    // Ensure key pair exists and is registered
    final keyPair = await _keyManager.getOrCreateIdentityKeyPair();
    if (userId != null) {
      try {
        await _firestore.registerPublicKey(
          userId: userId!,
          publicKeyBase64: keyPair.publicKeyBase64,
        );
      } catch (e) {
        debugPrint('Public key registration failed: $e');
      }

      // Register for push notifications
      try {
        await _notifications.initialize(userId!);
      } catch (e) {
        debugPrint('Notification init failed: $e');
      }
    }

    _startSync();
    _startSelfDestructTimer();
    _isInitialized = true;
    notifyListeners();
  }

  // --- Contact Management ---

  Future<Contact?> addContact(String contactId) async {
    if (contactId == userId) return null;

    final existing = contactForId(contactId);
    if (existing != null) return existing;

    try {
      final publicKeyBase64 = await _firestore.getPublicKey(contactId);
      if (publicKeyBase64 == null) return null;

      final contact = Contact(
        id: contactId,
        displayName: 'User ${contactId.substring(0, 6)}',
        publicKey: base64Decode(publicKeyBase64),
        addedAt: DateTime.now(),
      );

      _contacts.add(contact);
      await _localStore.saveContacts(_contacts);
      notifyListeners();
      return contact;
    } catch (e) {
      debugPrint('Add contact failed: $e');
      return null;
    }
  }

  Future<void> renameContact(String contactId, String newName) async {
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx == -1) return;
    _contacts[idx] = _contacts[idx].copyWith(displayName: newName);

    final chatIdx = _chats.indexWhere((c) => c.recipientId == contactId);
    if (chatIdx != -1) {
      _chats[chatIdx] = _chats[chatIdx].copyWith(recipientName: newName);
    }

    await _localStore.saveContacts(_contacts);
    await _localStore.saveChats(_chats);
    notifyListeners();
  }

  // --- Chat Management ---

  Chat getOrCreateChat(Contact contact) {
    final existing = chatForContact(contact.id);
    if (existing != null) return existing;

    final chat = Chat(
      id: _uuid.v4(),
      recipientId: contact.id,
      recipientName: contact.displayName,
    );
    _chats.insert(0, chat);
    _messagesByChat[chat.id] = [];
    _localStore.saveChats(_chats);
    notifyListeners();
    return chat;
  }

  void setActiveChat(String? chatId) {
    _activeChatId = chatId;
    if (chatId != null) {
      final idx = _chats.indexWhere((c) => c.id == chatId);
      if (idx != -1 && _chats[idx].unreadCount > 0) {
        _chats[idx] = _chats[idx].copyWith(unreadCount: 0);
        _localStore.saveChats(_chats);
        notifyListeners();
      }
    }
  }

  Future<void> deleteChat(String chatId) async {
    _chats.removeWhere((c) => c.id == chatId);
    _messagesByChat.remove(chatId);
    await _localStore.deleteMessages(chatId);
    await _localStore.saveChats(_chats);
    notifyListeners();
  }

  Future<void> renameChat(String chatId, String newName) async {
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx == -1) return;
    _chats[idx] = _chats[idx].copyWith(recipientName: newName);
    await _localStore.saveChats(_chats);
    notifyListeners();
  }

  Future<void> setChatSelfDestruct(String chatId, Duration? duration) async {
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx == -1) return;
    _chats[idx] = _chats[idx].copyWith(defaultSelfDestruct: duration);
    await _localStore.saveChats(_chats);
    notifyListeners();
  }

  Chat? chatById(String chatId) {
    for (final c in _chats) {
      if (c.id == chatId) return c;
    }
    return null;
  }

  // --- Sending Messages ---

  Future<void> sendMessage({
    required String chatId,
    required String text,
    Duration? selfDestruct,
    bool burnAfterRead = false,
    String? password,
  }) async {
    final chatIdx = _chats.indexWhere((c) => c.id == chatId);
    if (chatIdx == -1) return;
    final chat = _chats[chatIdx];
    final contact = contactForId(chat.recipientId);
    if (contact == null || userId == null) return;

    final messageId = _uuid.v4();
    final now = DateTime.now();
    final hasPassword = password != null && password.isNotEmpty;

    // If password-protected, encrypt the plaintext with the password first.
    // The password-encrypted blob becomes the "content" that travels through E2E.
    // The sender sees the original text; the recipient sees a locked message.
    String contentForTransmission = text;
    if (hasPassword) {
      contentForTransmission = await _encryption.encryptWithPassword(
        plaintext: text,
        password: password,
      );
    }

    final message = Message(
      id: messageId,
      chatId: chatId,
      senderId: userId!,
      recipientId: chat.recipientId,
      encryptedContent: '',
      decryptedContent: text,
      timestamp: now,
      status: MessageStatus.sending,
      selfDestructDuration: selfDestruct,
      burnAfterRead: burnAfterRead,
      isPasswordProtected: hasPassword,
      passwordUnlocked: true, // Sender always sees their own message
    );

    _addMessageToChat(chatId, message);
    _updateChatPreview(chatId, hasPassword ? '🔒 Password message' : text, now);
    notifyListeners();

    try {
      final payload = await _encryption.encryptMessage(
        plaintext: contentForTransmission,
        recipientPublicKey: contact.publicKey,
      );

      await _firestore.sendEncryptedMessage(
        senderId: userId!,
        recipientId: chat.recipientId,
        messageId: messageId,
        encryptedPayload: payload.toMap(),
        selfDestructMs: selfDestruct?.inMilliseconds,
        burnAfterRead: burnAfterRead,
        isPasswordProtected: hasPassword,
      );

      _updateMessageStatus(chatId, messageId, MessageStatus.sent);
    } catch (e) {
      debugPrint('Send failed: $e');
      _updateMessageStatus(chatId, messageId, MessageStatus.failed);
    }
  }

  // --- Password Message Unlock ---

  Future<bool> unlockMessage({
    required String chatId,
    required String messageId,
    required String password,
  }) async {
    final messages = _messagesByChat[chatId];
    if (messages == null) return false;
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return false;
    final msg = messages[idx];
    if (!msg.isPasswordProtected || msg.passwordUnlocked) return true;

    final plaintext = await _encryption.decryptWithPassword(
      encryptedBase64: msg.decryptedContent ?? '',
      password: password,
    );

    if (plaintext == null) return false;

    messages[idx] = msg.copyWith(
      decryptedContent: plaintext,
      passwordUnlocked: true,
    );
    await _localStore.saveMessages(chatId, messages);
    notifyListeners();
    return true;
  }

  // --- Typing Indicators ---

  void onLocalTyping(String recipientId) {
    if (userId == null) return;
    _typingDebounce?.cancel();
    _firestore.setTyping(recipientId: recipientId, senderId: userId!, isTyping: true);
    _typingDebounce = Timer(const Duration(seconds: 3), () {
      _firestore.setTyping(recipientId: recipientId, senderId: userId!, isTyping: false);
    });
  }

  void stopLocalTyping(String recipientId) {
    if (userId == null) return;
    _typingDebounce?.cancel();
    _firestore.setTyping(recipientId: recipientId, senderId: userId!, isTyping: false);
  }

  // --- Read Receipts ---

  Future<void> markAsRead(String chatId, String messageId) async {
    final messages = _messagesByChat[chatId];
    if (messages == null) return;

    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    final msg = messages[idx];
    if (msg.senderId == userId || msg.readAt != null) return;

    messages[idx] = msg.copyWith(status: MessageStatus.read, readAt: DateTime.now());
    await _localStore.saveMessages(chatId, messages);

    _firestore.sendAck(recipientId: msg.senderId, messageId: msg.id, type: 'read');
    notifyListeners();
  }

  // --- Real-time Sync ---

  void _startSync() {
    if (_isSyncing || userId == null) return;
    _isSyncing = true;

    _inboxSub = _firestore.listenForMessages(userId!).listen(
      _handleInbox,
      onError: (e) => debugPrint('Inbox error: $e'),
    );

    _ackSub = _firestore.listenForAcks(userId!).listen(
      _handleAcks,
      onError: (e) => debugPrint('Ack error: $e'),
    );

    _typingSub = _firestore.listenForTyping(userId!).listen(
      _handleTyping,
      onError: (e) => debugPrint('Typing error: $e'),
    );
  }

  Future<void> _handleInbox(QuerySnapshot<Map<String, dynamic>> snapshot) async {
    for (final change in snapshot.docChanges) {
      if (change.type != DocumentChangeType.added) continue;
      final data = change.doc.data();
      if (data == null) continue;

      try {
        final senderId = data['sid'] as String;
        final messageId = data['mid'] as String;
        final payloadMap = Map<String, dynamic>.from(data['p'] as Map);
        final selfDestructMs = data['sd'] as int?;
        final burnAfterRead = data['bar'] as bool? ?? false;
        final isPasswordProtected = data['pw'] as bool? ?? false;

        // Decrypt E2E layer
        final keyPair = await _keyManager.getOrCreateIdentityKeyPair();
        final payload = EncryptedPayload.fromMap(payloadMap);
        final plaintext = await _encryption.decryptMessage(
          payload: payload,
          privateKey: keyPair.privateKey,
        );

        // Ensure contact exists
        var contact = contactForId(senderId);
        contact ??= await addContact(senderId);
        if (contact == null) {
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }

        // Create/get chat
        final chat = getOrCreateChat(contact);

        // Prevent duplicates
        if ((_messagesByChat[chat.id] ?? []).any((m) => m.id == messageId)) {
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }

        // If password-protected, `plaintext` is the encrypted blob (not real text).
        // The recipient must enter the password to see the actual message.
        final message = Message(
          id: messageId,
          chatId: chat.id,
          senderId: senderId,
          recipientId: userId!,
          encryptedContent: '',
          decryptedContent: plaintext,
          timestamp: DateTime.now(),
          status: MessageStatus.delivered,
          selfDestructDuration: selfDestructMs != null
              ? Duration(milliseconds: selfDestructMs)
              : null,
          burnAfterRead: burnAfterRead,
          isPasswordProtected: isPasswordProtected,
          passwordUnlocked: !isPasswordProtected,
        );

        _addMessageToChat(chat.id, message);
        final preview = isPasswordProtected ? '🔒 Password message' : plaintext;
        _updateChatPreview(
          chat.id, preview, message.timestamp,
          incrementUnread: _activeChatId != chat.id,
        );

        // Send delivery ack
        _firestore.sendAck(recipientId: senderId, messageId: messageId, type: 'delivered');

        // Delete from server
        await _firestore.deleteRelayedMessage(userId!, change.doc.id);
        notifyListeners();
      } catch (e) {
        debugPrint('Process incoming message failed: $e');
        try { await _firestore.deleteRelayedMessage(userId!, change.doc.id); } catch (_) {}
      }
    }
  }

  Future<void> _handleAcks(QuerySnapshot<Map<String, dynamic>> snapshot) async {
    bool changed = false;
    for (final change in snapshot.docChanges) {
      if (change.type != DocumentChangeType.added) continue;
      final data = change.doc.data();
      if (data == null) continue;

      final messageId = data['mid'] as String;
      final type = data['type'] as String;
      final newStatus = type == 'read' ? MessageStatus.read : MessageStatus.delivered;

      for (final chatId in _messagesByChat.keys) {
        final messages = _messagesByChat[chatId]!;
        final idx = messages.indexWhere((m) => m.id == messageId);
        if (idx != -1) {
          messages[idx] = messages[idx].copyWith(
            status: newStatus,
            readAt: type == 'read' ? DateTime.now() : null,
          );
          await _localStore.saveMessages(chatId, messages);
          changed = true;
          break;
        }
      }

      try { await _firestore.deleteAck(userId!, change.doc.id); } catch (_) {}
    }
    if (changed) notifyListeners();
  }

  void _handleTyping(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    _typingStates.clear();

    if (data != null) {
      for (final entry in data.entries) {
        if (entry.value is Timestamp) {
          final ts = entry.value as Timestamp;
          _typingStates[entry.key] = DateTime.now().difference(ts.toDate()).inSeconds < 5;
        }
      }
    }

    for (var i = 0; i < _chats.length; i++) {
      final typing = _typingStates[_chats[i].recipientId] ?? false;
      if (_chats[i].isTyping != typing) {
        _chats[i] = _chats[i].copyWith(isTyping: typing);
      }
    }
    notifyListeners();
  }

  // --- Self-Destruct ---

  void _startSelfDestructTimer() {
    _selfDestructTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      bool changed = false;
      for (final chatId in _messagesByChat.keys) {
        final messages = _messagesByChat[chatId]!;
        final before = messages.length;
        messages.removeWhere((m) => m.isExpired || m.shouldBurn);
        if (messages.length != before) {
          _localStore.saveMessages(chatId, messages);
          changed = true;
        }
      }
      if (changed) notifyListeners();
    });
  }

  Future<void> burnReadMessages(String chatId) async {
    final messages = _messagesByChat[chatId];
    if (messages == null) return;
    final before = messages.length;
    messages.removeWhere((m) => m.burnAfterRead && m.readAt != null);
    if (messages.length != before) {
      await _localStore.saveMessages(chatId, messages);
      notifyListeners();
    }
  }

  // --- Helpers ---

  void _addMessageToChat(String chatId, Message message) {
    _messagesByChat.putIfAbsent(chatId, () => []);
    _messagesByChat[chatId]!.add(message);
    _localStore.saveMessages(chatId, _messagesByChat[chatId]!);
  }

  void _updateMessageStatus(String chatId, String messageId, MessageStatus status) {
    final messages = _messagesByChat[chatId];
    if (messages == null) return;
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    messages[idx] = messages[idx].copyWith(status: status);
    _localStore.saveMessages(chatId, messages);
    notifyListeners();
  }

  void _updateChatPreview(String chatId, String preview, DateTime time,
      {bool incrementUnread = false}) {
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx == -1) return;
    _chats[idx] = _chats[idx].copyWith(
      lastMessagePreview: preview,
      lastMessageTime: time,
      unreadCount: incrementUnread ? _chats[idx].unreadCount + 1 : _chats[idx].unreadCount,
    );
    final chat = _chats.removeAt(idx);
    _chats.insert(0, chat);
    _localStore.saveChats(_chats);
  }

  // --- Wipe ---

  Future<void> wipeAll() async {
    _stopSync();
    _chats.clear();
    _contacts.clear();
    _messagesByChat.clear();
    _typingStates.clear();
    _activeChatId = null;
    _isInitialized = false;
    await _localStore.wipeAll();
    notifyListeners();
  }

  void _stopSync() {
    _inboxSub?.cancel();
    _ackSub?.cancel();
    _typingSub?.cancel();
    _selfDestructTimer?.cancel();
    _typingDebounce?.cancel();
    _isSyncing = false;
  }

  @override
  void dispose() {
    _stopSync();
    super.dispose();
  }
}
