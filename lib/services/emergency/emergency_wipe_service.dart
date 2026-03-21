import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../firebase/firestore_service.dart';
import '../storage/secure_storage_service.dart';
import '../storage/encrypted_local_store.dart';
import '../../security/key_management/key_manager.dart';

/// Immediate, complete, irreversible data destruction.
///
/// Wipe sequence (NO confirmation dialog):
/// 1. Delete all local encrypted data files
/// 2. Destroy all encryption keys from keychain
/// 3. Clear secure storage (codes, preferences)
/// 4. Delete user data from Firestore
/// 5. Sign out and delete Firebase account
/// 6. Clear in-memory caches
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

    // Phase 1: Local wipe (highest priority, no network needed)
    await _wipeLocal();

    // Phase 2: Server cleanup (best effort)
    await _wipeServer(userId);

    // Phase 3: Auth cleanup
    await _wipeAuth();
  }

  Future<void> _wipeLocal() async {
    try { await _localStore.wipeAll(); } catch (e) { debugPrint('Wipe local store: $e'); }
    try { await _keyManager.deleteAllKeys(); } catch (e) { debugPrint('Wipe keys: $e'); }
    try { await _secureStorage.deleteAll(); } catch (e) { debugPrint('Wipe secure storage: $e'); }
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
    try { await _auth.currentUser?.delete(); } catch (_) {}
    try { await _auth.signOut(); } catch (_) {}
  }
}
