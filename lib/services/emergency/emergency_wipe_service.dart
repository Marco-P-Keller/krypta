import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../firebase/firestore_service.dart';
import '../storage/secure_storage_service.dart';
import '../storage/encrypted_local_store.dart';
import '../../security/key_management/key_manager.dart';

/// Immediate, complete, irreversible data destruction.
///
/// Wipe matrix — every item is wiped in priority order:
///
/// Phase 1 — Local (no network, highest priority):
///   [x] Encrypted local store (chats, messages, contacts, ratchet states)
///   [x] All encryption keys (identity, prekeys, database key)
///   [x] Secure storage (codes, vault password, settings flags)
///   [x] In-memory caches (key manager, provider state)
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

  EmergencyWipeService({
    required SecureStorageService secureStorage,
    required KeyManager keyManager,
    required EncryptedLocalStore localStore,
    required FirestoreService firestore,
    FirebaseAuth? auth,
  })  : _secureStorage = secureStorage,
        _keyManager = keyManager,
        _localStore = localStore,
        _firestore = firestore,
        _auth = auth ?? FirebaseAuth.instance;

  Future<void> wipeEverything() async {
    final userId = _auth.currentUser?.uid;

    // Phase 1: Local wipe (highest priority — no network needed)
    await _wipeLocal();

    // Phase 2: Server cleanup (best effort — don't block on failure)
    await _wipeServer(userId);

    // Phase 3: Auth cleanup
    await _wipeAuth();
  }

  Future<void> _wipeLocal() async {
    // 1. Encrypted local files (chats, messages, contacts, ratchet states, decoy data)
    try {
      await _localStore.wipeAll();
    } catch (e) {
      debugPrint('Wipe local store: $e');
    }

    // 2. All cryptographic keys (identity, prekeys, database key)
    try {
      await _keyManager.deleteAllKeys();
    } catch (e) {
      debugPrint('Wipe keys: $e');
    }

    // 3. Secure storage (hashed codes, vault password hash, settings)
    try {
      await _secureStorage.deleteAll();
    } catch (e) {
      debugPrint('Wipe secure storage: $e');
    }

    // 4. Clear in-memory caches
    _keyManager.clearMemoryCache();
  }

  Future<void> _wipeServer(String? userId) async {
    if (userId == null) return;
    try {
      await _firestore.deleteAllUserData(userId);
    } catch (e) {
      debugPrint('Wipe server data: $e');
    }
  }

  Future<void> _wipeAuth() async {
    try {
      await _auth.currentUser?.delete();
    } catch (_) {}
    try {
      await _auth.signOut();
    } catch (_) {}
  }
}
