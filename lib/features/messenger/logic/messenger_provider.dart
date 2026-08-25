import 'dart:async';
import 'dart:convert';
import 'dart:math';
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
import '../../../security/ratchet/replay_guard.dart';
import 'recording_notice_policy.dart';
import 'remote_clear_policy.dart';
import 'contact_request_policy.dart';
import 'key_publish_status.dart';
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

  /// Wer hat von welcher Bildschirmaufnahme schon erfahren. Siehe
  /// [RecordingNoticePolicy]: eine Aufnahme laeuft weiter, waehrend man durch
  /// die App navigiert, und der Chat-Bildschirm fragt bei jedem Aufbau erneut.
  final _recordingNotices = RecordingNoticePolicy();
  final Map<String, RatchetState> _ratchetStates = {};
  /// X3DH session header to include in the first encrypted message per chat.
  /// Contains the sender's ephemeral public key the receiver needs.
  final Map<String, Map<String, dynamic>> _pendingSessionHeaders = {};

  /// Handshake ephemerals (`ek`, base64) whose first message we have already
  /// accepted, per chat. Guards the session-heal path: a relayed COPY of an
  /// old first message (the server controls `mid` and `ek` is not covered by
  /// the message MAC) must not be able to re-derive a stale session over the
  /// live one. Persisted so the guard survives restarts; FIFO-capped.
  final Map<String, List<String>> _acceptedHandshakeEks = {};
  static const int _maxAcceptedEksPerChat = 100;
  static const String _acceptedEksStoreKey = 'hs_accepted_eks';

  /// Healed sessions awaiting commit (Codex review 2026-06, P1): a session
  /// re-derived by [_tryHealSession] must not replace the live one until the
  /// message that produced it passes ALL acceptance checks (sealed sender,
  /// C4/C5 replay/rollback gate, control-message HMAC+counter).
  ///
  /// Keyed by `'$chatId|$messageId'` (round 3): listener and polling can
  /// process different messages of the SAME chat concurrently — a per-chat
  /// slot would let message B overwrite or discard message A's pending
  /// session. Every read/advance/commit/discard targets exactly one
  /// (chat, message) pair; ids are UUIDs, so '|' cannot collide.
  final Map<String, RatchetState> _pendingHealCommits = {};

  static String _healKey(String chatId, String messageId) =>
      '$chatId|$messageId';

  /// H1-Proto / H1-State (audit 2026-05): per-chat ratchet mutex covering
  /// every code path that mutates ratchet state — sends AND decrypts AND
  /// session re-init. Two concurrent receives on the same chat (e.g. one
  /// from the realtime listener and one from a polled fetch) would each
  /// read the ratchet at the same chain key, both decrypt, both write
  /// divergent post-state — corrupting the chain. Serializing all ratchet
  /// mutations per-chat closes both the send race (H1-Proto) and the
  /// receive race (H1-State).
  final Map<String, Future<void>> _ratchetMutexPerChat = {};

  /// Run [body] under the per-chat ratchet mutex. Inner await chains queue
  /// behind any in-flight operation for the same chat.
  Future<T> _underSendMutex<T>(String chatId, Future<T> Function() body) =>
      _underRatchetMutex(chatId, body);

  Future<T> _underRatchetMutex<T>(
      String chatId, Future<T> Function() body) {
    final prior = _ratchetMutexPerChat[chatId] ?? Future<void>.value();
    final completed = Completer<void>();
    final ours = prior.then((_) => completed.future);
    _ratchetMutexPerChat[chatId] = ours;
    return prior.then((_) async {
      try {
        return await body();
      } finally {
        completed.complete();
        // Best-effort cleanup if no one stacked behind us.
        if (identical(_ratchetMutexPerChat[chatId], ours)) {
          _ratchetMutexPerChat.remove(chatId);
        }
      }
    });
  }
  // Typing states kept local-only — no server metadata leak.
  final Map<String, bool> _typingStates = {};
  /// Tracks processed message IDs to prevent replay/duplicate attacks.
  /// Persisted across sessions via EncryptedLocalStore.
  final Set<String> _processedMessageIds = {};
  /// Rate-limiting for password-protected message unlock attempts.
  /// Maps messageId → (failCount, lastAttemptTime).
  /// Persisted across app restarts via [EncryptedLocalStore.saveUnlockAttempts].
  final Map<String, (int, DateTime)> _unlockAttempts = {};
  /// Set of messageIds currently being unlocked — prevents concurrent attempts
  /// on the same message from racing and undercounting failures.
  final Set<String> _unlockInFlight = <String>{};
  /// A3: chats currently mid-deletion. Send/receive paths must skip any
  /// chat id in here so incoming messages cannot be appended to a chat
  /// whose persistence is being torn down.
  final Set<String> _deletingChats = <String>{};
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
  Timer? _inboxReconnectTimer;
  Timer? _selfDestructTimer;
  bool _isSyncing = false;
  bool _isInitialized = false;

  /// Ob die eigenen Schlüssel auf dem Server liegen.
  ///
  /// Ohne sie kann niemand eine Session zu einem aufbauen und es kommt keine
  /// Nachricht an — die App verhält sich sonst aber völlig normal. Vorher
  /// verschwand genau dieser Fehlschlag in einem `catch`, das nur in
  /// Debug-Builds etwas ausgab.
  final KeyPublishStatus _keyPublish = KeyPublishStatus();
  KeyPublishState get keyPublishState => _keyPublish.state;
  bool get keysArePublished => _keyPublish.isHealthy;

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

    // A3: drop any `msg_*` / `ratchet_*` files left behind by a crashed
    // deleteChat — no chat to consume them, and loading a ratchet file
    // whose chat id has been reused elsewhere would silently rebind old
    // private-key material to the new chat.
    //
    // H1-Storage (audit 2026-05): only prune when we are *sure* the
    // current `_chats` list reflects reality. Trustworthy ⇔
    //   (a) the chats.enc file does not exist on disk (genuine first run), OR
    //   (b) the chats.enc file exists AND we successfully loaded ≥1 chat.
    // The risky case the flag rules out: chats.enc present on disk but
    // loadChats returned [] because decryption failed transiently —
    // pruning then would wipe all sessions.
    final chatsBlobExists = await _localStore.hasPersistedChatsBlob();
    final chatsTrustworthy = !chatsBlobExists || _chats.isNotEmpty;
    try {
      await _localStore.pruneOrphanChatFiles(
        _chats.map((c) => c.id).toSet(),
        chatsListIsTrustworthy: chatsTrustworthy,
      );
    } catch (_) {}

    // Load persisted replay-protection IDs (survives message deletion)
    _processedMessageIds.addAll(await _localStore.loadProcessedIds());

    // Load accepted handshake ephemerals (session-heal replay guard)
    try {
      final eks = await _localStore.loadData(_acceptedEksStoreKey);
      if (eks is Map) {
        eks.forEach((key, value) {
          if (key is String && value is List) {
            _acceptedHandshakeEks[key] = value.whereType<String>().toList();
          }
        });
      }
    } catch (_) {}

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
        _keyPublish.recordIdentitySuccess();
      } catch (e) {
        // Nicht mehr stillschweigend verschlucken: ohne Identity-Key im
        // Register findet einen niemand. `permission-denied` heißt dabei
        // etwas ganz anderes als ein Netzwerkfehler — siehe KeyPublishStatus.
        _keyPublish.recordIdentityFailure(e);
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
          _keyPublish.recordPreKeySuccess();
        }
      } catch (e) {
        // Ohne veröffentlichtes Bundle kommt kein X3DH-Handshake zustande.
        // Für die Zustellung genauso tödlich wie ein fehlender Identity-Key.
        _keyPublish.recordPreKeyFailure(e);
        if (kDebugMode) debugPrint('PreKey management failed');
      }
      // Der Zustand steuert ein Warnbanner in app.dart — die Oberfläche muss
      // davon erfahren.
      notifyListeners();

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

      // C3: restore per-message unlock failure counts so the rate-limit
      // on password-protected messages survives app restarts.
      try {
        final saved = await _localStore.loadUnlockAttempts();
        if (saved != null) {
          _unlockAttempts.addAll(saved);
        }
      } catch (_) {}

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
      // Authentication is provided by the E2E ratchet, not the token.
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
        // Anfragezustand nachziehen: wer hinzufügt, hat zugestimmt.
        final moved = ContactRequestPolicy.afterLocalAdd(existing);
        if (moved.requestState != existing.requestState) {
          final i = _contacts.indexWhere((c) => c.id == contactId);
          _contacts[i] = moved;
          await _localStore.saveContacts(_contacts);
          notifyListeners();
          await _announceRequestTransition(existing, moved);
        }
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
      //
      // Der Anfragezustand ist `outgoing`: geschrieben werden darf erst, wenn
      // die Gegenseite annimmt. Vorher ging die erste Nachricht verloren —
      // sie wurde beim Empfänger verworfen UND vom Server gelöscht.
      final contact = Contact(
        id: contactId,
        displayName: 'User ${contactId.substring(0, 6)}',
        publicKey: newPublicKey,
        addedAt: DateTime.now(),
        trustState: TrustState.unverified,
        requestState: ContactRequestState.outgoing,
        firstSeenIdentityKey: Uint8List.fromList(newPublicKey),
      );

      _contacts.add(contact);
      await _localStore.saveContacts(_contacts);

      // Verify Key Transparency chain for new contact (non-blocking)
      await verifyContactTransparency(contactId);

      notifyListeners();

      // Die Anfrage abschicken. Ohne sie erfaehrt die Gegenseite nichts und
      // beide warten auf den jeweils anderen — genau der Zustand, den dieser
      // Umbau beseitigt.
      await _sendRequestTo(contact);

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
    String? qrToken,
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
        final moved = ContactRequestPolicy.afterLocalAdd(existing);
        _contacts[idx] = moved.copyWith(
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
        if (_contacts[idx].isOutgoingRequest) {
          await _sendRequestTo(_contacts[idx], qrToken: qrToken);
        }
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
        // Verifiziert heisst: der Schluessel stimmt. Einverstanden heisst es
        // nicht — auch hier geht eine Anfrage voraus, sonst haette der
        // QR-Pfad eine andere Regel als der ID-Pfad und die erste Nachricht
        // ginge beim Empfaenger genauso verloren wie vorher.
        requestState: ContactRequestState.outgoing,
      );
      _contacts.add(contact);
      await _localStore.saveContacts(_contacts);
      notifyListeners();
      await _sendRequestTo(contact, qrToken: qrToken);
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

  // ─── Systemhinweise: Screenshot und Bildschirmaufnahme ──────────────

  /// Kontrollnachrichten-Typen dieser Hinweise, in derselben Reihenfolge wie
  /// [SystemEventKind]. Der Name reist ueber die Leitung, der Index nicht —
  /// eine spaetere Umsortierung des Aufzaehlungstyps darf die Bedeutung nicht
  /// verschieben.
  static const Map<SystemEventKind, String> _systemEventTypes = {
    SystemEventKind.screenshot: 'screenshot',
    SystemEventKind.screenRecording: 'recording',
  };

  /// Festhalten, dass ich selbst einen Screenshot gemacht oder den Bildschirm
  /// aufgenommen habe — und es der Gegenseite mitteilen.
  ///
  /// Verhindern laesst sich beides auf iOS nicht. Der fruehere Versuch, den
  /// Inhalt zu schwaerzen, beruhte auf undokumentiertem Verhalten und wirkte
  /// ab iOS 26 nicht mehr; die App behauptete einen Schutz, den sie nicht
  /// hatte. Ehrlich ist: beide Seiten erfahren davon.
  Future<void> reportSystemEvent(String chatId, SystemEventKind kind) async {
    final chatIdx = _chats.indexWhere((c) => c.id == chatId);
    if (chatIdx == -1 || userId == null) return;
    final chat = _chats[chatIdx];
    final contact = contactForId(chat.recipientId);
    if (contact == null) return;

    final messageId = _uuid.v4();
    _appendSystemEvent(
      chatId: chatId,
      kind: kind,
      senderId: userId!,
      recipientId: chat.recipientId,
      messageId: messageId,
    );

    // Scheitert das Senden — kein Netz, blockiert —, bleibt der eigene
    // Eintrag stehen. Er ist auch dann richtig: gemacht wurde der Screenshot.
    try {
      await _sendControlMessage(
        chatId: chatId,
        contact: contact,
        type: _systemEventTypes[kind]!,
        messageId: messageId,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Systemhinweis nicht zustellbar: $e');
    }
  }

  /// Eine laufende Bildschirmaufnahme melden — hoechstens einmal je Aufnahme
  /// und Chat.
  ///
  /// [session] kommt vom [PlatformSecurityService] und ist `0`, wenn gerade
  /// nichts aufgenommen wird.
  Future<void> reportScreenRecording(String chatId, int session) async {
    if (!_recordingNotices.shouldAnnounce(chatId, session)) return;
    await reportSystemEvent(chatId, SystemEventKind.screenRecording);
  }

  /// Die Gegenseite hat einen Screenshot gemacht oder nimmt auf.
  void _applySystemEventFromPeer(
      String chatId, Contact contact, SystemEventKind kind, String messageId) {
    if (userId == null) return;
    _appendSystemEvent(
      chatId: chatId,
      kind: kind,
      senderId: contact.id,
      recipientId: userId!,
      messageId: messageId,
    );
  }

  void _appendSystemEvent({
    required String chatId,
    required SystemEventKind kind,
    required String senderId,
    required String recipientId,
    required String messageId,
  }) {
    if (_processedMessageIds.contains(messageId)) return;
    _addMessageToChat(
      chatId,
      Message(
        id: messageId,
        chatId: chatId,
        senderId: senderId,
        recipientId: recipientId,
        encryptedContent: '',
        timestamp: DateTime.now(),
        status: MessageStatus.delivered,
        // Bewusst ohne Selbstzerstoerung und ohne Burn-after-Read: der Hinweis
        // soll nicht ausgerechnet dann verschwinden, wenn man ihn braucht.
        systemEvent: kind,
      ),
    );
    notifyListeners();
  }

  // ─── QR-Token: Zeigen heisst Zustimmen ──────────────────────────────

  /// Einmal-Token aus gerade angezeigten QR-Codes.
  ///
  /// Der übrige QR-Inhalt — Nutzerkennung, Schlüssel und dessen Hash — ist
  /// vollständig öffentlich: wer eine ID kennt, baut ihn nach, ohne den Code
  /// je gesehen zu haben. Erst dieses Token macht aus dem Scannen einen
  /// Nachweis. Wer es vorlegt, hat den Code wirklich vor sich gehabt — und wer
  /// den Code zeigt, will den Kontakt. Deshalb entfällt für ihn die Rückfrage.
  ///
  /// Bewusst nur im Arbeitsspeicher und kurzlebig: das Token gilt für den
  /// Moment, in dem zwei Menschen nebeneinanderstehen, nicht darüber hinaus.
  final Map<String, DateTime> _shownQrTokens = {};
  static const Duration _qrTokenLifetime = Duration(minutes: 10);
  final Random _tokenRandom = Random.secure();

  /// Ein frisches Token für einen QR-Code, der gleich gezeigt wird.
  String issueQrToken() {
    _pruneQrTokens();
    final bytes = List<int>.generate(24, (_) => _tokenRandom.nextInt(256));
    final token = base64Url.encode(bytes);
    _shownQrTokens[token] = DateTime.now();
    return token;
  }

  /// Ein vorgelegtes Token einlösen. Einmalig — danach ist es verbraucht.
  bool _consumeQrToken(String? token) {
    if (token == null || token.isEmpty) return false;
    _pruneQrTokens();
    return _shownQrTokens.remove(token) != null;
  }

  void _pruneQrTokens() {
    final cutoff = DateTime.now().subtract(_qrTokenLifetime);
    _shownQrTokens.removeWhere((_, gezeigt) => gezeigt.isBefore(cutoff));
  }

  // ─── Kontaktanfragen ────────────────────────────────────────────────

  /// Alle unbeantworteten Anfragen an mich.
  List<Contact> get incomingRequests =>
      _contacts.where((c) => c.isIncomingRequest).toList();

  /// Eine Anfrage annehmen. Danach dürfen beide Seiten schreiben.
  ///
  /// Schickt der Gegenseite eine Kontrollnachricht, damit dort die Sperre
  /// ebenfalls fällt. Zu diesem Zeitpunkt existiert eine Sitzung — die
  /// Anfrage wurde ja entschlüsselt —, also trägt der übliche HMAC.
  Future<void> acceptContactRequest(String contactId) async {
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx == -1) return;
    if (!_contacts[idx].isIncomingRequest) return;

    _contacts[idx] = ContactRequestPolicy.afterAccept(_contacts[idx]);
    await _localStore.saveContacts(_contacts);
    notifyListeners();

    final chat = chatForContact(contactId);
    if (chat != null) {
      await _sendControlMessage(
        chatId: chat.id,
        contact: _contacts[idx],
        type: 'accepted',
        messageId: _uuid.v4(),
      );
    }
  }

  /// Eine Anfrage ablehnen.
  ///
  /// Es wird **nichts** zurückgeschickt: der Gegenseite mitzuteilen „du wurdest
  /// abgelehnt" verrät eine Entscheidung, die allein hier getroffen wird. Für
  /// sie sieht eine Ablehnung genauso aus wie eine Blockierung — nach nichts.
  Future<void> declineContactRequest(String contactId) async {
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx == -1) return;
    if (!_contacts[idx].isIncomingRequest) return;

    _contacts[idx] = ContactRequestPolicy.afterDecline(_contacts[idx]);
    await _localStore.saveContacts(_contacts);

    // Der Chat verschwindet — es steht ohnehin nichts drin, eine Anfrage
    // trägt keinen Inhalt.
    final chat = chatForContact(contactId);
    if (chat != null) await deleteChat(chat.id);

    notifyListeners();
  }

  /// Der Gegenseite mitteilen, was der eigene Zustandswechsel für sie bedeutet.
  ///
  /// Ohne das bliebe der andere hängen: hat er mich angefragt und füge ich ihn
  /// dann selbst hinzu, statt auf „Annehmen" zu tippen, wird der Kontakt hier
  /// zwar frei — auf seiner Seite stünde aber weiter „Anfrage gesendet", für
  /// immer.
  Future<void> _announceRequestTransition(Contact vorher, Contact nachher) async {
    final chat = chatForContact(nachher.id);
    if (chat == null) return;

    // Aus einer offenen Anfrage ist ein Kontakt geworden: das ist eine
    // Annahme, auch wenn der Weg dorthin das Hinzufügen war.
    if (vorher.isIncomingRequest &&
        nachher.requestState == ContactRequestState.established) {
      await _sendControlMessage(
        chatId: chat.id,
        contact: nachher,
        type: 'accepted',
        messageId: _uuid.v4(),
      );
      return;
    }

    // Nach eigener Ablehnung doch wieder angefragt.
    if (nachher.isOutgoingRequest) {
      await _sendRequestTo(nachher);
    }
  }

  /// Die Kontaktanfrage an [contact] verschicken.
  ///
  /// Eigener Weg, damit der ID-Pfad und der QR-Pfad dieselbe Regel benutzen.
  Future<void> _sendRequestTo(Contact contact, {String? qrToken}) async {
    final chat = getOrCreateChat(contact);
    await sendMessage(
      chatId: chat.id,
      text: '',
      asContactRequest: true,
      qrToken: qrToken,
    );
  }

  /// Eine Anfrage erneut senden. Ob sie ankommt, entscheidet die Gegenseite.
  ///
  /// Erzwingt dabei eine **frische Sitzung**. Beim Ablehnen wirft die
  /// Gegenseite ihren Chat und damit ihre Ratchet-Sitzung weg; hier bliebe sie
  /// bestehen. Eine Nachricht aus einer laufenden Sitzung trägt keinen
  /// Handschlag-Kopf (`ek`) — die Gegenseite könnte sie nicht entschlüsseln,
  /// und die erneute Anfrage fiele stumm durch. Genau die Art Fehlschlag, die
  /// diesen Umbau ausgelöst hat.
  Future<void> resendContactRequest(String contactId) async {
    final contact = contactForId(contactId);
    final chat = chatForContact(contactId);
    if (contact == null || chat == null) return;

    _ratchetStates.remove(chat.id);
    try {
      await _localStore.deleteRatchetState(chat.id);
    } catch (_) {}

    await _sendRequestTo(contact);
  }

  // ─── Kontaktanfragen: Empfang ───────────────────────────────────────────

  /// Ob von diesem Absender nur eine Anfrage angenommen werden darf.
  ///
  /// `established` und `outgoing` laufen den normalen Weg: bei `outgoing` habe
  /// ich selbst angefragt und muss die Annahme der Gegenseite empfangen
  /// können.
  bool _onlyAcceptsRequestFrom(Contact? contact) =>
      contact == null ||
      contact.requestState == ContactRequestState.incoming ||
      contact.requestState == ContactRequestState.declined;

  /// Eine Nachricht von jemandem ohne angenommenen Kontakt verarbeiten.
  ///
  /// Angenommen wird ausschliesslich eine Kontaktanfrage ohne Inhalt. Jede
  /// andere Nachricht wird verworfen — der Spalt, der sich hier oeffnet, ist
  /// bewusst eng. Die Nachricht ist danach in jedem Fall verbraucht und wird
  /// vom Server geloescht.
  ///
  /// Siehe `docs/KONTAKTANFRAGEN.md`, Abschnitt 3.
  Future<void> _receiveContactRequest({
    required String senderId,
    required String messageId,
    required Map<String, dynamic> payloadMap,
    required String docId,
    required Contact? existing,
  }) async {
    Future<void> drop() => _firestore.deleteRelayedMessage(userId!, docId);

    final rejection = ContactRequestPolicy.rejectIncoming(
      existing: existing,
      openIncomingCount: ContactRequestPolicy.openIncomingCount(_contacts),
    );
    if (rejection != null) {
      if (kDebugMode) debugPrint('Kontaktanfrage abgewiesen: $rejection');
      return drop();
    }

    // Nur v3 traegt die Markierung innerhalb der Verschluesselung. Aeltere
    // Fassungen legen sie neben die Ratchet-Felder, wo der Server sie setzen
    // koennte.
    if ((payloadMap['v'] as int? ?? 1) < 3) return drop();

    // Der Schluessel des Absenders. Ohne ihn laesst sich nichts entschluesseln.
    Contact contact;
    if (existing != null) {
      contact = existing;
    } else {
      final keyBase64 = await _firestore.getPublicKey(senderId);
      if (keyBase64 == null) return drop();
      final key = base64Decode(keyBase64);
      contact = Contact(
        id: senderId,
        displayName: 'User ${senderId.substring(0, 6)}',
        publicKey: key,
        addedAt: DateTime.now(),
        trustState: TrustState.unverified,
        requestState: ContactRequestState.incoming,
        // TOFU-Grundlinie ab der ersten Beruehrung, genau wie in addContact.
        firstSeenIdentityKey: Uint8List.fromList(key),
      );
    }

    // Entschluesseln braucht eine Chat-Kennung. Gibt es schon einen Chat
    // (erneute Anfrage), wird dessen Sitzung weiterbenutzt; sonst entsteht
    // eine neue Kennung, die erst bei Erfolg wirklich gespeichert wird.
    final existingChat = chatForContact(senderId);
    final chatId = existingChat?.id ?? _uuid.v4();

    // Ab dem Moment, in dem Kontakt und Chat gespeichert sind, darf der
    // catch-Zweig unten nichts mehr wegraeumen. Sonst wuerde ein
    // fehlgeschlagenes Loeschen auf dem Server die gerade aufgebaute Sitzung
    // gleich wieder zerstoeren.
    var festgeschrieben = false;

    try {
      final plaintext = await _decryptWithRatchet(
          chatId, contact, payloadMap, messageId: messageId);
      final inner = jsonDecode(plaintext) as Map<String, dynamic>;

      // Sealed Sender: die massgebliche Absenderkennung steht innerhalb der
      // Verschluesselung. Ohne diese Pruefung bestimmt der Server, wer jemand
      // ist.
      if (inner['_sid'] != senderId) {
        _discardPendingHeal(chatId, messageId);
        if (existingChat == null) await _scrubProvisionalSession(chatId);
        await drop();
        return;
      }

      // Von Fremden wird ausschliesslich eine Anfrage angenommen.
      if (inner['_rq'] != 1) {
        if (kDebugMode) {
          debugPrint('Inhalt von unbestaetigtem Kontakt verworfen: $senderId');
        }
        _discardPendingHeal(chatId, messageId);
        if (existingChat == null) await _scrubProvisionalSession(chatId);
        await drop();
        return;
      }

      // Ab hier ist die Anfrage echt und wird sichtbar.
      //
      // Legt sie ein Token vor, das aus einem QR-Code stammt, den ich gerade
      // selbst gezeigt habe, entfällt die Rückfrage: den Code zu zeigen IST
      // die Zustimmung. Das Token ist danach verbraucht.
      final ausQrCode = _consumeQrToken(inner['_rt'] as String?);
      final state = ausQrCode
          ? ContactRequestState.established
          : ContactRequestPolicy.stateAfterIncoming(existing);
      final updated = contact.copyWith(requestState: state);

      final idx = _contacts.indexWhere((c) => c.id == senderId);
      if (idx == -1) {
        _contacts.add(updated);
      } else {
        _contacts[idx] = updated;
      }
      await _localStore.saveContacts(_contacts);

      if (existingChat == null) {
        final chat = Chat(
          id: chatId,
          recipientId: updated.id,
          recipientName: updated.displayName,
        );
        _chats.insert(0, chat);
        _messagesByChat[chat.id] = [];
        await _localStore.saveChats(_chats);
      }

      await _finalizeAcceptedMessage(chatId, messageId, payloadMap);
      _processedMessageIds.add(messageId);
      festgeschrieben = true;
      notifyListeners();

      // Direkt angenommen: die Gegenseite wartet sonst weiter auf eine
      // Antwort, die nie käme.
      if (state == ContactRequestState.established) {
        await _sendControlMessage(
          chatId: chatId,
          contact: updated,
          type: 'accepted',
          messageId: _uuid.v4(),
        );
      }
      await drop();
      return;
    } catch (e) {
      if (kDebugMode) debugPrint('Kontaktanfrage nicht entschluesselbar: $e');
      if (festgeschrieben) {
        // Die Anfrage steht bereits; hier ist nur das Aufraeumen auf dem
        // Server schiefgegangen. Die Nachricht bleibt liegen und wird beim
        // naechsten Durchlauf erneut verarbeitet — sie traegt einen
        // Handschlag-Kopf, ist also weiterhin entschluesselbar.
        return;
      }
      _discardPendingHeal(chatId, messageId);
      if (existingChat == null) await _scrubProvisionalSession(chatId);
      return drop();
    }
  }

  /// Eine Sitzung wegraeumen, die nur fuer den Versuch angelegt wurde.
  ///
  /// Ohne das koennte jeder mit Muell-Nutzlasten Ratchet-Zustaende auf fremden
  /// Geraeten anlegen.
  Future<void> _scrubProvisionalSession(String chatId) async {
    _ratchetStates.remove(chatId);
    try {
      await _localStore.deleteRatchetState(chatId);
    } catch (_) {}
  }

  /// Die Gegenseite hat eine Anfrage von mir angenommen.
  void _applyContactAccepted(String contactId) {
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx == -1) return;
    if (_contacts[idx].requestState != ContactRequestState.outgoing) return;
    _contacts[idx] = ContactRequestPolicy.afterAccept(_contacts[idx]);
    _localStore.saveContacts(_contacts);
    notifyListeners();
  }

  /// Eine Anfrage von jemandem, den ich selbst schon angefragt habe.
  /// Beide sind einverstanden — kein Knopf, keine Blase.
  Future<void> _applyMutualRequest(Contact contact) async {
    final idx = _contacts.indexWhere((c) => c.id == contact.id);
    if (idx == -1) return;
    final state = ContactRequestPolicy.stateAfterIncoming(_contacts[idx]);
    if (state == _contacts[idx].requestState) return;
    _contacts[idx] = _contacts[idx].copyWith(requestState: state);
    await _localStore.saveContacts(_contacts);
    notifyListeners();
  }

  /// Single trust gate for sending. Fail-closed.
  /// Returns null if permitted, or error string if blocked.
  String? _validateSendPermission(Contact contact) {
    if (contact.isGone) return 'gone';
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
  ///
  /// A1: HKDF `info` is bound to the contact's own user ID. Without that
  /// binding, two Firebase accounts that happen to publish the same public
  /// key would derive the SAME HMAC key — a peer that controls multiple
  /// accounts with a shared key could replay or forge control messages
  /// across their chats with the same victim.
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

    // Sort the two participant IDs so both peers derive the same HMAC key.
    // Using `contact.id` alone is asymmetric: Alice would bind to Bob's ID
    // while Bob binds to Alice's ID, producing different keys for the same
    // chat and breaking control-message HMAC verification on every send.
    final pairTag = ([userId!, contact.id]..sort()).join('|');
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(sharedBytes),
      nonce: Uint8List(32),
      info: utf8.encode('KryptaControlHMAC-v2|$pairTag'),
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
    // H1-Proto: serialize control messages with content sends so they
    // share the per-chat ratchet ordering.
    return _underSendMutex(chatId, () => _sendControlMessageLocked(
          chatId: chatId,
          contact: contact,
          type: type,
          messageId: messageId,
        ));
  }

  Future<void> _sendControlMessageLocked({
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

      // H2-Proto (audit 2026-05): no longer toString() the payload values.
      // Kept stringly-typed values caused cross-version int/string parsing
      // ambiguity for `v`, `pv`, `ns`, `pn`, etc. Firestore accepts the
      // JSON-compatible types Krypta uses; pass them through unchanged.
      await _firestore.sendEncryptedMessage(
        senderId: userId!,
        recipientId: contact.id,
        messageId: _uuid.v4(),
        encryptedPayload: payloadMap,
      );
    } finally {
      SensitiveBuffer.zeroBytes(hmacKey);
    }
  }

  /// Process a received control message from the decrypted inner payload.
  ///
  /// Verifies HMAC signature, validates counter (replay prevention),
  /// checks sender binding, then applies the control action.
  ///
  /// Returns true iff the control message was authenticated and fresh —
  /// callers use this as the acceptance signal for committing a pending
  /// healed session (an unknown-but-authentic type still counts).
  Future<bool> _processControlMessage(
    String chatId,
    Contact contact,
    Map<String, dynamic> innerPayload,
  ) async {
    // Type-safe extraction: _ctrl comes from a decrypted but otherwise
    // untrusted payload — a wrong type is a rejection, not a crash.
    final ctrlRaw = innerPayload['_ctrl'];
    if (ctrlRaw is! Map) {
      if (kDebugMode) debugPrint('Malformed control message — rejected');
      return false;
    }
    final ctrlMap = Map<String, dynamic>.from(ctrlRaw);
    final ControlMessage ctrl;
    try {
      ctrl = ControlMessage.fromMap(ctrlMap);
    } on FormatException {
      if (kDebugMode) debugPrint('Malformed control message — rejected');
      return false; // Fail-closed: reject malformed control messages
    }

    // Verify HMAC signature
    final hmacKey = await _deriveControlHmacKey(contact);
    try {
      final verified = await ctrl.verify(hmacKey);
      if (!verified) {
        if (kDebugMode) debugPrint('Control message HMAC verification failed');
        return false; // Fail-closed: reject unsigned control messages
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
      return false; // Fail-closed: reject invalid control messages
    }

    // Record counter for replay prevention
    if (!_controlCounter.recordReceived(chatId, ctrl.counter)) {
      if (kDebugMode) debugPrint('Control message replay detected');
      return false;
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
      case 'accepted':
        _applyContactAccepted(contact.id);
      case 'clearMine':
        _applyPeerClear(chatId, contact.id);
      case 'gone':
        await _applyPeerGone(chatId, contact.id);
      case 'screenshot':
        _applySystemEventFromPeer(
            chatId, contact, SystemEventKind.screenshot, ctrl.messageId);
      case 'recording':
        _applySystemEventFromPeer(
            chatId, contact, SystemEventKind.screenRecording, ctrl.messageId);
      default:
        if (kDebugMode) debugPrint('Unknown control message type: ${ctrl.type}');
    }
    return true;
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
    // Hier wurde frueher der Klartext des verlassenen Chats aus dem Speicher
    // geraeumt. Das darf nicht mehr sein: der Klartext liegt jetzt auch im
    // verschluesselten Speicher, und jeder folgende Statuswechsel schreibt
    // die Liste zurueck — ein geraeumter Eintrag wuerde die gespeicherte
    // Fassung mit null ueberschreiben und die Nachricht dauerhaft
    // unleserlich machen.
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
    await _pruneUnlockAttempts([messageId]);
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
    await _pruneUnlockAttempts([messageId]);
    if (messages.isNotEmpty) {
      final last = messages.last;
      _updateChatPreview(chatId, last.decryptedContent ?? '', last.timestamp);
    }
    notifyListeners();
  }

  /// Die Gegenseite hat die Notfall-Loeschung ausgeloest.
  ///
  /// Ihre Nachrichten verschwinden, im Verlauf steht ein Hinweis, und
  /// geschrieben werden kann nicht mehr: Schluessel und Konto sind auf dem
  /// Server geloescht, eine Nachricht kaeme nie an. Der Chat bleibt lesbar —
  /// was ich geschrieben habe, gehoert weiterhin mir.
  Future<void> _applyPeerGone(String chatId, String peerId) async {
    _applyPeerClear(chatId, peerId);

    final idx = _contacts.indexWhere((c) => c.id == peerId);
    if (idx != -1 && !_contacts[idx].isGone) {
      _contacts[idx] = _contacts[idx].copyWith(isGone: true);
      await _localStore.saveContacts(_contacts);
    }

    _appendSystemEvent(
      chatId: chatId,
      kind: SystemEventKind.accountDeleted,
      senderId: peerId,
      recipientId: userId ?? '',
      messageId: _uuid.v4(),
    );
  }

  /// Die Gegenseite hat ihren Chat geleert.
  ///
  /// Entfernt nur, was sie selbst geschrieben hat — siehe
  /// [removedByPeerClear]. Die Kontrollnachricht ist an ihren Absender
  /// gebunden (HMAC, Zaehler, Absenderpruefung), sie kann also nicht in
  /// fremdem Namen aufraeumen.
  void _applyPeerClear(String chatId, String peerId) {
    final messages = _messagesByChat[chatId];
    if (messages == null) return;

    final weg = messages.where((m) => removedByPeerClear(m, peerId)).toList();
    if (weg.isEmpty) return;
    messages.removeWhere((m) => removedByPeerClear(m, peerId));

    _localStore.saveMessages(chatId, messages);
    _pruneUnlockAttempts(weg.map((m) => m.id).toList());
    if (messages.isEmpty) {
      final idx = _chats.indexWhere((c) => c.id == chatId);
      if (idx != -1) {
        _chats[idx] = _chats[idx].copyWith(
          lastMessagePreview: null,
          lastMessageTime: null,
        );
        _localStore.saveChats(_chats);
      }
    } else {
      final last = messages.last;
      _updateChatPreview(chatId, last.decryptedContent ?? '', last.timestamp);
    }
    notifyListeners();
  }

  /// Allen Kontakten sagen, dass es dieses Konto gleich nicht mehr gibt.
  ///
  /// Muss VOR dem Loeschen laufen: danach sind Schluessel und Sitzungen weg
  /// und es laesst sich nichts mehr senden.
  ///
  /// Streng begrenzt auf [_wipeAnnounceTimeout]. Die Notfall-Loeschung ist
  /// ein Panikknopf — sie darf unter keinen Umstaenden am Netz haengen
  /// bleiben. Wer sie drueckt, hat es eilig. Was in der Zeit rausgeht, geht
  /// raus; der Rest faellt weg, und die Gegenseite merkt es spaetestens
  /// daran, dass ihre Nachrichten nicht mehr zugestellt werden.
  Future<void> _announceGone() async {
    if (userId == null) return;
    final sendungen = <Future<void>>[];
    for (final chat in List<Chat>.from(_chats)) {
      final contact = contactForId(chat.recipientId);
      if (contact == null || contact.isGone) continue;
      if (!_ratchetStates.containsKey(chat.id)) continue;
      sendungen.add(
        _sendControlMessage(
          chatId: chat.id,
          contact: contact,
          type: 'gone',
          messageId: _uuid.v4(),
        ).catchError((_) {}),
      );
    }
    if (sendungen.isEmpty) return;
    try {
      await Future.wait(sendungen).timeout(_wipeAnnounceTimeout);
    } catch (_) {
      // Zeit abgelaufen oder Senden fehlgeschlagen. Beides aendert nichts:
      // geloescht wird trotzdem, und zwar jetzt.
    }
  }

  static const Duration _wipeAnnounceTimeout = Duration(seconds: 3);

  /// Den Chat leeren — auf beiden Geraeten.
  ///
  /// Hier verschwindet alles. Bei der Gegenseite nur, was ich selbst
  /// geschrieben habe: ihre eigenen Nachrichten gehoeren ihr.
  ///
  /// Eine einzige Kontrollnachricht, nicht eine je Nachricht. Ein Chat mit
  /// tausend Eintraegen wuerde sonst tausend Sendevorgaenge ausloesen, den
  /// Ratchet-Zaehler durchdrehen lassen und beim ersten Netzfehler halb
  /// erledigt liegenbleiben.
  Future<void> clearChat(String chatId) async {
    final chat = chatById(chatId);
    final contact =
        chat == null ? null : contactForId(chat.recipientId);
    final hatEigene =
        (_messagesByChat[chatId] ?? const []).any((m) => m.senderId == userId);
    if (contact != null && hatEigene) {
      try {
        await _sendControlMessage(
          chatId: chatId,
          contact: contact,
          type: 'clearMine',
          messageId: _uuid.v4(),
        );
      } catch (e) {
        // Kein Netz, blockiert, keine Sitzung: lokal wird trotzdem geleert.
        // Der Nutzer hat es angewiesen, und ein halb geleerter Chat waere
        // schlechter als einer, der drueben stehen bleibt.
        if (kDebugMode) debugPrint('Chat leeren nicht zustellbar: $e');
      }
    }

    final removedIds =
        (_messagesByChat[chatId] ?? const []).map((m) => m.id).toList();
    _messagesByChat[chatId]?.clear();
    await _localStore.saveMessages(chatId, []);
    await _pruneUnlockAttempts(removedIds);
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
    // A3: mark the chat as deleting BEFORE any await. Concurrent send/receive
    // paths test this set synchronously and drop work for a dying chat,
    // closing the race where an inbound message could be appended between
    // saveChats and the later file delete.
    if (!_deletingChats.add(chatId)) return; // already deleting — no-op

    try {
      final removedMessageIds =
          (_messagesByChat[chatId] ?? const []).map((m) => m.id).toList();

      // saveChats FIRST: if it throws the rest is skipped; on-disk state is
      // left untouched so retry is safe. Previously the memory clear and
      // file deletion preceded this, so a failure would resurrect the chat
      // on next boot with its ratchet state already gone.
      final newChats = _chats.where((c) => c.id != chatId).toList();
      await _localStore.saveChats(newChats);

      _chats
        ..clear()
        ..addAll(newChats);
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
      await _pruneUnlockAttempts(removedMessageIds);
      _pendingHealCommits.removeWhere((key, _) => key.startsWith('$chatId|'));
      if (_acceptedHandshakeEks.remove(chatId) != null) {
        try {
          await _localStore.saveData(
              _acceptedEksStoreKey, _acceptedHandshakeEks);
        } catch (_) {}
      }
      notifyListeners();
    } finally {
      _deletingChats.remove(chatId);
    }
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

  /// [asContactRequest] schickt eine Kontaktanfrage statt einer Nachricht:
  /// ohne Text, ohne sichtbare Blase, und an der Sendesperre vorbei — sie ist
  /// der einzige Weg, diese Sperre überhaupt aufzulösen.
  Future<void> sendMessage({
    required String chatId,
    required String text,
    Duration? selfDestruct,
    bool burnAfterRead = false,
    String? password,
    bool asContactRequest = false,
    String? qrToken,
  }) async {
    // H1-Proto: serialize concurrent sendMessage calls per chat so the
    // ratchet-encrypt + globalSendSeqNo update happens atomically. Without
    // this, two parallel sends collide on the same chain key and
    // sequence number, the ratchet drops one message and the recipient
    // rejects the other as REPLAY_SEQ.
    return _underSendMutex(chatId, () => _sendMessageLocked(
          chatId: chatId,
          text: text,
          selfDestruct: selfDestruct,
          burnAfterRead: burnAfterRead,
          password: password,
          asContactRequest: asContactRequest,
          qrToken: qrToken,
        ));
  }

  Future<void> _sendMessageLocked({
    required String chatId,
    required String text,
    Duration? selfDestruct,
    bool burnAfterRead = false,
    String? password,
    bool asContactRequest = false,
    String? qrToken,
  }) async {
    // A3: bail out if a deleteChat is already tearing this chat down. Without
    // this, a send started during the delete window can still hit Firestore
    // and re-save state the delete is about to wipe.
    if (_deletingChats.contains(chatId)) return;

    final chatIdx = _chats.indexWhere((c) => c.id == chatId);
    if (chatIdx == -1) return;
    final chat = _chats[chatIdx];
    final contact = contactForId(chat.recipientId);
    if (contact == null || userId == null) return;

    // Centralized trust gate — fail-closed.
    //
    // Eine Kontaktanfrage läuft bewusst daran vorbei: sie ist der einzige Weg,
    // eine Sperre überhaupt aufzulösen. Blockiert bleibt blockiert.
    if (asContactRequest) {
      if (contact.isBlocked) return;
    } else {
      final trustError = _validateSendPermission(contact);
      if (trustError != null) {
        if (kDebugMode) debugPrint('Send blocked: $trustError');
        return;
      }
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

    // If password-protected, validate password strength first, then encrypt.
    // The password-encrypted blob becomes the "content" that travels through E2E.
    // The sender sees the original text; the recipient sees a locked message.
    String contentForTransmission = text;
    if (hasPassword) {
      // Keine Mindestregeln für das Passwort einer einzelnen Nachricht —
      // siehe chat_screen. Argon2id leitet auch aus einem kurzen Passwort
      // einen brauchbaren Schlüssel ab; der Schutz ist ohnehin nur die
      // zweite Schicht über der Ende-zu-Ende-Verschlüsselung.
      //
      // H4-Crypto (audit 2026-05): bind the password-encrypted blob to its
      // cross-device context. NOTE: `chatId` is a per-device local UUID
      // and would not match between sender and recipient — Codex round 1
      // P1. Use stable identifiers that both sides can reproduce:
      // sender UID, recipient UID, message id (sender-generated, carried
      // intact in the envelope). The "pwd-v1|" prefix keeps room for
      // future context format changes.
      contentForTransmission = await _encryption.encryptWithPassword(
        plaintext: text,
        password: password,
        aad: 'pwd-v1|${userId!}|${chat.recipientId}|$messageId',
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

    if (!asContactRequest) {
      _addMessageToChat(chatId, message);
      _updateChatPreview(chatId, hasPassword ? '🔒 Password message' : text, now);
      notifyListeners();
    }

    try {
      // Initialize ratchet for first message if needed
      if (!_ratchetStates.containsKey(chatId)) {
        await _initRatchetAsSender(chatId, contact);
      }

      // Note: an automatic 14-day session-rotation block used to live here
      // (initiating a fresh X3DH whenever `createdAt` exceeded sessionMaxAge).
      // It was removed because the receive path only runs `_initRatchetAsReceiver`
      // when no state exists for the chat, so every aged conversation would
      // lose the next outbound message until one peer manually reset the
      // session. Forward secrecy is already provided per-message by Double
      // Ratchet's chain-key rotation; reintroducing time-based rotation
      // requires a coordinated receiver-side detection of new session headers,
      // which is not yet implemented.

      // ── v3: ALL metadata inside encrypted payload ──
      // The server sees only ratchet protocol fields. Message type,
      // self-destruct, burn-after-read, password flag, sender identity,
      // KT gossip, and delivery token are all encrypted and invisible.
      final state = _ratchetStates[chatId]!;
      final innerPayload = <String, dynamic>{
        '_t': contentForTransmission,
        '_sid': userId!,
        '_seq': state.globalSendSeqNo, // Monotonic sequence for replay protection
        // Kontaktanfrage: trägt keinen Text. Die Markierung liegt innerhalb
        // der Verschlüsselung, der Server sieht sie nicht.
        if (asContactRequest) '_rq': 1,
        // Nachweis, dass der QR-Code wirklich vorlag. Fehlt er, wird die
        // Anfrage ganz normal zur Rückfrage.
        if (asContactRequest && qrToken != null) '_rt': qrToken,
      };
      // Anti-rollback: include previous session ID in first message of new session
      if (state.globalSendSeqNo == 0 && state.previousSessionId != null) {
        innerPayload['_psid'] = state.previousSessionId;
      }
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

      // Delivery token inside encrypted content. The token is a routing
      // identifier only — sender/recipient authenticity comes from the E2E
      // ratchet, not from the token itself.
      try {
        final recipientToken = await _firestore.getDeliveryToken(chat.recipientId);
        if (recipientToken != null) {
          innerPayload['_dt'] = recipientToken;
        }
      } catch (_) {}

      // Encrypt the entire inner payload (metadata + content)
      final payloadMap = await _encryptWithRatchet(chatId, jsonEncode(innerPayload));
      payloadMap['v'] = 3; // v3: server sees only ratchet fields

      // Increment global send sequence number after successful encryption.
      final updatedState = _ratchetStates[chatId]!.copyWith(
        globalSendSeqNo: _ratchetStates[chatId]!.globalSendSeqNo + 1,
      );
      _ratchetStates[chatId] = updatedState;
      await _localStore.saveRatchetState(chatId, updatedState.toMap());

      // H2-Proto: native types (no toString()).
      await _firestore.sendEncryptedMessage(
        senderId: userId!,
        recipientId: chat.recipientId,
        messageId: messageId,
        encryptedPayload: payloadMap,
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

  /// Persist the current unlock-attempt state so rate-limit survives app
  /// restarts. If persistence fails the rate-limit degrades to RAM-only for
  /// this session; log in debug builds so silent regressions are visible.
  Future<void> _persistUnlockAttempts() async {
    try {
      await _localStore.saveUnlockAttempts(_unlockAttempts);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('unlockAttempts persistence failed: $e '
            '— rate-limit is now RAM-only this session');
      }
    }
  }

  /// Remove unlock-attempt entries for the given message IDs and persist.
  /// Called from message/chat deletion paths so the store does not grow
  /// unboundedly with stale entries for messages that no longer exist.
  Future<void> _pruneUnlockAttempts(Iterable<String> messageIds) async {
    var changed = false;
    for (final id in messageIds) {
      if (_unlockAttempts.remove(id) != null) changed = true;
    }
    if (changed) await _persistUnlockAttempts();
  }

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

    // Reject concurrent unlocks on the same message — without this two
    // overlapping failures could both read the same prior counter, compute
    // fails+1, and the later write would clobber the earlier one (undercount).
    if (!_unlockInFlight.add(messageId)) return false;
    try {
      // Rate-limit brute-force attempts on password-protected messages.
      // State persists across app restarts (C3 fix) — restart no longer
      // bypasses the cooldown.
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
          await _persistUnlockAttempts();
        }
      }

      // H4-Crypto: reconstruct the same cross-device AAD the sender used.
      // sender UID + recipient UID + message id are all stable across
      // devices; chatId is NOT (it is a per-device local UUID).
      final plaintext = await _encryption.decryptWithPassword(
        encryptedBase64: msg.decryptedContent ?? '',
        password: password,
        aad: 'pwd-v1|${msg.senderId}|${msg.recipientId}|${msg.id}',
      );

      if (plaintext == null) {
        final current = _unlockAttempts[messageId];
        final fails = (current?.$1 ?? 0) + 1;
        _unlockAttempts[messageId] = (fails, DateTime.now());
        await _persistUnlockAttempts();
        return false;
      }
      // Success: clear attempt tracking
      _unlockAttempts.remove(messageId);
      await _persistUnlockAttempts();

      messages[idx] = msg.copyWith(
        decryptedContent: plaintext,
        passwordUnlocked: true,
      );
      await _localStore.saveMessages(chatId, messages);
      notifyListeners();

      // Notify the sender that we unlocked their message (with jitter).
      // Only if delivery receipts are enabled — unlock is a form of delivery
      // confirmation.
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
    } finally {
      _unlockInFlight.remove(messageId);
    }
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
      _startInboxListenerWithReconnect();
    }
  }

  /// B2: start the inbox stream with automatic reconnect on stream error.
  /// Previously the `onError` handler just logged in debug mode and left
  /// the stream dead — a transient permission or network error would stop
  /// message delivery for the rest of the session with no UI signal.
  /// Exponential backoff prevents tight reconnect loops if the error
  /// recurs (e.g., permissions revoked).
  void _startInboxListenerWithReconnect({int attempt = 0}) {
    if (userId == null) return;
    _inboxSub?.cancel();
    _inboxSub = _firestore.listenForMessages(userId!).listen(
      _handleInbox,
      onError: (e) {
        if (kDebugMode) debugPrint('Inbox error (attempt $attempt): $e');
        // Exponential backoff capped at 60s: 1, 2, 4, 8, 16, 32, 60, 60, ...
        final delaySec = attempt >= 6 ? 60 : (1 << attempt);
        _inboxReconnectTimer?.cancel();
        _inboxReconnectTimer = Timer(Duration(seconds: delaySec), () {
          // Also guard on _isSyncing — a teardown (wipe/logout) between the
          // error and the timer firing must not resurrect the listener.
          if (!_isSyncing || userId == null) return;
          _startInboxListenerWithReconnect(attempt: attempt + 1);
        });
      },
      // B2: reconnect on clean completion while sync is still active. A
      // Firestore rebalance / server restart closes the stream without
      // error; without this the listener stays silently dead for the rest
      // of the session. `_isSyncing` distinguishes an intentional teardown
      // in `_stopSync` from a remote close.
      onDone: () {
        _inboxReconnectTimer?.cancel();
        if (!_isSyncing || userId == null) return;
        _inboxReconnectTimer = Timer(const Duration(seconds: 1), () {
          if (!_isSyncing || userId == null) return;
          _startInboxListenerWithReconnect(attempt: 0);
        });
      },
    );
  }

  Future<void> _handleInbox(QuerySnapshot<Map<String, dynamic>> snapshot) async {
    for (final change in snapshot.docChanges) {
      if (change.type != DocumentChangeType.added) continue;
      final data = change.doc.data();
      if (data == null) continue;

      // Codex review (2026-06, round 2): if processing dies AFTER a heal
      // parked a pending session (e.g. jsonDecode throws on the inner
      // payload), the catch blocks below must drop that pending — `mid`
      // is server-mutable, so a leftover entry could otherwise be
      // committed by a later message carrying the same mid.
      String? pendingHealKey;

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

        // Von jemandem ohne angenommenen Kontakt wird genau eine Sache
        // angenommen: eine Kontaktanfrage ohne Inhalt. Alles andere fliegt
        // weiterhin raus. Siehe docs/KONTAKTANFRAGEN.md.
        final contact = contactForId(senderId);
        if (_onlyAcceptsRequestFrom(contact)) {
          await _receiveContactRequest(
            senderId: senderId,
            messageId: messageId,
            payloadMap: payloadMap,
            docId: change.doc.id,
            existing: contact,
          );
          continue;
        }
        // _onlyAcceptsRequestFrom schliesst null bereits aus — der Analyzer
        // sieht das durch die Funktion hindurch nicht.
        if (contact == null) continue;

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

        // A3: if this chat is being deleted right now, drop the message
        // instead of appending it to a torn-down chat.
        if (_deletingChats.contains(chat.id)) {
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }

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
        pendingHealKey = _healKey(chat.id, messageId);
        final plaintext = await _decryptWithRatchet(
            chat.id, contact, payloadMap, messageId: messageId);

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
          final ctrlAccepted =
              await _processControlMessage(chat.id, contact, innerPayload);
          if (ctrlAccepted) {
            await _finalizeAcceptedMessage(chat.id, messageId, payloadMap);
          } else {
            _discardPendingHeal(chat.id, messageId);
          }
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }

        // Sealed sender validation: authoritative sender MUST be inside
        // the encrypted payload. Without it, the server controls identity.
        final sealedSenderId = innerPayload['_sid'] as String?;
        if (sealedSenderId == null) {
          if (kDebugMode) debugPrint('Rejected message without sealed sender identity');
          _discardPendingHeal(chat.id, messageId);
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }
        if (sealedSenderId != senderId) {
          if (kDebugMode) debugPrint('Sealed sender mismatch: routing=$senderId, sealed=$sealedSenderId');
          _discardPendingHeal(chat.id, messageId);
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }

        // Kontaktanfrage von jemandem, den ich selbst schon angefragt habe:
        // beide sind einverstanden. Sie traegt keinen Inhalt, also entsteht
        // auch keine Blase.
        if (innerPayload['_rq'] == 1) {
          await _applyMutualRequest(contact);
          await _finalizeAcceptedMessage(chat.id, messageId, payloadMap);
          _processedMessageIds.add(messageId);
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }

        // C4+C5: replay/rollback enforcement — advance globalRecvSeqNo and
        // record _psid. Must happen *after* sealed-sender so a forged payload
        // cannot desync our seq counter.
        if (!await _enforceReplayAndRollback(chat.id, innerPayload, version,
            messageId: messageId)) {
          _discardPendingHeal(chat.id, messageId);
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }

        // Message accepted — commit a pending healed session (if this
        // message produced one) and pin its handshake ephemeral. A false
        // return means this was a concurrent duplicate of an already
        // committed re-handshake — reject it.
        if (!await _finalizeAcceptedMessage(chat.id, messageId, payloadMap)) {
          await _firestore.deleteRelayedMessage(userId!, change.doc.id);
          continue;
        }

        // Process Key Transparency gossip from the encrypted payload
        await _processTransparencyGossip(senderId, innerPayload);

        // Extract message metadata from the (now correctly encrypted) inner payload.
        // A2: clamp self-destruct to a sane non-negative range so a malicious
        // sender cannot hide messages instantly (negative Duration = already
        // expired) or overflow timers with int.max.
        var selfDestructMs = innerPayload['_sd'] as int? ??
            (innerPayload['sd'] as int?); // v2 compat
        if (selfDestructMs != null) {
          selfDestructMs = _clampSelfDestructMs(selfDestructMs);
        }
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
          selfDestructDuration:
              selfDestructMs != null ? Duration(milliseconds: selfDestructMs) : null,
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
        if (pendingHealKey != null) _pendingHealCommits.remove(pendingHealKey);
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
        if (pendingHealKey != null) _pendingHealCommits.remove(pendingHealKey);
        if (kDebugMode) debugPrint('Handshake failed on receive: $e');
        try { await _firestore.deleteRelayedMessage(userId!, change.doc.id); } catch (_) {}
      } catch (e) {
        if (pendingHealKey != null) _pendingHealCommits.remove(pendingHealKey);
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
    // See _handleInbox: drop a parked healed session if processing dies
    // after the decrypt — `mid` is server-mutable.
    String? pendingHealKey;
    try {
      final senderId = data['sid'] as String;
      final messageId = data['mid'] as String;
      final payloadMap = Map<String, dynamic>.from(data['p'] as Map);

      final payloadSize = jsonEncode(payloadMap).length;
      if (payloadSize > 65536) {
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }

      // Gleiche Regel wie im Live-Listener — die beiden Pfade sind schon
      // einmal auseinandergelaufen, deshalb dieselbe Funktion.
      final contact = contactForId(senderId);
      if (_onlyAcceptsRequestFrom(contact)) {
        await _receiveContactRequest(
          senderId: senderId,
          messageId: messageId,
          payloadMap: payloadMap,
          docId: doc.id,
          existing: contact,
        );
        return;
      }
      // Siehe Live-Listener: die Einschraenkung auf non-null steckt in
      // _onlyAcceptsRequestFrom, der Analyzer erkennt sie nicht.
      if (contact == null) return;

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

      // A3: mirror the _handleInbox guard — drop messages arriving while
      // this chat is being deleted.
      if (_deletingChats.contains(chat.id)) {
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }

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

      pendingHealKey = _healKey(chat.id, messageId);
      final plaintext = await _decryptWithRatchet(
          chat.id, contact, payloadMap, messageId: messageId);

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
        final ctrlAccepted =
            await _processControlMessage(chat.id, contact, innerPayload);
        if (ctrlAccepted) {
          await _finalizeAcceptedMessage(chat.id, messageId, payloadMap);
        } else {
          _discardPendingHeal(chat.id, messageId);
        }
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }

      // Sealed sender validation
      final sealedSenderId = innerPayload['_sid'] as String?;
      if (sealedSenderId == null) {
        _discardPendingHeal(chat.id, messageId);
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }
      if (sealedSenderId != senderId) {
        _discardPendingHeal(chat.id, messageId);
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }

      // Kontaktanfrage von jemandem, den ich selbst schon angefragt habe:
      // beide sind einverstanden. Sie traegt keinen Inhalt, also entsteht
      // auch keine Blase.
      if (innerPayload['_rq'] == 1) {
        await _applyMutualRequest(contact);
        await _finalizeAcceptedMessage(chat.id, messageId, payloadMap);
        _processedMessageIds.add(messageId);
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }

      // C4+C5: replay/rollback enforcement — same contract as _handleInbox.
      if (!await _enforceReplayAndRollback(chat.id, innerPayload, version,
          messageId: messageId)) {
        _discardPendingHeal(chat.id, messageId);
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }

      // Message accepted — commit pending healed session + pin its ek.
      // False = concurrent duplicate of a committed re-handshake → reject.
      if (!await _finalizeAcceptedMessage(chat.id, messageId, payloadMap)) {
        await _firestore.deleteRelayedMessage(userId!, doc.id);
        return;
      }

      // Process Key Transparency gossip from the encrypted payload
      await _processTransparencyGossip(senderId, innerPayload);

      // Extract metadata from inner payload (v3 keys with v2 compat)
      // A2: see _handleInbox — sanitize attacker-controlled self-destruct.
      var selfDestructMs = innerPayload['_sd'] as int? ??
          (innerPayload['sd'] as int?);
      if (selfDestructMs != null) {
        selfDestructMs = _clampSelfDestructMs(selfDestructMs);
      }
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
        selfDestructDuration:
            selfDestructMs != null ? Duration(milliseconds: selfDestructMs) : null,
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
      if (pendingHealKey != null) _pendingHealCommits.remove(pendingHealKey);
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
      if (pendingHealKey != null) _pendingHealCommits.remove(pendingHealKey);
      if (kDebugMode) debugPrint('Handshake failed on polled receive: $e');
      try { await _firestore.deleteRelayedMessage(userId!, doc.id); } catch (_) {}
    } catch (e) {
      if (pendingHealKey != null) _pendingHealCommits.remove(pendingHealKey);
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

      // Assign session ID for anti-rollback protection.
      final oldState = _ratchetStates[chatId];
      final oldSessionId = oldState?.sessionId;
      // C5: carry forward the set of peer _psid values we've already seen,
      // so a re-handshake doesn't reset our rollback memory.
      final preservedSeenPsids = oldState?.peerSeenPsids ?? const <String>{};
      final newState = session.ratchetState.copyWith(
        sessionId: const Uuid().v4(),
        previousSessionId: oldSessionId,
        peerSeenPsids: preservedSeenPsids,
      );
      _ratchetStates[chatId] = newState;
      await _localStore.saveRatchetState(chatId, newState.toMap());

      // Store the session header for the first message payload. The
      // receiver needs `ek` to perform the mirror X3DH and `spkId` to
      // resolve which signed prekey we derived against (it may already
      // have rotated on their side — previous keys stay valid for 48h).
      _pendingSessionHeaders[chatId] = {
        'ek': base64Encode(session.ephemeralPublicKey),
        'spkId': session.signedPreKeyId,
      };
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

    final rawState = await DoubleRatchet.initAsSender(
      sharedSecret: sharedSecret,
      recipientRatchetPublicKey: contact.publicKey,
    );

    final oldState = _ratchetStates[chatId];
    final oldSessionId = oldState?.sessionId;
    final preservedSeenPsids = oldState?.peerSeenPsids ?? const <String>{};
    final state = rawState.copyWith(
      sessionId: const Uuid().v4(),
      previousSessionId: oldSessionId,
      peerSeenPsids: preservedSeenPsids,
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

  /// Initialize a ratchet session as receiver (first message from them):
  /// derive and commit to memory + disk. The handshake ephemeral is
  /// recorded later by [_finalizeAcceptedMessage] — only messages that
  /// pass all acceptance checks pin their `ek` (Codex review 2026-06).
  Future<void> _initRatchetAsReceiver(
      String chatId, Contact contact, Map<String, dynamic> payloadMap) async {
    final state = await _deriveInboundSessionState(chatId, contact, payloadMap);
    _ratchetStates[chatId] = state;
    await _localStore.saveRatchetState(chatId, state.toMap());
  }

  /// Derive (but do NOT persist) the inbound session state for a first
  /// message. Pure with respect to provider state — used by both the
  /// normal receiver init and the session-heal path, which must only
  /// commit a state that actually decrypts the message.
  Future<RatchetState> _deriveInboundSessionState(
      String chatId, Contact contact, Map<String, dynamic> payloadMap) async {
    final keyPair = await _keyManager.getOrCreateIdentityKeyPair();

    // Extract sender's X3DH ephemeral public key from the first message.
    // Without this, the receiver cannot derive the same shared secret.
    //
    // Headerless legacy (`ek` missing): deliberately NOT treated as an
    // identity-key fallback. It keeps the historical behavior — sender
    // ephemeral substituted with the contact's identity key, mirrored on
    // the bundle/SPK path below. Build 61+ senders always include `ek`
    // on first messages; only the `ek2` marker selects the fallback
    // mirror (sender derived against our identity key).
    final ephKeyB64 = payloadMap['ek'] as String?;
    final senderEphemeralPublic = ephKeyB64 != null
        ? Uint8List.fromList(base64Decode(ephKeyB64))
        : contact.publicKey;

    // Extract second ephemeral key (ek2) for fallback path with 3 independent DH outputs
    final eph2KeyB64 = payloadMap['ek2'] as String?;
    final senderEphemeral2Public = eph2KeyB64 != null
        ? Uint8List.fromList(base64Decode(eph2KeyB64))
        : null;

    // Mirror the sender's derivation. ek2 marks a fallback handshake
    // (sender derived against our IDENTITY key); otherwise the sender used
    // the signed prekey from our published bundle, resolvable via the
    // transmitted spkId even across a rotation. Tolerate junk in spkId —
    // it is untrusted input; an unknown id falls back to the current key.
    final spkIdRaw = payloadMap['spkId'];
    final spkId = spkIdRaw is int ? spkIdRaw : int.tryParse('$spkIdRaw');
    final (signedPreKeyPrivate, signedPreKeyPublic) =
        SessionHandshakeService.resolveInboundHandshakeKeys(
      isFallback: senderEphemeral2Public != null,
      signedPreKeyId: spkId,
      identityKeyPair: keyPair,
      currentSignedPreKey: _preKeyManager.currentSignedPreKey,
      findSignedPreKeyById: _preKeyManager.findSignedPreKey,
    );

    final rawState = await SessionHandshakeService.createInboundSession(
      identityKeyPair: keyPair,
      signedPreKeyPrivate: signedPreKeyPrivate,
      signedPreKeyPublic: signedPreKeyPublic,
      senderIdentityPublic: contact.publicKey,
      senderEphemeralPublic: senderEphemeralPublic,
      senderEphemeral2Public: senderEphemeral2Public,
    );

    final oldState = _ratchetStates[chatId];
    final oldSessionId = oldState?.sessionId;
    // C5: preserve peerSeenPsids across re-init so a forged first-message
    // with a stale _psid cannot pass after the state gets rebuilt.
    final preservedSeenPsids = oldState?.peerSeenPsids ?? const <String>{};
    return rawState.copyWith(
      sessionId: const Uuid().v4(),
      previousSessionId: oldSessionId,
      peerSeenPsids: preservedSeenPsids,
    );
  }

  /// Mark an accepted handshake ephemeral in memory (FIFO-capped).
  ///
  /// Deliberately synchronous: the mark must land in the same event-loop
  /// turn as the session commit that justifies it, so a concurrently
  /// processed duplicate cannot pass its own freshness re-check in
  /// between (Codex review 2026-06, round 4).
  void _markAcceptedHandshakeEk(String chatId, String ekB64) {
    final list = _acceptedHandshakeEks.putIfAbsent(chatId, () => []);
    if (list.contains(ekB64)) return;
    list.add(ekB64);
    if (list.length > _maxAcceptedEksPerChat) {
      list.removeAt(0);
    }
  }

  Future<void> _persistAcceptedEks() async {
    try {
      await _localStore.saveData(_acceptedEksStoreKey, _acceptedHandshakeEks);
    } catch (_) {
      // Guard degrades to RAM-only for this session if persistence fails.
    }
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
  ///
  /// H1-State (audit 2026-05): runs under the per-chat ratchet mutex so
  /// two concurrent receives (listener + polled) cannot both decrypt
  /// against the same chain key and write divergent post-states.
  Future<String> _decryptWithRatchet(
      String chatId, Contact contact, Map<String, dynamic> payloadMap,
      {required String messageId}) {
    return _underRatchetMutex(chatId, () async {
      // Init receiver session if we don't have one yet.
      // Pass payloadMap so the receiver can extract the sender's ephemeral key.
      //
      // B4: on exception during init, scrub BOTH in-memory and on-disk
      // ratchet state. _initRatchetAsReceiver may have persisted a partial
      // state to the store before the exception bubbled up; leaving that
      // behind would let the next startup reload stale state via
      // loadRatchetState and keep re-failing on this peer.
      if (!_ratchetStates.containsKey(chatId)) {
        try {
          await _initRatchetAsReceiver(chatId, contact, payloadMap);
        } catch (e) {
          _ratchetStates.remove(chatId);
          try {
            await _localStore.deleteRatchetState(chatId);
          } catch (_) {}
          rethrow;
        }
      }

      final state = _ratchetStates[chatId];
      if (state == null) {
        throw StateError('Failed to initialize ratchet for chat $chatId');
      }
      final ratchetMsg = RatchetMessage.fromPayloadMap(payloadMap);
      final ad = Uint8List.fromList(utf8.encode(contact.id));

      RatchetState newState;
      Uint8List paddedPlaintext;
      var healed = false;
      try {
        (newState, paddedPlaintext) = await DoubleRatchet.decrypt(
          state: state,
          message: ratchetMsg,
          associatedData: ad,
        );
      } catch (_) {
        // Session heal: the peer may have re-handshaked (state lost on
        // their side — reinstall, key-change reset, one-sided chat
        // delete) while we still hold the old session. Historically the
        // `ek` header was ignored whenever local state existed, so such
        // chats stayed broken forever (every message MAC-failed and was
        // dropped). If this message carries a session header, try it
        // under a freshly derived inbound session.
        final healResult =
            await _tryHealSession(chatId, contact, payloadMap, ratchetMsg, ad);
        if (healResult == null) rethrow;
        (newState, paddedPlaintext) = healResult;
        healed = true;
      }

      if (healed) {
        // Codex review (2026-06, P1): do NOT swap the live session here.
        // The healed state stays pending until this exact message passes
        // sealed-sender + C4/C5 (or control HMAC+counter) acceptance —
        // _finalizeAcceptedMessage commits it, every reject path discards
        // it and the previous session stays live.
        _pendingHealCommits[_healKey(chatId, messageId)] = newState;
      } else {
        _ratchetStates[chatId] = newState;
        await _localStore.saveRatchetState(chatId, newState.toMap());
      }

      // Remove padding — mandatory for all v2 messages.
      final plaintext = EncryptionService.unpadPlaintext(paddedPlaintext);
      final out = utf8.decode(plaintext);
      // H6: best-effort zero of plaintext buffers.
      SensitiveBuffer.zeroBytes(plaintext);
      SensitiveBuffer.zeroBytes(paddedPlaintext);
      return out;
    });
  }

  /// Try to decrypt a message under a session re-derived from its X3DH
  /// header after the existing session failed. Returns the advanced state
  /// and padded plaintext on success, null if the message has no header,
  /// the header was already accepted once (replay of an old first message
  /// — the server controls `mid` and `ek` is outside the message MAC, so
  /// this guard helps stop a stale-session swap), or the derived session
  /// cannot decrypt it either.
  ///
  /// Security: a successful decrypt requires the X3DH mirror over the
  /// contact's pinned identity key — only the genuine contact can produce
  /// a message that passes. NOTHING is committed here: the caller parks
  /// the result in [_pendingHealCommits]; the live session is only
  /// replaced by [_finalizeAcceptedMessage] after the message passes all
  /// acceptance checks, and the accepted `ek` is recorded there too.
  ///
  /// Known residual: if the first and second message of a re-handshake
  /// arrive out of order, the second (header-less) one is dropped before
  /// the heal can run — same loss as before the heal existed.
  Future<(RatchetState, Uint8List)?> _tryHealSession(
    String chatId,
    Contact contact,
    Map<String, dynamic> payloadMap,
    RatchetMessage ratchetMsg,
    Uint8List ad,
  ) async {
    final ekB64 = payloadMap['ek'] as String?;
    if (ekB64 == null) return null;
    final accepted = _acceptedHandshakeEks[chatId];
    if (accepted != null && accepted.contains(ekB64)) return null;

    final RatchetState fresh;
    try {
      fresh = await _deriveInboundSessionState(chatId, contact, payloadMap);
    } catch (_) {
      return null; // Malformed header — keep the old session.
    }
    try {
      return await DoubleRatchet.decrypt(
        state: fresh,
        message: ratchetMsg,
        associatedData: ad,
      );
    } catch (_) {
      return null; // Not decryptable under the new header either.
    }
  }

  /// Commit point for an ACCEPTED inbound message: swaps in the pending
  /// healed session (only the one belonging to exactly this message) and
  /// records the message's handshake ephemeral so a replayed copy can
  /// never re-derive a session later.
  ///
  /// Returns false when a pending heal turned out to be a duplicate of an
  /// already-committed re-handshake (Codex review 2026-06, round 4: the
  /// server can deliver the same first message twice under different
  /// `mid`s; both copies heal and validate against their own pre-accept
  /// snapshots). The freshness re-check + in-memory commit + ek mark all
  /// happen before the first await, so no concurrent task can interleave
  /// between check and commit. On false the caller must reject the
  /// message; the live session stays untouched.
  Future<bool> _finalizeAcceptedMessage(
      String chatId, String messageId, Map<String, dynamic> payloadMap) async {
    final ekRaw = payloadMap['ek'];
    final ekB64 = ekRaw is String ? ekRaw : null;
    final pendingState =
        _pendingHealCommits.remove(_healKey(chatId, messageId));
    if (pendingState != null) {
      if (ekB64 != null &&
          (_acceptedHandshakeEks[chatId]?.contains(ekB64) ?? false)) {
        // A concurrent copy of this re-handshake already committed.
        return false;
      }
      _ratchetStates[chatId] = pendingState;
      if (ekB64 != null) _markAcceptedHandshakeEk(chatId, ekB64);
      await _localStore.saveRatchetState(chatId, pendingState.toMap());
      await _persistAcceptedEks();
      if (kDebugMode) {
        debugPrint('Session healed from re-handshake header (chat $chatId)');
      }
      return true;
    }
    if (ekB64 != null) {
      _markAcceptedHandshakeEk(chatId, ekB64);
      await _persistAcceptedEks();
    }
    return true;
  }

  /// Drop the pending healed session of exactly this message — it was
  /// rejected. The previous (live) session remains untouched; pendings of
  /// other in-flight messages on the same chat are unaffected.
  void _discardPendingHeal(String chatId, String messageId) {
    _pendingHealCommits.remove(_healKey(chatId, messageId));
  }

  /// A2: sanitize self-destruct milliseconds from an untrusted inner payload.
  /// - Returns null (no self-destruct) for non-positive values; a negative
  ///   Duration would expire the message the moment it lands and hide it
  ///   from the UI before the user sees it.
  /// - Caps at 30 days so an adversarial sender cannot overflow timers.
  static int? _clampSelfDestructMs(int raw) {
    if (raw <= 0) return null;
    const maxMs = 30 * 24 * 60 * 60 * 1000; // 30 days
    return raw > maxMs ? maxMs : raw;
  }

  /// C4+C5: replay (_seq) + rollback (_psid) enforcement for v3 payloads.
  ///
  /// Called after successful ratchet decryption and sealed-sender validation.
  /// Returns true if the message should be processed, false if it must be
  /// discarded. On accept, the ratchet state is advanced (`globalRecvSeqNo`,
  /// `peerSeenPsids`) and persisted.
  ///
  /// Intentionally placed *after* sealed-sender so an attacker-injected
  /// ciphertext cannot advance our seq counter; only authenticated peer
  /// messages reach here.
  Future<bool> _enforceReplayAndRollback(
    String chatId,
    Map<String, dynamic> innerPayload,
    int version, {
    String? messageId,
  }) async {
    // If this exact message produced a pending healed session, validate
    // against THAT state: the live state belongs to the dead old session
    // (its peerSeenPsids lineage was carried over during derivation), and
    // the seq/psid bookkeeping must advance the pending state so nothing
    // is lost when _finalizeAcceptedMessage commits it.
    final healKey = messageId != null ? _healKey(chatId, messageId) : null;
    final pendingState =
        healKey != null ? _pendingHealCommits[healKey] : null;

    final state = pendingState ?? _ratchetStates[chatId];
    if (state == null) return true; // no state = session init path, nothing to check
    final result = ReplayGuard.validate(
      state: state,
      innerPayload: innerPayload,
      version: version,
    );
    if (result.rejectReason != null) {
      if (kDebugMode) {
        debugPrint('[replay-guard] rejected: ${result.rejectReason} '
            '(chatId=$chatId, version=$version)');
      }
      return false;
    }
    // Passthrough returns the same state instance (v2). Only persist on change.
    if (result.state != null && !identical(result.state, state)) {
      if (pendingState != null) {
        // Keep the advance pending — committed only on final acceptance.
        _pendingHealCommits[healKey!] = result.state!;
      } else {
        _ratchetStates[chatId] = result.state!;
        await _localStore.saveRatchetState(chatId, result.state!.toMap());
      }
    }
    return true;
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
    await _announceGone();
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
    // B5: disconnect the auto-persist callback BEFORE clear. clear() would
    // otherwise fire onStateChanged → saveControlCounters, which could
    // asynchronously write an empty counter file AFTER _localStore.wipeAll
    // has already deleted the storage directory. On native platforms the
    // save would create the dir again (leaking the fact that a wipe
    // happened / who the user talked to). Nulling the callback keeps the
    // clear purely in-memory; the disk copy is removed by wipeAll below.
    _controlCounter.onStateChanged = null;
    _controlCounter.clear();
    _chats.clear();
    _contacts.clear();
    _messagesByChat.clear();
    _ratchetStates.clear();
    _pendingHealCommits.clear();
    _acceptedHandshakeEks.clear();
    _typingStates.clear();
    _processedMessageIds.clear();
    _unlockAttempts.clear();
    _recordingNotices.clear();
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
    _inboxReconnectTimer?.cancel(); // B2: kill any pending reconnect
    _privacyPolling?.stop();
    _privacyPolling = null;
    _selfDestructTimer?.cancel();
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
