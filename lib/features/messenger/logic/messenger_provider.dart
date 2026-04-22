import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../security/encryption/encryption_service.dart';
import '../../../security/key_management/key_manager.dart';
import '../../../security/memory/sensitive_buffer.dart';
import '../../../security/messaging/control_message.dart';
import '../../../security/prekey/prekey_bundle.dart';
import '../../../security/prekey/prekey_manager.dart';
import '../../../security/ratchet/double_ratchet.dart';
import '../../../security/ratchet/ratchet_message.dart';
import '../../../security/ratchet/ratchet_state.dart';
import '../../../security/session/session_errors.dart';
import '../../../security/session/session_handshake_service.dart';
import '../../../security/transparency/consistency_checker.dart';
import '../../../security/transparency/key_commitment.dart';
import '../../../security/transparency/key_transparency_log.dart';
import '../../../security/transport/privacy_polling.dart';
import '../../../security/transport/sealed_sender.dart';
import '../../../security/transport/timing_protection.dart';
import '../../../security/verification/safety_number.dart';
import '../../../services/firebase/auth_service.dart';
import '../../../services/firebase/firestore_service.dart';
import '../../../services/notification/notification_service.dart';
import '../../../services/storage/encrypted_local_store.dart';
import '../../../services/storage/secure_storage_service.dart';
import '../data/models/chat_model.dart';
import '../data/models/contact_model.dart';
import '../data/models/message_model.dart';

/// Result of adding a contact via QR code with key verification.
enum QrContactResult {
  /// Server key matches QR key — contact is verified.
  verified,
  /// Server key does NOT match QR key — possible MITM. Contact blocked.
  keyMismatch,
  /// User not found on server.
  userNotFound,
}

/// Central messenger state. Handles: contacts, chats, messages,
/// E2E encryption, real-time sync, typing, self-destruct, control messages.
class MessengerProvider extends ChangeNotifier {
  final EncryptionService _encryption;
  final KeyManager _keyManager;
  final AuthService _auth;
  final FirestoreService _firestore;
  final EncryptedLocalStore _localStore;
  final NotificationService _notifications;
  final SecureStorageService _secureStorage;
  final PreKeyManager _preKeyManager;
  KeyTransparencyLog? _transparencyLog;
  ConsistencyChecker? _consistencyChecker;
  final _uuid = const Uuid();

  List<Chat> _chats = [];
  List<Contact> _contacts = [];
  final Map<String, List<Message>> _messagesByChat = {};
  final Map<String, RatchetState> _ratchetStates = {};
  /// X3DH session header to include in the first encrypted message per chat.
  /// Contains the sender's ephemeral public key the receiver needs.
  final Map<String, Map<String, String>> _pendingSessionHeaders = {};
  // Typing states kept local-only — no server metadata leak.
  final Map<String, bool> _typingStates = {};
  /// Tracks processed message IDs to prevent replay/duplicate attacks.
  /// Persisted across sessions via EncryptedLocalStore.
  final Set<String> _processedMessageIds = {};
  /// Rate-limiting for password-protected message unlock attempts.
  /// Maps messageId → (failCount, lastAttemptTime).
  final Map<String, (int, DateTime)> _unlockAttempts = {};
  static const _maxUnlockAttempts = 5;
  static const _unlockCooldown = Duration(seconds: 30);
  String? _activeChatId;
  /// Our current delivery token for sealed sender routing.
  DeliveryToken? _deliveryToken;
  /// Privacy polling service — used when push privacy mode is enabled.
  PrivacyPolling? _privacyPolling;
  /// Whether push privacy mode is active (no FCM, polling only).
  bool _pushPrivacyEnabled = false;
  /// Pending jitter timers for control message delivery (cancelled on wipe/dispose).
  final List<Timer> _pendingJitterTimers = [];
  /// Control message counter for replay prevention (persisted across sessions).
  final ControlMessageCounter _controlCounter = ControlMessageCounter();
  /// Cached HMAC keys per contact for control message signing.
  /// Cleared on key change, wipe, and dispose.
  final Map<String, Uint8List> _hmacKeyCache = {};
  /// Whether delivery receipts are enabled (default: disabled for privacy).
  bool _deliveryReceiptsEnabled = false;
  /// Whether read receipts are enabled (default: disabled for privacy).
  bool _readReceiptsEnabled = false;

  static final _x25519 = X25519();

  StreamSubscription? _inboxSub;
  Timer? _selfDestructTimer;
  Timer? _memoryScrubTimer;
  bool _isSyncing = false;
  bool _isInitialized = false;

  MessengerProvider({
    required EncryptionService encryption,
    required KeyManager keyManager,
    required AuthService auth,
    required FirestoreService firestore,
    required EncryptedLocalStore localStore,
    required NotificationService notifications,
    required SecureStorageService secureStorage,
    PreKeyManager? preKeyManager,
  })  : _encryption = encryption,
        _keyManager = keyManager,
        _auth = auth,
        _firestore = firestore,
        _localStore = localStore,
        _notifications = notifications,
        _secureStorage = secureStorage,
        _preKeyManager = preKeyManager ?? PreKeyManager(localStore: localStore);

  /// Attach Key Transparency for split-view detection and key auditing.
  void setTransparency({
    required KeyTransparencyLog log,
    required ConsistencyChecker checker,
  }) {
    _transparencyLog = log;
    _consistencyChecker = checker;
  }

  // --- Getters ---

  String? get userId => _auth.userId;
  List<Chat> get chats => List.unmodifiable(_chats);
  List<Contact> get contacts => List.unmodifiable(_contacts);
  String? get activeChatId => _activeChatId;
  bool get isInitialized => _isInitialized;
  bool get isPushPrivacyEnabled => _pushPrivacyEnabled;
  bool get isDeliveryReceiptsEnabled => _deliveryReceiptsEnabled;
  bool get isReadReceiptsEnabled => _readReceiptsEnabled;

  List<Message> messagesForChat(String chatId) =>
      List.unmodifiable(_messagesByChat[chatId] ?? []);

  bool isTyping(String contactId) => _typingStates[contactId] ?? false;

  /// Get our identity public key for safety number generation.
  Future<Uint8List?> getIdentityPublicKey() async {
    if (!_keyManager.hasKeysInMemory) return null;
    final kp = await _keyManager.getOrCreateIdentityKeyPair();
    return kp.publicKey;
  }

  Contact? contactForId(String id) {
    for (final c in _contacts) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Validate user ID format (Firebase Auth UID).
  /// Rejects path traversal characters, whitespace, and extreme lengths.
  static bool _isValidUserId(String id) {
    if (id.length < 10 || id.length > 128) return false;
    // Firebase Auth UIDs are alphanumeric (letters, digits)
    return RegExp(r'^[a-zA-Z0-9]+$').hasMatch(id);
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

    // Load persisted replay-protection IDs (survives message deletion)
    _processedMessageIds.addAll(await _localStore.loadProcessedIds());

    for (final chat in _chats) {
      _messagesByChat[chat.id] = await _localStore.loadMessages(chat.id);
      // Load ratchet state for each chat
      final rState = await _localStore.loadRatchetState(chat.id);
      if (rState != null) {
        _ratchetStates[chat.id] = RatchetState.fromMap(rState);
      }
      // Also add current message IDs (belt and suspenders)
      for (final msg in _messagesByChat[chat.id]!) {
        _processedMessageIds.add(msg.id);
      }
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
        if (kDebugMode) debugPrint('Key registration failed');
      }

      // PreKey management: init, rotate if needed, replenish OTPs
      try {
        await _preKeyManager.init();
        if (_preKeyManager.needsRotation()) {
          await _preKeyManager.generateSignedPreKey(keyPair);
        }
        if (_preKeyManager.needsReplenishment()) {
          await _preKeyManager.generateOneTimePreKeys(100);
        }
        // Publish updated bundle
        if (_preKeyManager.currentSignedPreKey != null) {
          final (sig, signingPub) = await _preKeyManager.signPreKey(
            _preKeyManager.currentSignedPreKey!.publicKey,
            keyPair.privateKey,
          );
          final bundle = _preKeyManager.buildBundle(
            keyPair, sig, signingPublicKey: signingPub,
          );
          await _firestore.publishPreKeyBundle(
            userId: userId!,
            bundle: bundle.toMap(),
          );
        }
      } catch (e) {
        if (kDebugMode) debugPrint('PreKey management failed');
      }

      // Check push privacy mode setting
      _pushPrivacyEnabled = await _secureStorage.isPushPrivacyEnabled();

      // Load receipt privacy settings (both default to disabled = maximum privacy)
      _deliveryReceiptsEnabled = await _secureStorage.isDeliveryReceiptsEnabled();
      _readReceiptsEnabled = await _secureStorage.isReadReceiptsEnabled();

      // Load persisted control message counters for replay prevention
      try {
        final counterState = await _localStore.loadControlCounters();
        if (counterState != null) {
          _controlCounter.loadFromMap(counterState);
        }
      } catch (_) {}
      // Persist counter changes automatically
      _controlCounter.onStateChanged = (state) {
        _localStore.saveControlCounters(state);
      };

      if (_pushPrivacyEnabled) {
        // Push privacy mode: delete any existing FCM token from server
        // and do NOT register for push notifications. Messages will be
        // fetched via randomized polling instead.
        try {
          await _firestore.deleteFcmToken(userId!);
        } catch (_) {}
      } else {
        // Normal mode: register for push notifications
        try {
          await _notifications.initialize(userId!);
        } catch (e) {
          if (kDebugMode) debugPrint('Notification init failed: $e');
        }
      }

      // Sealed sender: publish a delivery token for anonymous routing.
      // Other users send to this token instead of our userId, so the
      // server cannot link sender → recipient without reading the token.
      try {
        final token = SealedSender.generateDeliveryToken();
        await _firestore.publishDeliveryToken(
          userId: userId!,
          token: token.token,
        );
        _deliveryToken = token;
      } catch (e) {
        if (kDebugMode) debugPrint('Delivery token publish failed: $e');
      }
    }

    _startSync();
    // Clean up expired messages BEFORE starting timer to avoid concurrent modification
    _cleanupExpiredMessages();
    _startSelfDestructTimer();
    _startMemoryScrubTimer();
    _isInitialized = true;
    notifyListeners();
  }

  // --- Contact Management ---

  Future<Contact?> addContact(String contactId) async {
    if (contactId == userId) return null;
    // Validate contact ID format: Firebase Auth UIDs are alphanumeric, 20-128 chars.
    // Reject anything else to prevent path traversal or injection via document IDs.
    if (!_isValidUserId(contactId)) return null;

    try {
      final publicKeyBase64 = await _firestore.getPublicKey(contactId);
      if (publicKeyBase64 == null) return null;
      final newPublicKey = base64Decode(publicKeyBase64);

      final existing = contactForId(contactId);
      if (existing != null) {
        // Key change detection: if the public key changed, block sending until re-verified.
        // Also invalidate existing ratchet sessions (compromised key = untrusted session).
        if (base64Encode(existing.publicKey) != publicKeyBase64) {
          final idx = _contacts.indexWhere((c) => c.id == contactId);
          _contacts[idx] = existing.copyWith(
            publicKey: newPublicKey,
            trustState: TrustState.keyChanged,
            verifiedAt: null,
            verificationMethod: null,
            verifiedFingerprint: null,
            safetyNumberVersion: null,
            previousPublicKey: existing.publicKey,
            lastKeyChangeAt: DateTime.now(),
            keyChangeCount: existing.keyChangeCount + 1,
          );
          await _localStore.saveContacts(_contacts);

          // Invalidate ratchet sessions and HMAC key cache for this contact
          _invalidateHmacKey(contactId);
          for (final chat in _chats) {
            if (chat.recipientId == contactId) {
              _ratchetStates.remove(chat.id);
              await _localStore.deleteRatchetState(chat.id);
            }
          }

          notifyListeners();
        }
        return contactForId(contactId);
      }

      // New contact: always starts as unverified — never trust blindly.
      // Record first-seen identity key as TOFU baseline.
      final contact = Contact(
        id: contactId,
        displayName: 'User ${contactId.substring(0, 6)}',
        publicKey: newPublicKey,
        addedAt: DateTime.now(),
        trustState: TrustState.unverified,
        firstSeenIdentityKey: Uint8List.fromList(newPublicKey),
      );

      _contacts.add(contact);
      await _localStore.saveContacts(_contacts);

      // Verify Key Transparency chain for new contact (non-blocking)
      await verifyContactTransparency(contactId);

      notifyListeners();
      return contact;
    } catch (e) {
      if (kDebugMode) debugPrint('Add contact failed: $e');
      return null;
    }
  }

  /// Add a contact via QR code with cryptographic key verification.
  ///
  /// This is the ONLY safe way to add a verified contact. The method:
  /// 1. Fetches the server-provided public key for [contactId]
  /// 2. Compares it byte-exact (constant-time) with the QR-provided key
  /// 3. If match → contact is created/updated as verified
  /// 4. If mismatch → contact is blocked (server potentially compromised)
  ///
  /// The QR code is the trust anchor. On mismatch, the QR key is treated
  /// as authoritative and the server key is rejected.
  Future<(Contact?, QrContactResult)> addContactFromQr({
    required String contactId,
    required Uint8List qrPublicKey,
    required String qrFingerprint,
  }) async {
    if (contactId == userId) return (null, QrContactResult.userNotFound);

    try {
      // Fetch server-provided public key
      final serverKeyBase64 = await _firestore.getPublicKey(contactId);
      if (serverKeyBase64 == null) return (null, QrContactResult.userNotFound);
      final serverKey = base64Decode(serverKeyBase64);

      // CRITICAL: Byte-exact, constant-time comparison of server vs QR key.
      // QR is the trust anchor — if they differ, the server is suspect.
      if (!_constantTimeEquals(serverKey, qrPublicKey)) {
        // Key mismatch: treat as security incident.
        final existing = contactForId(contactId);
        if (existing != null) {
          final idx = _contacts.indexWhere((c) => c.id == contactId);
          _contacts[idx] = existing.copyWith(
            publicKey: qrPublicKey, // Trust QR key, not server
            trustState: TrustState.keyChanged,
            verifiedAt: null,
            verificationMethod: null,
            verifiedFingerprint: null,
            safetyNumberVersion: null,
            previousPublicKey: existing.publicKey,
            lastKeyChangeAt: DateTime.now(),
            keyChangeCount: existing.keyChangeCount + 1,
          );
        } else {
          _contacts.add(Contact(
            id: contactId,
            displayName: 'User ${contactId.substring(0, 6)}',
            publicKey: qrPublicKey,
            addedAt: DateTime.now(),
            trustState: TrustState.keyChanged,
            firstSeenIdentityKey: Uint8List.fromList(qrPublicKey),
          ));
        }
        await _localStore.saveContacts(_contacts);

        // Invalidate ratchet sessions and HMAC key cache for this contact
        _invalidateHmacKey(contactId);
        for (final chat in _chats) {
          if (chat.recipientId == contactId) {
            _ratchetStates.remove(chat.id);
            await _localStore.deleteRatchetState(chat.id);
          }
        }

        notifyListeners();
        return (null, QrContactResult.keyMismatch);
      }

      // Keys match — create or update contact as verified
      final existing = contactForId(contactId);
      if (existing != null) {
        final idx = _contacts.indexWhere((c) => c.id == contactId);
        _contacts[idx] = existing.copyWith(
          publicKey: qrPublicKey,
          trustState: TrustState.verified,
          verifiedAt: DateTime.now(),
          verificationMethod: VerificationMethod.qrCode,
          verifiedFingerprint: qrFingerprint,
          safetyNumberVersion: SafetyNumber.currentVersion,
          previousPublicKey: null,
        );
        await _localStore.saveContacts(_contacts);
        notifyListeners();
        return (_contacts[idx], QrContactResult.verified);
      }

      // New contact — directly verified via QR. Record TOFU baseline.
      final contact = Contact(
        id: contactId,
        displayName: 'User ${contactId.substring(0, 6)}',
        publicKey: qrPublicKey,
        addedAt: DateTime.now(),
        trustState: TrustState.verified,
        verifiedAt: DateTime.now(),
        verificationMethod: VerificationMethod.qrCode,
        verifiedFingerprint: qrFingerprint,
        firstSeenIdentityKey: Uint8List.fromList(qrPublicKey),
        safetyNumberVersion: SafetyNumber.currentVersion,
      );
      _contacts.add(contact);
      await _localStore.saveContacts(_contacts);
      notifyListeners();
      return (contact, QrContactResult.verified);
    } catch (e) {
      if (kDebugMode) debugPrint('QR contact add failed: $e');
      return (null, QrContactResult.userNotFound);
    }
  }

  /// Mark a contact as verified after key comparison.
  ///
  /// [verifiedPublicKey] is REQUIRED — verification without key comparison
  /// is not allowed. The key must match the stored key exactly.
  /// Returns false if keys don't match (MITM protection).
  Future<bool> markContactVerified(
    String contactId, {
    VerificationMethod method = VerificationMethod.safetyNumber,
    required Uint8List verifiedPublicKey,
  }) async {
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx == -1) return false;

    final contact = _contacts[idx];

    // Mandatory key comparison — constant-time to prevent timing attacks
    if (!_constantTimeEquals(contact.publicKey, verifiedPublicKey)) {
      return false; // Key mismatch — possible MITM
    }

    final fingerprint = Contact.computeFullFingerprint(verifiedPublicKey);
    _contacts[idx] = contact.copyWith(
      trustState: TrustState.verified,
      verifiedAt: DateTime.now(),
      verificationMethod: method,
      verifiedFingerprint: fingerprint,
      safetyNumberVersion: SafetyNumber.currentVersion,
      previousPublicKey: null,
    );
    await _localStore.saveContacts(_contacts);
    notifyListeners();
    return true;
  }

  /// Acknowledge a key change notification (UI-only).
  ///
  /// DOES NOT re-enable messaging. The contact remains in [keyChanged] state.
  /// The only way to resolve a key change is through re-verification:
  /// - QR code scan ([addContactFromQr])
  /// - Safety number comparison ([markContactVerified])
  ///
  /// This method only clears the [previousPublicKey] to dismiss the diff UI.
  /// Sending remains blocked until the contact is re-verified.
  Future<void> acknowledgeKeyChange(String contactId) async {
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx == -1) return;
    // Keep keyChanged state — only verification can resolve it.
    // Clear previous key since the user has seen the warning.
    _contacts[idx] = _contacts[idx].copyWith(
      previousPublicKey: null,
    );
    await _localStore.saveContacts(_contacts);
    notifyListeners();
  }

  /// Block a contact — no messages can be sent or received.
  Future<void> blockContact(String contactId) async {
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx == -1) return;
    _contacts[idx] = _contacts[idx].copyWith(
      trustState: TrustState.blocked,
    );
    await _localStore.saveContacts(_contacts);
    notifyListeners();
  }

  /// Unblock a contact — returns to keyChanged state (requires re-verification).
  ///
  /// DOES NOT re-enable messaging. After unblocking, the contact must be
  /// re-verified via QR or safety number before messages can flow.
  /// This prevents the block → unblock path from being used to bypass
  /// the key-change verification requirement.
  Future<void> unblockContact(String contactId) async {
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx == -1) return;
    _contacts[idx] = _contacts[idx].copyWith(
      trustState: TrustState.keyChanged,
    );
    await _localStore.saveContacts(_contacts);
    notifyListeners();
  }

  /// Constant-time byte comparison to prevent timing attacks.
  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  // ─── Centralized Trust Gates ────────────────────────────────────────────

  /// Single trust gate for sending. Fail-closed.
  /// Returns null if permitted, or error string if blocked.
  String? _validateSendPermission(Contact contact) {
    if (contact.isBlocked) return 'blocked';
    if (contact.hasKeyChanged) return 'key_changed';
    if (!contact.canSendMessages) return 'trust_insufficient';
    return null;
  }

  /// Single trust gate for receiving. Fail-closed.
  /// Returns null if permitted, or error string if blocked.
  String? _validateReceivePermission(Contact contact) {
    if (contact.isBlocked) return 'blocked';
    if (contact.hasKeyChanged) return 'key_changed';
    return null;
  }

  /// Verify sender identity consistency against TOFU baseline.
  /// Fail-closed: returns false if any inconsistency is detected.
  ///
  /// In unverified state, the current public key MUST equal the
  /// firstSeenIdentityKey baseline. If they differ without a keyChanged
  /// state transition, something has been tampered with.
  bool _verifyIdentityConsistency(Contact contact) {
    if (contact.firstSeenIdentityKey == null) return true;
    if (contact.trustState == TrustState.unverified) {
      if (!_constantTimeEquals(contact.publicKey, contact.firstSeenIdentityKey!)) {
        return false;
      }
    }
    return true;
  }

  // ─── Control Message HMAC Key Derivation ──────────────────────────────

  /// Derive HMAC key for control message signing/verification.
  ///
  /// Uses X25519 DH(ourIdentityPrivate, theirIdentityPublic) → HKDF.
  /// Cached per contact; invalidated on key change or wipe.
  Future<Uint8List> _deriveControlHmacKey(Contact contact) async {
    final cached = _hmacKeyCache[contact.id];
    if (cached != null) return Uint8List.fromList(cached);

    final keyPair = await _keyManager.getOrCreateIdentityKeyPair();
    final kp = await _x25519.newKeyPairFromSeed(keyPair.privateKey);
    final shared = await _x25519.sharedSecretKey(
      keyPair: kp,
      remotePublicKey: SimplePublicKey(contact.publicKey, type: KeyPairType.x25519),
    );
    final sharedBytes = Uint8List.fromList(await shared.extractBytes());

    if (sharedBytes.every((b) => b == 0)) {
      throw StateError('Control HMAC key derivation: zero shared secret');
    }

    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(sharedBytes),
      nonce: Uint8List(32),
      info: utf8.encode('KryptaControlHMAC-v1'),
    );
    SensitiveBuffer.zeroBytes(sharedBytes);

    final key = Uint8List.fromList(await derived.extractBytes());
    _hmacKeyCache[contact.id] = Uint8List.fromList(key);
    return key;
  }

  /// Invalidate cached HMAC key for a contact (on key change).
  void _invalidateHmacKey(String contactId) {
    final cached = _hmacKeyCache.remove(contactId);
    if (cached != null) SensitiveBuffer.zeroBytes(cached);
  }

  // ─── Control Message Send/Receive ─────────────────────────────────────

  /// Send a signed control message through the encrypted message channel.
  ///
  /// Creates a ControlMessage → signs with HMAC → wraps in v3 payload →
  /// encrypts with Double Ratchet → sends via message relay.
  /// The server sees only a regular encrypted message — indistinguishable
  /// from content messages.
  Future<void> _sendControlMessage({
    required String chatId,
    required Contact contact,
    required String type,
    required String messageId,
  }) async {
    if (userId == null) return;
    // Trust gate: don't send control messages to compromised contacts
    if (_validateSendPermission(contact) != null) return;
    if (!_ratchetStates.containsKey(chatId)) return;

    final hmacKey = await _deriveControlHmacKey(contact);
    try {
      final counter = _controlCounter.nextCounter(chatId);
      final ctrl = await ControlMessage.create(
        type: type,
        chatId: chatId,
        messageId: messageId,
        senderId: userId!,
        counter: counter,
        signingKey: hmacKey,
      );

      final innerPayload = <String, dynamic>{
        '_ctrl': ctrl.toMap(),
        '_sid': userId!,
      };

      final payloadMap = await _encryptWithRatchet(chatId, jsonEncode(innerPayload));
      payloadMap['v'] = 3;

      await _firestore.sendEncryptedMessage(
        senderId: userId!,
        recipientId: contact.id,
        messageId: _uuid.v4(),
        encryptedPayload: payloadMap.map((k, v) => MapEntry(k, v.toString())),
      );
    } finally {
      SensitiveBuffer.zeroBytes(hmacKey);
    }
  }

  /// Process a received control message from the decrypted inner payload.
  ///
  /// Verifies HMAC signature, validates counter (replay prevention),
  /// checks sender binding, then applies the control action.
  Future<void> _processControlMessage(
    String chatId,
    Contact contact,
    Map<String, dynamic> innerPayload,
  ) async {
    final ctrlMap = innerPayload['_ctrl'] as Map<String, dynamic>;
    final ControlMessage ctrl;
    try {
      ctrl = ControlMessage.fromMap(ctrlMap);
    } on FormatException {
      if (kDebugMode) debugPrint('Malformed control message — rejected');
      return; // Fail-closed: reject malformed control messages
    }

    // Verify HMAC signature
    final hmacKey = await _deriveControlHmacKey(contact);
    try {
      final verified = await ctrl.verify(hmacKey);
      if (!verified) {
        if (kDebugMode) debugPrint('Control message HMAC verification failed');
        return; // Fail-closed: reject unsigned control messages
      }
    } finally {
      SensitiveBuffer.zeroBytes(hmacKey);
    }

    // Validate sender, counter, timestamp
    final error = ctrl.validate(
      expectedSenderId: contact.id,
      lastSeenCounter: _controlCounter.getLastSeen(chatId),
    );
    if (error != null) {
      if (kDebugMode) debugPrint('Control message validation failed: $error');
      return; // Fail-closed: reject invalid control messages
    }

    // Record counter for replay prevention
    if (!_controlCounter.recordReceived(chatId, ctrl.counter)) {
      if (kDebugMode) debugPrint('Control message replay detected');
      return;
    }

    // Apply the control action
    switch (ctrl.type) {
      case 'delivered':
        _applyDeliveredStatus(ctrl.messageId);
      case 'read':
        _applyReadStatus(ctrl.messageId);
      case 'delete':
        _applyRemoteDelete(ctrl.messageId);
      case 'unlock':
        _applyUnlockNotification(ctrl.messageId);
      default:
        if (kDebugMode) debugPrint('Unknown control message type: ${ctrl.type}');
    }
  }

  /// Apply delivered status from a verified control message.
  void _applyDeliveredStatus(String messageId) {
    for (final chatId in _messagesByChat.keys) {
      final messages = _messagesByChat[chatId]!;
      final idx = messages.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        final msg = messages[idx];
        if (msg.senderId != userId) break; // Only accept for OUR messages
        if (msg.status == MessageStatus.read) break; // Don't regress status
        messages[idx] = msg.copyWith(status: MessageStatus.delivered);
        _localStore.saveMessages(chatId, messages);
        notifyListeners();
        break;
      }
    }
  }

  /// Apply read status from a verified control message.
  void _applyReadStatus(String messageId) {
    for (final chatId in _messagesByChat.keys) {
      final messages = _messagesByChat[chatId]!;
      final idx = messages.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        final msg = messages[idx];
        if (msg.senderId != userId) break;
        if (msg.status == MessageStatus.read) break;
        messages[idx] = msg.copyWith(
          status: MessageStatus.read,
          readAt: DateTime.now(),
        );
        _localStore.saveMessages(chatId, messages);
        notifyListeners();
        break;
      }
    }
  }

  /// Apply remote delete from a verified control message.
  void _applyRemoteDelete(String messageId) {
    for (final chatId in _messagesByChat.keys) {
      final messages = _messagesByChat[chatId]!;
      final idx = messages.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        final msg = messages[idx];
        // Only allow deletion of their messages (they're retracting their own)
        if (msg.senderId == userId) break;
        messages.removeAt(idx);
        _localStore.saveMessages(chatId, messages);
        notifyListeners();
        break;
      }
    }
  }

  /// Apply unlock notification from a verified control message.
  void _applyUnlockNotification(String messageId) {
    for (final chatId in _messagesByChat.keys) {
      final messages = _messagesByChat[chatId]!;
      final idx = messages.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        final msg = messages[idx];
        if (msg.senderId != userId) break; // Only accept for OUR messages
        if (msg.isPasswordProtected && !msg.passwordUnlocked) {
          messages[idx] = msg.copyWith(passwordUnlocked: true);
          _localStore.saveMessages(chatId, messages);
          notifyListeners();
        }
        break;
      }
    }
  }

  /// Verify a contact's Key Transparency chain from the server.
  ///
  /// Fetches new key commitments (incremental sync since last verified epoch),
  /// verifies the hash chain and Ed25519 signatures, and updates the contact's
  /// transparency state.
  /// Fail-closed: verification failure marks transparency as unverified.
  Future<void> verifyContactTransparency(String contactId) async {
    if (_transparencyLog == null) return;

    try {
      final contact = contactForId(contactId);
      if (contact == null) return;

      // Incremental sync: only fetch commitments newer than what we already have.
      final localEpoch = await _transparencyLog!.getLatestEpoch(contactId);
      final List<Map<String, dynamic>> commitmentMaps;
      if (localEpoch >= 0) {
        commitmentMaps = await _firestore.getKeyCommitmentsSince(
            contactId, localEpoch);
      } else {
        commitmentMaps = await _firestore.getKeyCommitments(contactId);
      }
      if (commitmentMaps.isEmpty) return;

      for (final map in commitmentMaps) {
        final commitment = KeyCommitment.fromMap(map);
        final result = await _transparencyLog!.verifyAndAppend(
          userId: contactId,
          commitment: commitment,
          expectedPublicKey: contact.publicKey,
        );

        if (result == CommitmentVerifyResult.epochViolation) {
          // Already-seen epoch during re-sync: verify hash consistency.
          // If the server returns a different commitment for the same epoch,
          // that's a split-view attack — not a benign re-sync.
          final localLog = await _transparencyLog!.getLog(contactId);
          final localAtEpoch = localLog
              .where((c) => c.epoch == commitment.epoch)
              .toList();
          if (localAtEpoch.isNotEmpty &&
              !_constantTimeEquals(
                  localAtEpoch.first.commitHash, commitment.commitHash)) {
            // CRITICAL: Same epoch, different hash = split-view attack
            final idx = _contacts.indexWhere((c) => c.id == contactId);
            if (idx != -1) {
              _contacts[idx] = _contacts[idx].copyWith(
                transparencyVerified: false,
              );
              await _localStore.saveContacts(_contacts);
            }
            return;
          }
          // Hash matches — benign re-sync, skip this commitment
          continue;
        }

        if (result != CommitmentVerifyResult.valid) {
          // Chain broken, signature invalid, or key mismatch — mark as unverified
          final idx = _contacts.indexWhere((c) => c.id == contactId);
          if (idx != -1) {
            _contacts[idx] = _contacts[idx].copyWith(
              transparencyVerified: false,
            );
            await _localStore.saveContacts(_contacts);
          }
          return;
        }
      }

      // All commitments verified — update contact
      final latestEpoch = await _transparencyLog!.getLatestEpoch(contactId);
      final idx = _contacts.indexWhere((c) => c.id == contactId);
      if (idx != -1) {
        _contacts[idx] = _contacts[idx].copyWith(
          lastVerifiedEpoch: latestEpoch,
          transparencyVerified: true,
        );
        await _localStore.saveContacts(_contacts);
      }
    } catch (_) {
      // Fail-closed: verification failure does not crash the app
    }
  }

  /// Process Key Transparency gossip from an incoming message.
  ///
  /// Checks consistency of the sender's view vs our local view.
  /// On split-view detection, marks the contact's transparency as unverified
  /// and persists the change.
  Future<void> _processTransparencyGossip(
      String senderId, Map<String, dynamic> payloadMap) async {
    if (_consistencyChecker == null) return;
    if (!payloadMap.containsKey('_kt')) return;

    try {
      final gossip = payloadMap['_kt'] as Map<String, dynamic>;
      final results = await _consistencyChecker!.processGossipPayload(gossip);

      var splitViewDetected = false;
      for (final entry in results.entries) {
        if (entry.value == ConsistencyResult.splitView) {
          // CRITICAL: Split-view attack detected
          final idx = _contacts.indexWhere((c) => c.id == entry.key);
          if (idx != -1) {
            _contacts[idx] = _contacts[idx].copyWith(
              transparencyVerified: false,
            );
            splitViewDetected = true;
          }
          if (kDebugMode) {
            debugPrint('SPLIT VIEW DETECTED for ${entry.key}');
          }
        }
      }
      // Persist contact state change so split-view detection survives restart
      if (splitViewDetected) {
        await _localStore.saveContacts(_contacts);
      }
    } catch (_) {
      // Gossip processing failure is non-fatal
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
    // Clear decrypted content from the previous active chat (memory hygiene)
    if (_activeChatId != null && _activeChatId != chatId) {
      _clearDecryptedContent(_activeChatId!);
    }

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

  /// Clear decrypted content from messages no longer being viewed.
  /// Rebuilds messages without plaintext so it doesn't linger in memory.
  void _clearDecryptedContent(String chatId) {
    final messages = _messagesByChat[chatId];
    if (messages == null) return;
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].decryptedContent != null) {
        messages[i] = messages[i].copyWith(decryptedContent: null);
      }
    }
  }

  /// Delete a message locally only (visible change only on this device).
  Future<void> deleteMessageForMe(String chatId, String messageId) async {
    final messages = _messagesByChat[chatId];
    if (messages == null) return;
    messages.removeWhere((m) => m.id == messageId);
    await _localStore.saveMessages(chatId, messages);
    if (messages.isNotEmpty) {
      final last = messages.last;
      _updateChatPreview(chatId, last.decryptedContent ?? '', last.timestamp);
    }
    notifyListeners();
  }

  /// Delete a message for both users.
  /// Removes locally and sends a delete command to the recipient.
  Future<void> deleteMessageForEveryone(String chatId, String messageId) async {
    final messages = _messagesByChat[chatId];
    if (messages == null) return;
    final msgIdx = messages.indexWhere((m) => m.id == messageId);
    if (msgIdx == -1) return;
    final msg = messages[msgIdx];

    // Only allow deleting own messages for everyone
    if (msg.senderId != userId) return;

    // Send delete command through encrypted control channel
    final chat = chatById(chatId);
    if (chat != null && userId != null) {
      final contact = contactForId(chat.recipientId);
      if (contact != null) {
        try {
          await _sendControlMessage(
            chatId: chatId,
            contact: contact,
            type: 'delete',
            messageId: messageId,
          );
        } catch (_) {}
      }
    }

    // Delete locally
    messages.removeAt(msgIdx);
    await _localStore.saveMessages(chatId, messages);
    if (messages.isNotEmpty) {
      final last = messages.last;
      _updateChatPreview(chatId, last.decryptedContent ?? '', last.timestamp);
    }
    notifyListeners();
  }

  /// Clear all messages in a chat but keep the chat itself.
  Future<void> clearChat(String chatId) async {
    _messagesByChat[chatId]?.clear();
    await _localStore.saveMessages(chatId, []);
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx != -1) {
      _chats[idx] = _chats[idx].copyWith(
        lastMessagePreview: null,
        lastMessageTime: null,
        unreadCount: 0,
      );
      await _localStore.saveChats(_chats);
    }
    notifyListeners();
  }

  Future<void> deleteChat(String chatId) async {
    _chats.removeWhere((c) => c.id == chatId);
    _messagesByChat.remove(chatId);
    // Zero ratchet private keys before removing from memory.
    final ratchet = _ratchetStates.remove(chatId);
    if (ratchet != null) {
      for (var i = 0; i < ratchet.dhSendingPrivate.length; i++) {
        ratchet.dhSendingPrivate[i] = 0;
      }
      if (ratchet.rootKey.isNotEmpty) {
        for (var i = 0; i < ratchet.rootKey.length; i++) {
          ratchet.rootKey[i] = 0;
        }
      }
    }
    await Future.wait([
      _localStore.deleteMessages(chatId),
      _localStore.deleteRatchetState(chatId),
    ]);
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

    // Centralized trust gate — fail-closed
    final trustError = _validateSendPermission(contact);
    if (trustError != null) {
      if (kDebugMode) debugPrint('Send blocked: $trustError');
      return;
    }

    // Pre-send key validation: check if the server key has changed since
    // we last fetched it. This catches key changes that happen between
    // inbox notifications, preventing messages encrypted to a stale key.
    // Fail-closed: if we can't verify the key, don't send.
    try {
      final serverKeyBase64 = await _firestore.getPublicKey(contact.id);
      if (serverKeyBase64 != null &&
          serverKeyBase64 != base64Encode(contact.publicKey)) {
        // Key changed on server — trigger key change flow and abort send.
        await addContact(contact.id);
        if (kDebugMode) debugPrint('Send aborted: server key changed');
        return;
      }
    } catch (e) {
      // Fail-closed: if we cannot verify the recipient's key is still
      // valid, refuse to send. A malicious server could return errors
      // to prevent key change detection while the key is compromised.
      if (kDebugMode) debugPrint('Send aborted: key verification failed: $e');
      return;
    }

    // Rotate our own delivery token if expired (24h max age).
    // This limits how long a token can be used to correlate our messages.
    if (_deliveryToken != null && _deliveryToken!.isExpired && userId != null) {
      try {
        final newToken = SealedSender.generateDeliveryToken();
        await _firestore.publishDeliveryToken(
          userId: userId!,
          token: newToken.token,
        );
        _deliveryToken = newToken;
      } catch (_) {
        // Rotation failed — keep using existing token.
      }
    }

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
      passwordUnlocked: !hasPassword, // Both sides start locked
    );

    _addMessageToChat(chatId, message);
    _updateChatPreview(chatId, hasPassword ? '🔒 Password message' : text, now);
    notifyListeners();

    try {
      // Initialize ratchet for first message if needed
      if (!_ratchetStates.containsKey(chatId)) {
        await _initRatchetAsSender(chatId, contact);
      }

      // ── v3: ALL metadata inside encrypted payload ──
      // The server sees only ratchet protocol fields. Message type,
      // self-destruct, burn-after-read, password flag, sender identity,
      // KT gossip, and delivery token are all encrypted and invisible.
      final innerPayload = <String, dynamic>{
        '_t': contentForTransmission,
        '_sid': userId!,
      };
      if (selfDestruct != null) innerPayload['_sd'] = selfDestruct.inMilliseconds;
      if (burnAfterRead) innerPayload['_bar'] = true;
      if (hasPassword) innerPayload['_pw'] = true;

      // Key Transparency gossip inside encrypted content
      if (_consistencyChecker != null && userId != null) {
        try {
          final gossip = await _consistencyChecker!.buildGossipPayload(
            localUserId: userId!,
            recipientId: chat.recipientId,
          );
          if (gossip != null) innerPayload['_kt'] = gossip;
        } catch (_) {}
      }

      // Delivery token inside encrypted content
      try {
        final recipientToken = await _firestore.getDeliveryToken(chat.recipientId);
        if (recipientToken != null) innerPayload['_dt'] = recipientToken;
      } catch (_) {}

      // Encrypt the entire inner payload (metadata + content)
      final payloadMap = await _encryptWithRatchet(chatId, jsonEncode(innerPayload));
      payloadMap['v'] = 3; // v3: server sees only ratchet fields

      await _firestore.sendEncryptedMessage(
        senderId: userId!,
        recipientId: chat.recipientId,
        messageId: messageId,
        encryptedPayload: payloadMap.map((k, v) => MapEntry(k, v.toString())),
      );

      _updateMessageStatus(chatId, messageId, MessageStatus.sent);
    } on HandshakeException catch (e) {
      // Fail-closed: handshake security failure — destroy session, do NOT send.
      // Policy: destroySession
      _ratchetStates.remove(chatId);
      await _localStore.deleteRatchetState(chatId);
      if (kDebugMode) debugPrint('Session destroyed — handshake failed: $e');
      _updateMessageStatus(chatId, messageId, MessageStatus.failed);
    } on SessionError catch (e) {
      // Typed session error — apply defined policy
      switch (e.policy) {
        case SessionErrorPolicy.destroySession:
          _ratchetStates.remove(chatId);
          await _localStore.deleteRatchetState(chatId);
          if (kDebugMode) debugPrint('Session destroyed: ${e.category}');
        case SessionErrorPolicy.blockUntilVerified:
          if (kDebugMode) debugPrint('Blocked until verified: ${e.category}');
        case SessionErrorPolicy.rejectMessage:
        case SessionErrorPolicy.retryTransient:
          if (kDebugMode) debugPrint('Send failed: ${e.category}');
      }
      _updateMessageStatus(chatId, messageId, MessageStatus.failed);
    } on StateError catch (e) {
      // Ratchet state error — destroy and retry on next attempt
      _ratchetStates.remove(chatId);
      if (kDebugMode) debugPrint('Ratchet error, session cleared: $e');
      _updateMessageStatus(chatId, messageId, MessageStatus.failed);
    } catch (e) {
      if (kDebugMode) debugPrint('Send failed: $e');
      _updateMessageStatus(chatId, messageId, MessageStatus.failed);
    }
  }

  // --- Password Message Unlock ---

  /// Returns remaining cooldown duration for a locked message, or zero.
  Duration unlockCooldownRemaining(String messageId) {
    final attempt = _unlockAttempts[messageId];
    if (attempt == null) return Duration.zero;
    final (fails, lastTime) = attempt;
    if (fails < _maxUnlockAttempts) return Duration.zero;
    final elapsed = DateTime.now().difference(lastTime);
    if (elapsed >= _unlockCooldown) return Duration.zero;
    return _unlockCooldown - elapsed;
  }

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

    // Rate-limit brute-force attempts on password-protected messages.
    final attempt = _unlockAttempts[messageId];
    if (attempt != null) {
      final (fails, lastTime) = attempt;
      if (fails >= _maxUnlockAttempts &&
          DateTime.now().difference(lastTime) < _unlockCooldown) {
        return false; // Cooldown active
      }
      // Reset counter after cooldown expires
      if (fails >= _maxUnlockAttempts &&
          DateTime.now().difference(lastTime) >= _unlockCooldown) {
        _unlockAttempts[messageId] = (0, DateTime.now());
      }
    }

    final plaintext = await _encryption.decryptWithPassword(
      encryptedBase64: msg.decryptedContent ?? '',
      password: password,
    );

    if (plaintext == null) {
      final current = _unlockAttempts[messageId];
      final fails = (current?.$1 ?? 0) + 1;
      _unlockAttempts[messageId] = (fails, DateTime.now());
      return false;
    }
    // Success: clear attempt tracking
    _unlockAttempts.remove(messageId);

    messages[idx] = msg.copyWith(
      decryptedContent: plaintext,
      passwordUnlocked: true,
    );
    await _localStore.saveMessages(chatId, messages);
    notifyListeners();

    // Notify the sender that we unlocked their message (with jitter).
    // Only if delivery receipts are enabled — unlock is a form of delivery confirmation.
    if (_deliveryReceiptsEnabled && msg.senderId != userId && userId != null) {
      final contact = contactForId(msg.senderId);
      if (contact != null) {
        _pendingJitterTimers.add(
          TimingProtection.sendDeliveryAckWithJitter(() => _sendControlMessage(
            chatId: chatId,
            contact: contact,
            type: 'unlock',
            messageId: messageId,
          )),
        );
      }
    }

    return true;
  }

  // --- Typing Indicators (local-only, no server metadata) ---
  //
  // Privacy-by-design: typing state is NEVER sent to the server.
  // This prevents interaction-metadata leakage. Stubs kept for UI compat.

  void onLocalTyping(String recipientId) {
    // No-op: typing indicators disabled to prevent metadata leakage.
  }

  void stopLocalTyping(String recipientId) {
    // No-op: typing indicators disabled to prevent metadata leakage.
  }

  // --- Push Privacy Mode ---

  /// Toggle push privacy mode.
  ///
  /// When enabled:
  /// - FCM token is deleted from the server
  /// - Firestore real-time listeners are stopped
  /// - Messages are fetched via randomized polling with jitter
  /// - Push notification provider learns nothing about message timing
  ///
  /// When disabled:
  /// - FCM is re-initialized for instant push delivery
  /// - Firestore real-time listeners are restored
  Future<void> setPushPrivacyEnabled(bool enabled) async {
    if (_pushPrivacyEnabled == enabled) return;
    _pushPrivacyEnabled = enabled;
    await _secureStorage.setPushPrivacyEnabled(enabled);

    if (userId == null) return;

    // Stop current sync mechanism
    _stopSync();

    if (enabled) {
      // Delete FCM token — push provider can no longer reach us
      try {
        await _firestore.deleteFcmToken(userId!);
      } catch (_) {}
    } else {
      // Re-register for push notifications
      try {
        await _notifications.initialize(userId!);
      } catch (e) {
        if (kDebugMode) debugPrint('Push re-init failed: $e');
      }
    }

    // Restart sync with new mode
    _startSync();
    _startSelfDestructTimer();
    notifyListeners();
  }

  // --- Receipt Privacy Settings ---

  /// Toggle delivery receipts (default: disabled).
  /// When disabled, senders learn nothing about message delivery.
  Future<void> setDeliveryReceiptsEnabled(bool enabled) async {
    _deliveryReceiptsEnabled = enabled;
    await _secureStorage.setDeliveryReceiptsEnabled(enabled);
    notifyListeners();
  }

  /// Toggle read receipts (default: disabled).
  /// When disabled, senders learn nothing about read state.
  Future<void> setReadReceiptsEnabled(bool enabled) async {
    _readReceiptsEnabled = enabled;
    await _secureStorage.setReadReceiptsEnabled(enabled);
    notifyListeners();
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

    // Read receipt: only sent if the user explicitly enabled read receipts.
    // Default: disabled (maximum privacy — sender learns nothing about read state).
    if (_readReceiptsEnabled && userId != null) {
      final contact = contactForId(msg.senderId);
      if (contact != null) {
        _pendingJitterTimers.add(
          TimingProtection.sendReadReceiptWithJitter(() => _sendControlMessage(
            chatId: chatId,
            contact: contact,
            type: 'read',
            messageId: msg.id,
          )),
        );
      }
    }
    notifyListeners();
  }

  // --- Real-time Sync ---

  void _startSync() {
    if (_isSyncing || userId == null) return;
    _isSyncing = true;

    if (_pushPrivacyEnabled) {
      // Privacy mode: use randomized polling instead of real-time listeners.
      // No persistent connections — reduces metadata leaked to server.
      // Control messages (ACKs, deletes, reads) travel through the same
      // encrypted message channel — no separate ACK polling needed.
      _privacyPolling = PrivacyPolling(
        onMessages: _handlePolledMessages,
      );
      _privacyPolling!.start(userId!);
    } else {
      // Normal mode: Firestore real-time listeners (push-based).
      // Single inbox listener handles both content and control messages.
      _inboxSub = _firestore.listenForMessages(userId!).listen(
        _handleInbox,
        onError: (e) { if (kDebugMode) debugPrint('Inbox error: $e'); },
      );
    }
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

        // Reject oversized payloads to prevent OOM during decryption.
        // Use jsonEncode for reliable size measurement (not .toString()).
        final payloadSize = jsonEncode(payloadMap).length;
        if (payloadSize > 65536) {
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }

        // Reject messages from unknown senders. Do NOT auto-create contacts.
        final contact = contactForId(senderId);
        if (contact == null) {
          if (kDebugMode) debugPrint('Rejected message from unknown sender: $senderId');
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }

        // Centralized trust gate — fail-closed
        final trustError = _validateReceivePermission(contact);
        if (trustError != null) {
          if (kDebugMode) debugPrint('Receive blocked ($trustError): $senderId');
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }

        // Identity consistency check (TOFU baseline)
        if (!_verifyIdentityConsistency(contact)) {
          if (kDebugMode) debugPrint('Identity consistency violation: $senderId');
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }

        final chat = getOrCreateChat(contact);

        // Replay/duplicate prevention
        if (_processedMessageIds.contains(messageId)) {
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }
        if ((_messagesByChat[chat.id] ?? []).any((m) => m.id == messageId)) {
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }

        // Strict version check: v2+ only (Double Ratchet required)
        final version = payloadMap['v'] as int? ?? 1;
        if (version < 2) {
          if (kDebugMode) debugPrint('Rejected v1 legacy message from $senderId');
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }

        // Decrypt with Double Ratchet
        final plaintext = await _decryptWithRatchet(chat.id, contact, payloadMap);

        // Parse inner payload based on version
        Map<String, dynamic> innerPayload;
        String messageContent;
        if (version >= 3) {
          // v3: ALL metadata inside encrypted content
          innerPayload = jsonDecode(plaintext) as Map<String, dynamic>;
          messageContent = innerPayload['_t'] as String? ?? '';
        } else {
          // v2 legacy: metadata alongside ratchet fields (visible to server)
          innerPayload = payloadMap;
          messageContent = plaintext;
        }

        // ── Control message detection (v3+ only) ──
        // Control messages travel through the same encrypted channel as
        // content messages. CRITICAL: only process _ctrl from v3+ payloads
        // where the field was inside the encrypted content. In v2, the
        // innerPayload IS the server-visible payloadMap — a malicious
        // server could inject a _ctrl field to forge control messages.
        if (version >= 3 && innerPayload.containsKey('_ctrl')) {
          await _processControlMessage(chat.id, contact, innerPayload);
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }

        // Sealed sender validation: authoritative sender MUST be inside
        // the encrypted payload. Without it, the server controls identity.
        final sealedSenderId = innerPayload['_sid'] as String?;
        if (sealedSenderId == null) {
          if (kDebugMode) debugPrint('Rejected message without sealed sender identity');
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }
        if (sealedSenderId != senderId) {
          if (kDebugMode) debugPrint('Sealed sender mismatch: routing=$senderId, sealed=$sealedSenderId');
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }

        // Process Key Transparency gossip from the encrypted payload
        await _processTransparencyGossip(senderId, innerPayload);

        // Extract message metadata from the (now correctly encrypted) inner payload
        final selfDestructMs = innerPayload['_sd'] as int? ??
            (innerPayload['sd'] as int?); // v2 compat
        final burnAfterRead = innerPayload['_bar'] == true ||
            innerPayload['_bar'] == 'true' ||
            innerPayload['bar'] == true ||
            innerPayload['bar'] == 'true'; // v2 compat
        final isPasswordProtected = innerPayload['_pw'] == true ||
            innerPayload['_pw'] == 'true' ||
            innerPayload['pw'] == true ||
            innerPayload['pw'] == 'true'; // v2 compat

        final message = Message(
          id: messageId,
          chatId: chat.id,
          senderId: senderId,
          recipientId: userId!,
          encryptedContent: '',
          decryptedContent: messageContent,
          timestamp: DateTime.now(),
          status: MessageStatus.delivered,
          selfDestructDuration: selfDestructMs != null
              ? Duration(milliseconds: int.tryParse(selfDestructMs.toString()) ?? 0)
              : null,
          burnAfterRead: burnAfterRead,
          isPasswordProtected: isPasswordProtected,
          passwordUnlocked: !isPasswordProtected,
        );

        _addMessageToChat(chat.id, message);
        final preview = isPasswordProtected ? '🔒 Password message' : messageContent;
        _updateChatPreview(
          chat.id, preview, message.timestamp,
          incrementUnread: _activeChatId != chat.id,
        );

        // Delivery ACK via encrypted control channel (with jitter).
        // Only sent if delivery receipts are enabled.
        if (_deliveryReceiptsEnabled && userId != null) {
          _pendingJitterTimers.add(
            TimingProtection.sendDeliveryAckWithJitter(() => _sendControlMessage(
              chatId: chat.id,
              contact: contact,
              type: 'delivered',
              messageId: messageId,
            )),
          );
        }

        await _firestore.deleteRelayedMessage(userId!, change.doc.id);
        notifyListeners();
      } on SessionError catch (e) {
        switch (e.policy) {
          case SessionErrorPolicy.destroySession:
            final contact = contactForId(data['sid'] as String);
            if (contact != null) {
              for (final chat in _chats) {
                if (chat.recipientId == contact.id) {
                  _ratchetStates.remove(chat.id);
                  await _localStore.deleteRatchetState(chat.id);
                }
              }
            }
            if (kDebugMode) debugPrint('Session destroyed on receive: ${e.category}');
          case SessionErrorPolicy.blockUntilVerified:
            if (kDebugMode) debugPrint('Blocked on receive: ${e.category}');
          case SessionErrorPolicy.rejectMessage:
            if (kDebugMode) debugPrint('Message rejected: ${e.category}');
          case SessionErrorPolicy.retryTransient:
            if (kDebugMode) debugPrint('Transient receive error: ${e.category}');
        }
        try { await _firestore.deleteRelayedMessage(userId!, change.doc.id); } catch (_) {}
      } on HandshakeException catch (e) {
        if (kDebugMode) debugPrint('Handshake failed on receive: $e');
        try { await _firestore.deleteRelayedMessage(userId!, change.doc.id); } catch (_) {}
      } catch (e) {
        if (kDebugMode) debugPrint('Process incoming message failed: $e');
        try { await _firestore.deleteRelayedMessage(userId!, change.doc.id); } catch (_) {}
      }
    }
  }

  // _handleTyping removed — typing indicators disabled (privacy-by-design).

  // --- Privacy Polling Handlers ---

  /// Handle messages retrieved by privacy polling (one-shot fetch).
  /// Converts raw document snapshots into the same flow as _handleInbox.
  void _handlePolledMessages(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    // Wrap as a synthetic snapshot-like iteration for _handleInbox.
    // Process each doc as an "added" change.
    for (final doc in docs) {
      _processPolledMessage(doc);
    }
  }

  Future<void> _processPolledMessage(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    try {
      final senderId = data['sid'] as String;
      final messageId = data['mid'] as String;
      final payloadMap = Map<String, dynamic>.from(data['p'] as Map);

      final payloadSize = jsonEncode(payloadMap).length;
      if (payloadSize > 65536) {
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }

      final contact = contactForId(senderId);
      if (contact == null) {
        if (kDebugMode) debugPrint('Rejected polled message from unknown sender: $senderId');
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }

      // Centralized trust gate — fail-closed
      final trustError = _validateReceivePermission(contact);
      if (trustError != null) {
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }

      // Identity consistency check (TOFU baseline)
      if (!_verifyIdentityConsistency(contact)) {
        if (kDebugMode) debugPrint('Identity consistency violation: $senderId');
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }

      final chat = getOrCreateChat(contact);

      if (_processedMessageIds.contains(messageId)) {
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }
      if ((_messagesByChat[chat.id] ?? []).any((m) => m.id == messageId)) {
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }

      final version = payloadMap['v'] as int? ?? 1;
      if (version < 2) {
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }

      final plaintext = await _decryptWithRatchet(chat.id, contact, payloadMap);

      // Parse inner payload based on version
      Map<String, dynamic> innerPayload;
      String messageContent;
      if (version >= 3) {
        innerPayload = jsonDecode(plaintext) as Map<String, dynamic>;
        messageContent = innerPayload['_t'] as String? ?? '';
      } else {
        innerPayload = payloadMap;
        messageContent = plaintext;
      }

      // Control message detection (v3+ only — v2 payloadMap is server-visible)
      if (version >= 3 && innerPayload.containsKey('_ctrl')) {
        await _processControlMessage(chat.id, contact, innerPayload);
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }

      // Sealed sender validation
      final sealedSenderId = innerPayload['_sid'] as String?;
      if (sealedSenderId == null) {
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }
      if (sealedSenderId != senderId) {
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }

      // Process Key Transparency gossip from the encrypted payload
      await _processTransparencyGossip(senderId, innerPayload);

      // Extract metadata from inner payload (v3 keys with v2 compat)
      final selfDestructMs = innerPayload['_sd'] as int? ??
          (innerPayload['sd'] as int?);
      final burnAfterRead = innerPayload['_bar'] == true ||
          innerPayload['_bar'] == 'true' ||
          innerPayload['bar'] == true ||
          innerPayload['bar'] == 'true';
      final isPasswordProtected = innerPayload['_pw'] == true ||
          innerPayload['_pw'] == 'true' ||
          innerPayload['pw'] == true ||
          innerPayload['pw'] == 'true';

      final message = Message(
        id: messageId,
        chatId: chat.id,
        senderId: senderId,
        recipientId: userId!,
        encryptedContent: '',
        decryptedContent: messageContent,
        timestamp: DateTime.now(),
        status: MessageStatus.delivered,
        selfDestructDuration: selfDestructMs != null
            ? Duration(milliseconds: int.tryParse(selfDestructMs.toString()) ?? 0)
            : null,
        burnAfterRead: burnAfterRead,
        isPasswordProtected: isPasswordProtected,
        passwordUnlocked: !isPasswordProtected,
      );

      _addMessageToChat(chat.id, message);
      final preview = isPasswordProtected ? '🔒 Password message' : messageContent;
      _updateChatPreview(
        chat.id, preview, message.timestamp,
        incrementUnread: _activeChatId != chat.id,
      );

      // Delivery ACK via encrypted control channel (with jitter)
      if (_deliveryReceiptsEnabled && userId != null) {
        _pendingJitterTimers.add(
          TimingProtection.sendDeliveryAckWithJitter(() => _sendControlMessage(
            chatId: chat.id,
            contact: contact,
            type: 'delivered',
            messageId: messageId,
          )),
        );
      }

      await _firestore.deleteRelayedMessage(userId!, doc.id);
      notifyListeners();
    } on SessionError catch (e) {
      switch (e.policy) {
        case SessionErrorPolicy.destroySession:
          final contact = contactForId(data['sid'] as String);
          if (contact != null) {
            for (final chat in _chats) {
              if (chat.recipientId == contact.id) {
                _ratchetStates.remove(chat.id);
                await _localStore.deleteRatchetState(chat.id);
              }
            }
          }
        case SessionErrorPolicy.blockUntilVerified:
        case SessionErrorPolicy.rejectMessage:
        case SessionErrorPolicy.retryTransient:
          break;
      }
      try { await _firestore.deleteRelayedMessage(userId!, doc.id); } catch (_) {}
    } on HandshakeException catch (e) {
      if (kDebugMode) debugPrint('Handshake failed on polled receive: $e');
      try { await _firestore.deleteRelayedMessage(userId!, doc.id); } catch (_) {}
    } catch (e) {
      if (kDebugMode) debugPrint('Polled message processing failed: $e');
      try { await _firestore.deleteRelayedMessage(userId!, doc.id); } catch (_) {}
    }
  }

  // --- Self-Destruct ---

  /// Remove all expired/burnt messages immediately (called on init).
  void _cleanupExpiredMessages() {
    for (final chatId in _messagesByChat.keys) {
      final messages = _messagesByChat[chatId]!;
      final before = messages.length;
      messages.removeWhere((m) => m.isExpired || m.shouldBurn);
      if (messages.length != before) {
        _localStore.saveMessages(chatId, messages);
      }
    }
  }

  void _startSelfDestructTimer() {
    _selfDestructTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      bool changed = false;
      for (final chatId in _messagesByChat.keys) {
        final messages = _messagesByChat[chatId]!;
        final before = messages.length;
        // Only time-based self-destruct here.
        // Burn-after-read is handled on chat exit (burnReadMessages).
        messages.removeWhere((m) => m.isExpired);
        if (messages.length != before) {
          _localStore.saveMessages(chatId, messages);
          changed = true;
        }
      }
      if (changed) notifyListeners();
    });
  }

  /// Periodically clear decrypted content from inactive chat messages.
  ///
  /// Plaintext should not linger in RAM longer than necessary. Messages
  /// in the active chat are kept readable; all other chats have their
  /// decrypted content scrubbed every 2 minutes.
  void _startMemoryScrubTimer() {
    _memoryScrubTimer?.cancel();
    _memoryScrubTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _scrubInactiveDecryptedContent();
    });
  }

  /// Clear decrypted content from all chats except the active one.
  void _scrubInactiveDecryptedContent() {
    for (final chatId in _messagesByChat.keys) {
      if (chatId == _activeChatId) continue;
      _clearDecryptedContent(chatId);
    }
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

  // --- Double Ratchet Helpers ---

  /// Initialize a ratchet session as sender using X3DH handshake.
  ///
  /// Fetches the recipient's PreKeyBundle from Firestore,
  /// verifies the signed prekey signature, then performs X3DH.
  /// Falls back to simplified DH if no bundle is available.
  ///
  /// Throws [HandshakeException] if signature verification fails.
  Future<void> _initRatchetAsSender(String chatId, Contact contact) async {
    final keyPair = await _keyManager.getOrCreateIdentityKeyPair();

    // Try full X3DH with PreKeyBundle first.
    // Fail-closed on network errors — a malicious server withholding the
    // bundle would force us into the weaker fallback path.
    Map<String, dynamic>? bundleMap;
    try {
      bundleMap = await _firestore.getPreKeyBundle(contact.id);
    } on HandshakeException {
      rethrow; // Don't swallow security errors
    } catch (e) {
      // Network failure fetching bundle: fail-closed.
      // Don't fall through to the weaker fallback — rethrow so the caller
      // gets a send failure rather than a silently degraded session.
      throw BundleNotAvailableError('Bundle fetch failed: $e');
    }

    if (bundleMap != null) {
      final bundle = PreKeyBundle.fromMap(bundleMap);
      final session = await SessionHandshakeService.createOutboundSession(
        identityKeyPair: keyPair,
        bundle: bundle,
      );

      _ratchetStates[chatId] = session.ratchetState;
      await _localStore.saveRatchetState(chatId, session.ratchetState.toMap());

      // Store ephemeral key so it's included in the first message payload.
      // The receiver needs this to perform the mirror X3DH.
      _pendingSessionHeaders[chatId] = {
        'ek': base64Encode(session.ephemeralPublicKey),
      };

      // Consume one-time prekey on server if used
      if (session.usedOneTimePreKeyId != null) {
        try {
          await _firestore.consumeOneTimePreKey(contact.id);
        } catch (_) {}
      }
      return;
    }

    // No bundle published by recipient (new user, not yet initialized).
    // Use X3DH-compatible 3-DH with identity key as "signed prekey".
    // This is weaker than full X3DH — both sides must use the same DH
    // formula and HKDF info string.
    final (ephPub, ephPriv) = await DoubleRatchet.generateEphemeralKeyPair();

    final (sharedSecret, eph2Pub) = await SessionHandshakeService.deriveFallbackSecret(
      identityPrivate: keyPair.privateKey,
      ephemeralPrivate: ephPriv,
      recipientIdentityPublic: contact.publicKey,
    );

    final state = await DoubleRatchet.initAsSender(
      sharedSecret: sharedSecret,
      recipientRatchetPublicKey: contact.publicKey,
    );

    _ratchetStates[chatId] = state;
    await _localStore.saveRatchetState(chatId, state.toMap());

    // Store ephemeral keys for inclusion in the first message
    // ek2 = second ephemeral public key used for DH3 in fallback path
    _pendingSessionHeaders[chatId] = {
      'ek': base64Encode(ephPub),
      'ek2': base64Encode(eph2Pub),
    };
  }

  /// Initialize a ratchet session as receiver (first message from them).
  ///
  /// Extracts the sender's ephemeral public key from [payloadMap] (field `ek`).
  /// Uses our signed prekey if available, otherwise falls back to identity key.
  Future<void> _initRatchetAsReceiver(
      String chatId, Contact contact, Map<String, dynamic> payloadMap) async {
    final keyPair = await _keyManager.getOrCreateIdentityKeyPair();

    // Extract sender's X3DH ephemeral public key from the first message.
    // Without this, the receiver cannot derive the same shared secret.
    final ephKeyB64 = payloadMap['ek'] as String?;
    final senderEphemeralPublic = ephKeyB64 != null
        ? Uint8List.fromList(base64Decode(ephKeyB64))
        : contact.publicKey; // Legacy messages without ek field

    // Extract second ephemeral key (ek2) for fallback path with 3 independent DH outputs
    final eph2KeyB64 = payloadMap['ek2'] as String?;
    final senderEphemeral2Public = eph2KeyB64 != null
        ? Uint8List.fromList(base64Decode(eph2KeyB64))
        : null;

    // Use signed prekey if available for proper X3DH receiver side.
    // Both private and public are needed — the ratchet key pair must match
    // what the sender used as recipientRatchetPublicKey.
    Uint8List signedPreKeyPrivate = keyPair.privateKey;
    Uint8List signedPreKeyPublic = keyPair.publicKey;

    if (_preKeyManager.currentSignedPreKey != null) {
      signedPreKeyPrivate = _preKeyManager.currentSignedPreKey!.privateKey;
      signedPreKeyPublic = _preKeyManager.currentSignedPreKey!.publicKey;
    }

    final state = await SessionHandshakeService.createInboundSession(
      identityKeyPair: keyPair,
      signedPreKeyPrivate: signedPreKeyPrivate,
      signedPreKeyPublic: signedPreKeyPublic,
      senderIdentityPublic: contact.publicKey,
      senderEphemeralPublic: senderEphemeralPublic,
      senderEphemeral2Public: senderEphemeral2Public,
    );

    _ratchetStates[chatId] = state;
    await _localStore.saveRatchetState(chatId, state.toMap());
  }

  /// Encrypt using Double Ratchet. Returns the Firestore payload map.
  ///
  /// Fail-closed: throws if no ratchet state exists.
  Future<Map<String, dynamic>> _encryptWithRatchet(
      String chatId, String content) async {
    final state = _ratchetStates[chatId];
    if (state == null) {
      throw StateError('No ratchet state for chat $chatId — cannot encrypt');
    }
    final ad = Uint8List.fromList(utf8.encode(userId!));
    final plaintext = Uint8List.fromList(utf8.encode(content));
    // Pad to fixed block size to prevent traffic analysis
    final padded = EncryptionService.padPlaintext(plaintext);

    final (newState, ratchetMsg) = await DoubleRatchet.encrypt(
      state: state,
      plaintext: padded,
      associatedData: ad,
    );

    _ratchetStates[chatId] = newState;
    await _localStore.saveRatchetState(chatId, newState.toMap());

    final map = ratchetMsg.toPayloadMap();
    // Include X3DH session header in the first message so the receiver
    // can derive the same shared secret (contains our ephemeral public key).
    final sessionHeader = _pendingSessionHeaders.remove(chatId);
    if (sessionHeader != null) {
      map.addAll(sessionHeader);
    }
    return map;
  }

  /// Decrypt using Double Ratchet. Returns plaintext string.
  ///
  /// Fail-closed: throws if session initialization fails.
  Future<String> _decryptWithRatchet(
      String chatId, Contact contact, Map<String, dynamic> payloadMap) async {
    // Init receiver session if we don't have one yet.
    // Pass payloadMap so the receiver can extract the sender's ephemeral key.
    if (!_ratchetStates.containsKey(chatId)) {
      await _initRatchetAsReceiver(chatId, contact, payloadMap);
    }

    final state = _ratchetStates[chatId];
    if (state == null) {
      throw StateError('Failed to initialize ratchet for chat $chatId');
    }
    final ratchetMsg = RatchetMessage.fromPayloadMap(payloadMap);
    final ad = Uint8List.fromList(utf8.encode(contact.id));

    final (newState, paddedPlaintext) = await DoubleRatchet.decrypt(
      state: state,
      message: ratchetMsg,
      associatedData: ad,
    );

    _ratchetStates[chatId] = newState;
    await _localStore.saveRatchetState(chatId, newState.toMap());

    // Remove padding — mandatory for all v2 messages.
    // No fallback to unpadded: all ratchet messages must be padded.
    final plaintext = EncryptionService.unpadPlaintext(paddedPlaintext);
    return utf8.decode(plaintext);
  }

  // --- Helpers ---

  void _addMessageToChat(String chatId, Message message) {
    _messagesByChat.putIfAbsent(chatId, () => []);
    _messagesByChat[chatId]!.add(message);
    _processedMessageIds.add(message.id); // Replay protection
    _localStore.saveMessages(chatId, _messagesByChat[chatId]!);
    // Persist replay-protection set so deleted messages stay protected
    _localStore.saveProcessedIds(_processedMessageIds);
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
    // Zero private key bytes in ratchet states before clearing references.
    // Best-effort: Dart GC may retain copies, but this prevents casual inspection.
    for (final state in _ratchetStates.values) {
      SensitiveBuffer.zeroBytes(state.dhSendingPrivate);
      if (state.rootKey.isNotEmpty) SensitiveBuffer.zeroBytes(state.rootKey);
      if (state.sendingChainKey != null) {
        SensitiveBuffer.zeroBytes(state.sendingChainKey!);
      }
      if (state.receivingChainKey != null) {
        SensitiveBuffer.zeroBytes(state.receivingChainKey!);
      }
      // Zero skipped message keys
      for (final mk in state.skippedMessageKeys.values) {
        SensitiveBuffer.zeroBytes(mk);
      }
    }
    // Scrub decrypted content from all messages before clearing
    for (final chatId in _messagesByChat.keys) {
      _clearDecryptedContent(chatId);
    }
    // Zero HMAC key cache before clearing
    for (final key in _hmacKeyCache.values) {
      SensitiveBuffer.zeroBytes(key);
    }
    _hmacKeyCache.clear();
    _controlCounter.clear();
    _chats.clear();
    _contacts.clear();
    _messagesByChat.clear();
    _ratchetStates.clear();
    _typingStates.clear();
    _processedMessageIds.clear();
    _activeChatId = null;
    _deliveryToken = null;
    _isInitialized = false;
    // Delete delivery token from server on wipe
    if (userId != null) {
      try {
        await _firestore.deleteDeliveryToken(userId!);
      } catch (_) {}
    }
    await _localStore.wipeAll();
    notifyListeners();
  }

  void _stopSync() {
    _inboxSub?.cancel();
    _privacyPolling?.stop();
    _privacyPolling = null;
    _selfDestructTimer?.cancel();
    _memoryScrubTimer?.cancel();
    // Cancel all pending jitter timers (control messages, read receipts)
    for (final timer in _pendingJitterTimers) {
      timer.cancel();
    }
    _pendingJitterTimers.clear();
    _isSyncing = false;
  }

  @override
  void dispose() {
    _stopSync();
    // Zero HMAC key cache on dispose
    for (final key in _hmacKeyCache.values) {
      SensitiveBuffer.zeroBytes(key);
    }
    _hmacKeyCache.clear();
    super.dispose();
  }
}
