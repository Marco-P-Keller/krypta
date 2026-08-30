import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../firebase/firestore_service.dart';
import '../platform/clipboard_helper.dart';
import '../storage/secure_storage_service.dart';
import '../storage/encrypted_local_store.dart';
import '../storage/file_helper.dart' as io;
import '../../security/key_management/key_manager.dart';
import '../../security/prekey/prekey_manager.dart';

/// Immediate, complete, irreversible data destruction.
///
/// Wipe matrix — every item is wiped in priority order:
///
/// Phase 1 — Local (no network, highest priority):
///   [x] Encrypted local store (chats, messages, contacts, ratchet states)
///   [x] All encryption keys (identity, prekeys, database key)
///   [x] PreKey material (signed prekeys, one-time prekeys)
///   [x] Secure storage (codes, vault password, settings flags, fail counters)
///   [x] In-memory caches (key manager, prekey manager state)
///   [x] Cache/temp directories (image cache, HTTP cache, temp files)
///
/// Phase 2 — Server (best effort, non-blocking):
///   [x] Firestore user data (messages, acks, typing, FCM, public keys, prekeys)
///
/// Phase 3 — Auth (best effort):
///   [x] Delete Firebase account
///   [x] Sign out
class EmergencyWipeService {
  final SecureStorageService _secureStorage;
  final KeyManager _keyManager;
  final EncryptedLocalStore _localStore;
  final FirestoreService _firestore;
  final FirebaseAuth _auth;
  final PreKeyManager? _preKeyManager;

  EmergencyWipeService({
    required SecureStorageService secureStorage,
    required KeyManager keyManager,
    required EncryptedLocalStore localStore,
    required FirestoreService firestore,
    PreKeyManager? preKeyManager,
    FirebaseAuth? auth,
  })  : _secureStorage = secureStorage,
        _keyManager = keyManager,
        _localStore = localStore,
        _firestore = firestore,
        _preKeyManager = preKeyManager,
        _auth = auth ?? FirebaseAuth.instance;

  Future<void> wipeEverything() async {
    // Beide Angaben JETZT festhalten. Wer die Loeschung mit einer Frist
    // aufruft und danach weitergeht, laesst den Rest im Hintergrund
    // weiterlaufen - meldet sich bis dahin ein neues anonymes Konto an,
    // wuerde ein spaeter gelesenes `currentUser` genau dieses treffen.
    final user = _auth.currentUser;
    final userId = user?.uid;

    // H3: set a wipe-in-progress marker BEFORE any destructive step so an
    // interrupt (crash, kill, power loss) is detectable on next startup.
    // The marker file lives outside the secure store / encrypted store and
    // survives both wipes.
    try {
      await io.setWipeMarker();
    } catch (_) {}

    // Phase 1: Local wipe (highest priority — no network needed)
    await _wipeLocal();

    // Phase 2: Server cleanup (best effort — don't block on failure)
    await _wipeServer(userId);

    // Phase 3: Auth cleanup
    await _wipeAuth(user);

    // H3: only clear the marker if identity keys are really gone. If
    // deleteAllKeys / secure_storage.deleteAll failed or were interrupted,
    // leftover keys must NOT be reused — leaving the marker set forces fresh
    // key generation on next startup.
    try {
      if (!await _keyManager.hasIdentityKeys()) {
        await io.clearWipeMarker();
      }
    } catch (_) {
      // Verification failed — leave marker set (fail-safe).
    }
  }

  Future<void> _wipeLocal() async {
    // 1. Encrypted local files (chats, messages, contacts, ratchet states)
    try { await _localStore.wipeAll(); } catch (_) {}

    // 2. All cryptographic keys (identity, prekeys, database key)
    try { await _keyManager.deleteAllKeys(); } catch (_) {}

    // 3. PreKey material (signed prekeys, one-time prekeys)
    try { await _preKeyManager?.wipeAll(); } catch (_) {}

    // 4. Secure storage (hashed codes, vault password, settings, fail counters)
    try { await _secureStorage.deleteAll(); } catch (_) {}

    // 5. Clear ALL in-memory caches
    _keyManager.clearMemoryCache();

    // 6. Clear system clipboard (may contain copied messages/keys).
    // M2-Client: also cancel any pending auto-clear so a stale "60 seconds
    // from now" timer cannot wipe a value the user puts there post-wipe.
    try {
      ClipboardHelper.cancelPending();
      await Clipboard.setData(const ClipboardData(text: ''));
    } catch (_) {}

    // 7. Wipe cache/temp directories (image cache, HTTP cache, temp files)
    try { await io.wipeCacheAndTemp(); } catch (_) {}
  }

  Future<void> _wipeServer(String? userId) async {
    if (userId == null) return;
    try { await _firestore.deleteAllUserData(userId); } catch (_) {}
  }

  Future<void> _wipeAuth(User? user) async {
    try {
      await user?.delete();
    } catch (_) {}
    try {
      await _auth.signOut();
    } catch (_) {}
  }
}
