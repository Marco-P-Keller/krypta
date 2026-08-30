import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants/storage_keys.dart';
import '../../features/messenger/data/models/chat_model.dart';
import '../../features/messenger/data/models/contact_model.dart';
import '../../features/messenger/data/models/message_model.dart';
import '../../security/encryption/encryption_service.dart';
import '../../security/hardware/hardware_security_binding.dart';
import 'file_helper.dart' as io;

/// Encrypted local data store.
///
/// Native: Data is XChaCha20-Poly1305 encrypted and written to app-private files.
/// Web: Data lives in memory only (no persistence = more secure for web).
/// The encryption key is a random 256-bit key stored in the platform keychain.
class EncryptedLocalStore {
  final EncryptionService _encryption;
  final FlutterSecureStorage _secureStorage;
  HardwareSecurityBinding? _hardwareBinding;

  Uint8List? _storageKey;
  String? _basePath;
  final Map<String, String> _cache = {};
  /// B5: generation counter incremented on every `wipeAll`. Writes snapshot
  /// this at entry; if the generation changed before the write commits the
  /// write is abandoned — no resurrection of data an in-flight save was
  /// holding when the user wiped the vault.
  int _generation = 0;
  /// Track last access time for cache entries to enable TTL-based eviction.
  /// Ratchet state entries containing private keys are evicted after [_cacheTtl].
  final Map<String, DateTime> _cacheAccessTime = {};
  static const _cacheTtl = Duration(minutes: 5);
  /// Whether the database key is currently hardware-wrapped.
  bool _isHardwareWrapped = false;
  bool get isHardwareWrapped => _isHardwareWrapped;

  EncryptedLocalStore({
    EncryptionService? encryption,
    FlutterSecureStorage? secureStorage,
  })  : _encryption = encryption ?? EncryptionService(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(),
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
        );

  /// Attach hardware security binding for key wrapping.
  ///
  /// Must be called before [init]. If not called or if hardware binding
  /// is not available, the database key is stored directly in the
  /// platform keychain (current behavior).
  void setHardwareBinding(HardwareSecurityBinding binding) {
    _hardwareBinding = binding;
  }

  Future<void> init() async {
    // Check if we have a hardware-wrapped key first.
    final wrappedKey = await _secureStorage.read(
      key: StorageKeys.databaseKeyWrapped,
    );
    final existingKey = await _secureStorage.read(key: StorageKeys.databaseKey);

    if (wrappedKey != null && _hardwareBinding != null &&
        _hardwareBinding!.isHardwareKeyReady) {
      // Unwrap the database key using hardware security module.
      final unwrapped = await _hardwareBinding!.unwrapKey(
        base64Decode(wrappedKey),
      );
      if (unwrapped != null) {
        _storageKey = unwrapped;
        _isHardwareWrapped = true;
      } else {
        // Hardware unwrap failed (device reset, key deleted).
        // Fall back to the software-stored key if available.
        if (existingKey != null) {
          _storageKey = base64Decode(existingKey);
          if (kDebugMode) {
            debugPrint('Hardware unwrap failed — using software key');
          }
        }
      }
    } else if (existingKey != null) {
      _storageKey = base64Decode(existingKey);

      // Opportunistic migration: if hardware binding just became available,
      // wrap the existing key with hardware and store the wrapped version.
      await _migrateToHardwareWrapping();
    }

    if (_storageKey == null) {
      // First run: generate a new database key.
      _storageKey = _encryption.generateLocalStorageKey();
      await _storeKey(_storageKey!);
    }

    _basePath = await io.getStorageBasePath();
    // H5: recover from a crashed storage-key rotation before loading data.
    // A marker file written during rotateStorageKey tells us whether the
    // keychain had been updated at crash time; without this the load could
    // use a half-rotated main directory.
    await _recoverInterruptedRotation();
    await _loadAllFromDisk();
  }

  /// Store the database key, with hardware wrapping if available.
  Future<void> _storeKey(Uint8List key) async {
    // Always store the software copy as fallback.
    await _secureStorage.write(
      key: StorageKeys.databaseKey,
      value: base64Encode(key),
    );

    // If hardware binding is available, also store wrapped version.
    if (_hardwareBinding != null && _hardwareBinding!.isHardwareKeyReady) {
      final wrapped = await _hardwareBinding!.wrapKey(key);
      if (wrapped != null) {
        await _secureStorage.write(
          key: StorageKeys.databaseKeyWrapped,
          value: base64Encode(wrapped),
        );
        _isHardwareWrapped = true;

        // Remove the software copy — the hardware-wrapped version is
        // now the only way to access the key. The wrapping key never
        // leaves the secure hardware, so the database key is bound
        // to this device's hardware module.
        await _secureStorage.delete(key: StorageKeys.databaseKey);
      }
    }
  }

  /// Migrate an existing software-stored key to hardware wrapping.
  Future<void> _migrateToHardwareWrapping() async {
    if (_hardwareBinding == null || !_hardwareBinding!.isHardwareBindingAvailable) {
      return;
    }

    // Create the hardware wrapping key if not yet done
    final created = await _hardwareBinding!.createHardwareKey();
    if (!created || _storageKey == null) return;

    // Wrap and store
    final wrapped = await _hardwareBinding!.wrapKey(_storageKey!);
    if (wrapped != null) {
      await _secureStorage.write(
        key: StorageKeys.databaseKeyWrapped,
        value: base64Encode(wrapped),
      );
      _isHardwareWrapped = true;

      // Remove the software copy — key is now hardware-bound.
      await _secureStorage.delete(key: StorageKeys.databaseKey);

      if (kDebugMode) {
        debugPrint('Database key migrated to hardware binding');
      }
    }
  }

  // --- Chats ---

  Future<List<Chat>> loadChats() async {
    final data = _cache['chats'];
    if (data == null) return [];
    try {
      final list = jsonDecode(data) as List;
      return list.map((e) => Chat.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveChats(List<Chat> chats) async {
    final json = jsonEncode(chats.map((c) => c.toMap()).toList());
    _cache['chats'] = json;
    await _encryptAndWrite('chats', json);
  }

  // --- Contacts ---

  Future<List<Contact>> loadContacts() async {
    final data = _cache['contacts'];
    if (data == null) return [];
    try {
      final list = jsonDecode(data) as List;
      return list.map((e) => Contact.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveContacts(List<Contact> contacts) async {
    final json = jsonEncode(contacts.map((c) => c.toMap()).toList());
    _cache['contacts'] = json;
    await _encryptAndWrite('contacts', json);
  }

  // --- Messages ---

  Future<List<Message>> loadMessages(String chatId) async {
    final data = _cache['msg_$chatId'];
    if (data == null) return [];
    try {
      final list = jsonDecode(data) as List;
      return list.map((e) => Message.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveMessages(String chatId, List<Message> messages) async {
    final json = jsonEncode(messages.map((m) => m.toMap()).toList());
    _cache['msg_$chatId'] = json;
    await _encryptAndWrite('msg_$chatId', json);
  }

  Future<void> deleteMessages(String chatId) async {
    _cache.remove('msg_$chatId');
    if (_basePath != null) {
      await io.deleteFileAt('$_basePath/msg_$chatId.enc');
    }
  }

  /// A3: sweep `msg_*` and `ratchet_*` files that belong to chats no longer
  /// present in the chat list. A crashed `deleteChat` (or a migrated-in
  /// store) can leave those behind with no owner, wasting disk and
  /// accidentally resurrecting private key material on next load if the
  /// chat id is ever reused.
  /// Prune orphan chat files (msg_*, ratchet_*) whose chat id is not in
  /// [knownChatIds].
  ///
  /// H1-Storage (audit 2026-05): the previous implementation would happily
  /// delete every msg_/ratchet_ file when called with an empty
  /// `knownChatIds` set. The boot path calls this with
  /// `_chats.map((c) => c.id).toSet()`, and `loadChats()` returns `[]`
  /// both when the user truly has no chats AND when `chats.enc`
  /// decryption fails. A single transient decrypt failure (rotation
  /// crash window, hardware-key transient unwrap failure, etc.) would
  /// therefore wipe ALL sessions on disk. We require the caller to also
  /// pass a `chatsListIsTrustworthy` flag — true only when loadChats was
  /// known to have succeeded (or is verifiably empty due to first-run).
  /// When the flag is false, we no-op rather than risk catastrophic data
  /// loss; the orphan files stay around until a known-good prune pass.
  Future<void> pruneOrphanChatFiles(
    Set<String> knownChatIds, {
    required bool chatsListIsTrustworthy,
  }) async {
    if (_basePath == null) return;
    if (!chatsListIsTrustworthy) {
      if (kDebugMode) {
        debugPrint('pruneOrphanChatFiles: skipped — caller flagged chats list as not trustworthy');
      }
      return;
    }
    final enc = await io.listEncFiles(_basePath!);
    for (final filePath in enc) {
      final name = filePath.split(RegExp(r'[\\/]')).last;
      if (!name.endsWith('.enc')) continue;
      final base = name.substring(0, name.length - 4); // strip .enc
      String? chatId;
      if (base.startsWith('msg_')) {
        chatId = base.substring(4);
      } else if (base.startsWith('ratchet_')) {
        chatId = base.substring(8);
      }
      if (chatId == null || knownChatIds.contains(chatId)) continue;
      _cache.remove(base);
      _cacheAccessTime.remove(base);
      try {
        await io.deleteFileAt(filePath);
      } catch (_) {}
    }
  }

  /// Reports whether the persisted `chats.enc` blob exists on disk.
  ///
  /// Codex audit-2026-05 R(Run4) P1: this MUST check the filesystem, not
  /// `_cache`. `_cache` is populated only on successful decrypt; a decrypt
  /// failure leaves the cache empty even though the file is present, and
  /// the boot path would then mistake "load failed" for "first run" and
  /// prune all sessions.
  Future<bool> hasPersistedChatsBlob() async {
    if (_basePath == null) return false;
    try {
      final bytes = await io.readFileBytes('$_basePath/chats.enc');
      return bytes != null;
    } catch (_) {
      return false;
    }
  }

  // --- Generic Key-Value (PreKey-Zustand, Key-Transparency-Pins, ...) ---
  //
  // Hiess einmal `loadDecoyData`/`saveDecoyData` und trug damit den Namen des
  // Tarn-Messengers, obwohl darueber laengst der PreKey-Zustand und die
  // Key-Transparency-Pins liefen. Beim Ausbau des Tarnmodus stand genau
  // deshalb die Falle im Weg, das hier mitzuloeschen.

  /// Load generic encrypted data by key.
  Future<dynamic> loadData(String key) async {
    final data = _cache[key];
    if (data == null) return null;
    try {
      return jsonDecode(data);
    } catch (_) {
      return null;
    }
  }

  /// Save generic encrypted data by key.
  Future<void> saveData(String key, dynamic data) async {
    final json = jsonEncode(data);
    _cache[key] = json;
    await _encryptAndWrite(key, json);
  }

  /// Loescht die Dateien des ausgebauten Tarn-Messengers: `decoy_chats` und
  /// jede `decoy_msg_*`-Datei. Gibt zurueck, wie viele weg sind.
  ///
  /// Gefiltert wird ueber das Praefix `decoy_` im Dateinamen. Der allgemeine
  /// Schluessel-Wert-Speicher ist davon nicht betroffen: dessen Schluessel
  /// heissen `prekey_state`, `kt_pin_*` und dergleichen — die Aehnlichkeit lag
  /// nur im frueheren Methodennamen, nie in den Dateien.
  Future<int> purgeLegacyDecoyFiles() async {
    // Kein stilles 0: waere der Speicher noch nicht bereit, wuerde der
    // Aufraeumlauf "nichts gefunden" melden, sich das merken und die Reste
    // fuer immer liegen lassen. Werfen heisst: naechster Start versucht es.
    if (_basePath == null) {
      throw StateError('purgeLegacyDecoyFiles vor der Initialisierung');
    }
    var geloescht = 0;
    final enc = await io.listEncFiles(_basePath!);
    for (final filePath in enc) {
      final name = filePath.split(RegExp(r'[\/]')).last;
      if (!name.endsWith('.enc')) continue;
      final base = name.substring(0, name.length - 4);
      if (!base.startsWith('decoy_')) continue;
      _cache.remove(base);
      _cacheAccessTime.remove(base);
      await io.deleteFileAt(filePath);
      geloescht++;
    }
    return geloescht;
  }

  // --- Ratchet State (Double Ratchet per chat) ---

  Future<Map<String, dynamic>?> loadRatchetState(String chatId) async {
    final key = 'ratchet_$chatId';
    _cacheAccessTime[key] = DateTime.now();
    final data = _cache[key];
    if (data == null) {
      // Re-read from disk if evicted from cache
      if (_basePath != null) {
        try {
          final encrypted = await io.readFileBytes('$_basePath/$key.enc');
          if (encrypted != null) {
            // H2-Crypto (audit 2026-05): bind ciphertext to its storage
            // slot so a file swap on disk cannot mix chats.
            final decrypted = await _encryption.decryptLocal(
              encrypted: encrypted,
              key: _storageKey!,
              aad: key,
            );
            final json = utf8.decode(decrypted);
            // H6: best-effort zero of the plaintext byte buffer. The
            // resulting String is still in memory but the raw bytes
            // (which include base64 private keys for ratchet_* files)
            // are cleared.
            _zeroIfMutable(decrypted);
            _cache[key] = json;
            // H2-Crypto Codex R10 P1: auto-migrate legacy v1 blobs to v2 so
            // the AAD binding becomes effective immediately, not only after
            // the next save / key rotation. Best-effort: failures are
            // ignored — the read already succeeded and we'll retry on the
            // next access.
            if (!EncryptionService.isLocalV2Format(encrypted)) {
              try {
                final reEnc = await _encryption.encryptLocal(
                  plaintext: Uint8List.fromList(utf8.encode(json)),
                  key: _storageKey!,
                  aad: key,
                );
                await io.writeFileBytes('$_basePath/$key.enc', reEnc);
              } catch (_) {/* best-effort migration */}
            }
            return jsonDecode(json) as Map<String, dynamic>;
          }
        } catch (_) {}
      }
      return null;
    }
    try {
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRatchetState(String chatId, Map<String, dynamic> state) async {
    final key = 'ratchet_$chatId';
    final json = jsonEncode(state);
    _cache[key] = json;
    _cacheAccessTime[key] = DateTime.now();
    await _encryptAndWrite(key, json);
  }

  Future<void> deleteRatchetState(String chatId) async {
    final key = 'ratchet_$chatId';
    _cache.remove(key);
    _cacheAccessTime.remove(key);
    if (_basePath != null) {
      await io.deleteFileAt('$_basePath/$key.enc');
    }
  }

  /// Evict stale ratchet state entries from the in-memory cache.
  ///
  /// Should be called periodically (e.g. on app lifecycle events).
  /// Ratchet states contain private keys (base64-encoded in JSON) and
  /// should not live in memory longer than necessary.
  ///
  /// Note: Dart `String` objects are immutable and cannot be zeroed.
  /// Removing from `_cache` allows GC to collect them. This is best-effort —
  /// the string bytes may linger in GC heap until collected.
  void evictStaleCacheEntries() {
    final now = DateTime.now();
    final staleKeys = <String>[];
    for (final entry in _cacheAccessTime.entries) {
      if (entry.key.startsWith('ratchet_') &&
          now.difference(entry.value) > _cacheTtl) {
        staleKeys.add(entry.key);
      }
    }
    for (final key in staleKeys) {
      _cache.remove(key);
      _cacheAccessTime.remove(key);
    }
  }

  // --- Unlock Attempt Persistence (C3 fix: survive app restarts) ---

  static const _unlockAttemptsKey = 'unlock_attempts';

  /// Load per-message unlock failure counts + last-attempt timestamps so the
  /// rate-limit on password-protected messages survives app restarts.
  /// Returns null if nothing has been saved yet.
  Future<Map<String, (int, DateTime)>?> loadUnlockAttempts() async {
    final data = _cache[_unlockAttemptsKey];
    if (data == null) return null;
    try {
      final raw = jsonDecode(data) as Map<String, dynamic>;
      return raw.map((k, v) {
        final entry = v as Map<String, dynamic>;
        return MapEntry(
          k,
          (
            entry['f'] as int,
            DateTime.fromMillisecondsSinceEpoch(entry['t'] as int),
          ),
        );
      });
    } catch (_) {
      return null;
    }
  }

  /// Persist unlock failure state. Serialization uses short keys (`f` = fails,
  /// `t` = timestamp ms) to keep payload tight.
  Future<void> saveUnlockAttempts(Map<String, (int, DateTime)> attempts) async {
    final raw = attempts.map((k, v) => MapEntry(k, {
          'f': v.$1,
          't': v.$2.millisecondsSinceEpoch,
        }));
    final json = jsonEncode(raw);
    _cache[_unlockAttemptsKey] = json;
    await _encryptAndWrite(_unlockAttemptsKey, json);
  }

  // --- Control Message Counter Persistence ---

  static const _controlCounterKey = 'control_counters';

  Future<Map<String, dynamic>?> loadControlCounters() async {
    final data = _cache[_controlCounterKey];
    if (data == null) return null;
    try {
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveControlCounters(Map<String, dynamic> state) async {
    final json = jsonEncode(state);
    _cache[_controlCounterKey] = json;
    await _encryptAndWrite(_controlCounterKey, json);
  }

  // --- Replay Protection (processed message IDs) ---

  static const _processedIdsKey = 'processed_ids';

  /// Load persisted processed message IDs for replay prevention.
  Future<Set<String>> loadProcessedIds() async {
    final data = _cache[_processedIdsKey];
    if (data == null) return {};
    try {
      final list = jsonDecode(data) as List<dynamic>;
      return list.cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  /// Persist processed message IDs with timestamps for expiry-based pruning.
  /// IDs older than 30 days are pruned to bound storage while maintaining
  /// replay protection within the relevant window.
  Future<void> saveProcessedIds(Set<String> ids) async {
    // Load existing timestamps or create new map
    Map<String, int> timestamped = {};
    final existingData = _cache['${_processedIdsKey}_ts'];
    if (existingData != null) {
      try {
        final map = jsonDecode(existingData) as Map<String, dynamic>;
        timestamped = map.map((k, v) => MapEntry(k, v as int));
      } catch (_) {}
    }

    // Add new IDs with current timestamp
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final id in ids) {
      timestamped.putIfAbsent(id, () => now);
    }

    // Prune entries older than 30 days
    final cutoff = now - const Duration(days: 30).inMilliseconds;
    timestamped.removeWhere((_, ts) => ts < cutoff);

    // Hard cap at 50000 — remove oldest by timestamp if still too large
    if (timestamped.length > 50000) {
      final sorted = timestamped.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final keep = sorted.sublist(sorted.length - 50000);
      timestamped = Map.fromEntries(keep);
    }

    // Save timestamped map
    final tsJson = jsonEncode(timestamped);
    _cache['${_processedIdsKey}_ts'] = tsJson;
    await _encryptAndWrite('${_processedIdsKey}_ts', tsJson);

    // Save ID set (for backward compat with loadProcessedIds)
    final capped = timestamped.keys.toSet();
    final json = jsonEncode(capped.toList());
    _cache[_processedIdsKey] = json;
    await _encryptAndWrite(_processedIdsKey, json);
  }

  // --- Key Rotation ---

  /// Re-encrypt all local data with a new storage key.
  ///
  /// Crash-safe flow (H5):
  /// 0. Write marker with phase=0 (temp-writing). A crash here is benign —
  ///    old keychain + old main dir are still consistent.
  /// 1. Write all re-encrypted files to a temp directory.
  /// 2. Update the marker to phase=1 (rollforward) and swap the keychain to
  ///    the new key. From here on, the only consistent recovery is to
  ///    complete the rollforward (phase=0 would lose data).
  /// 3. Copy each temp file into the main directory.
  /// 4. Delete the marker and the temp directory.
  ///
  /// On next init `_recoverInterruptedRotation` reads the marker and either
  /// discards the temp dir (phase=0) or finishes the rollforward (phase=1).
  ///
  /// Call only when the app is in the foreground and has battery.
  Future<bool> rotateStorageKey() async {
    if (_storageKey == null || _basePath == null) return false;

    final oldKey = _storageKey!;
    final newKey = _encryption.generateLocalStorageKey();
    final tempPath = '${_basePath!}_rotation_tmp';
    final markerPath = '$_basePath/$_rotationMarkerFileName';

    // Track which side of the keychain swap we crossed. The catch path uses
    // this to decide whether rollback is safe (phase 0) or whether we MUST
    // leave the marker + temp for the next init to roll forward (phase 1).
    var reachedRollforward = false;

    try {
      await io.createDir(tempPath);

      // Phase 0: mark rotation as started (temp-writing phase).
      await io.writeFileBytes(markerPath, Uint8List.fromList([0]));

      // Phase 1: Write re-encrypted files to temp directory
      for (final entry in _cache.entries) {
        final plaintext = Uint8List.fromList(utf8.encode(entry.value));
        // H2-Crypto: bind to slot. Rotation re-encrypts under the new key
        // and (if not yet) upgrades each blob to v2 with AAD.
        final encrypted = await _encryption.encryptLocal(
          plaintext: plaintext,
          key: newKey,
          aad: entry.key,
        );
        await io.writeFileBytes('$tempPath/${entry.key}.enc', encrypted);
      }

      // Phase 2: swap the keychain, then flip the marker to rollforward.
      // With this order every phase=1 marker on disk guarantees that
      // `_storeKey(newKey)` completed, so `_recoverInterruptedRotation` can
      // safely roll forward without re-checking the keychain.
      //
      // Documented residual availability risk: a crash DURING `_storeKey`
      // (between software-key write and hardware-wrapped write) leaves the
      // marker at phase=0 so next init discards temp. If the keychain is
      // already partially swapped, decryption of old main files may fail.
      // Security invariants are preserved (no wrong-plaintext mis-decrypt);
      // recovery is manual re-setup. Accepted tradeoff — making this fully
      // atomic would require keychain transactions which FlutterSecureStorage
      // does not expose.
      _storageKey = newKey;
      await _storeKey(newKey);
      await io.writeFileBytes(markerPath, Uint8List.fromList([1]));
      reachedRollforward = true;

      // Phase 3: copy temp → main.
      for (final entry in _cache.entries) {
        final tempFile = '$tempPath/${entry.key}.enc';
        final mainFile = '$_basePath/${entry.key}.enc';
        final bytes = await io.readFileBytes(tempFile);
        if (bytes != null) {
          await io.writeFileBytes(mainFile, bytes);
        }
      }

      // Phase 4: cleanup marker + temp.
      try { await io.deleteFileAt(markerPath); } catch (_) {}
      try { await io.deleteDirRecursive(tempPath); } catch (_) {}

      return true;
    } catch (e) {
      if (reachedRollforward) {
        // Past the keychain swap — a partial copy may have already mixed
        // new-key and old-key files in main. The ONLY safe recovery is to
        // let the next init's _recoverInterruptedRotation finish the copy
        // using the temp dir. Leave marker + temp in place; do NOT roll the
        // keychain back (the hardware-wrapped path may already have the new
        // wrapped key and discarding temp would leave unreadable files).
        if (kDebugMode) {
          debugPrint('Key rotation interrupted post-keychain swap — '
              'deferring recovery to next init');
        }
        return false;
      }
      // Pre-keychain-swap failure: old key is still authoritative, temp
      // files are new-key encrypted and useless. Safe to discard both.
      _storageKey = oldKey;
      try {
        await _secureStorage.write(
          key: StorageKeys.databaseKey,
          value: base64Encode(oldKey),
        );
      } catch (_) {}
      try { await io.deleteFileAt(markerPath); } catch (_) {}
      try { await io.deleteDirRecursive(tempPath); } catch (_) {}
      if (kDebugMode) debugPrint('Key rotation failed (pre-swap)');
      return false;
    }
  }

  /// Filename of the rotation-in-progress marker under [_basePath].
  static const _rotationMarkerFileName = '.rotation_in_progress';

  /// H5: resume or discard a rotation that crashed mid-way.
  ///
  /// - No marker: nothing to do.
  /// - Marker with phase=0 (temp-writing): keychain still holds the OLD key
  ///   and main files are OLD-key encrypted. Discard temp and marker; state
  ///   is internally consistent.
  /// - Marker with phase=1 (rollforward): keychain holds the NEW key. Any
  ///   main-dir file that is still OLD-key encrypted must be replaced from
  ///   its temp counterpart; we copy every available temp file into main to
  ///   reach a consistent NEW-key state, then delete marker + temp.
  Future<void> _recoverInterruptedRotation() async {
    if (_basePath == null) return;
    final markerPath = '$_basePath/$_rotationMarkerFileName';
    final tempPath = '${_basePath!}_rotation_tmp';

    final markerBytes = await io.readFileBytes(markerPath);
    if (markerBytes == null) return;

    final phase = markerBytes.isEmpty ? 0 : markerBytes[0];

    if (phase == 1) {
      // Rollforward: temp files are authoritative, keychain already swapped.
      final tempFiles = await io.listEncFiles(tempPath);
      for (final tempFile in tempFiles) {
        final name = tempFile.split(RegExp(r'[\\/]')).last;
        final mainFile = '$_basePath/$name';
        final bytes = await io.readFileBytes(tempFile);
        if (bytes != null) {
          await io.writeFileBytes(mainFile, bytes);
        }
      }
      if (kDebugMode) {
        debugPrint('Recovered interrupted rotation: rolled forward '
            '${tempFiles.length} files');
      }
    } else if (kDebugMode) {
      debugPrint('Recovered interrupted rotation: discarded pre-keychain temp');
    }

    try { await io.deleteFileAt(markerPath); } catch (_) {}
    try { await io.deleteDirRecursive(tempPath); } catch (_) {}
  }

  // --- Wipe ---

  Future<void> wipeAll() async {
    // B5: bump the generation so any _encryptAndWrite currently mid-flight
    // aborts when it tries to commit — prevents an async save from
    // recreating the storage directory after wipe.
    _generation++;
    _cache.clear();
    _storageKey = null;
    _isHardwareWrapped = false;
    try { await _secureStorage.delete(key: StorageKeys.databaseKey); } catch (_) {}
    try { await _secureStorage.delete(key: StorageKeys.databaseKeyWrapped); } catch (_) {}
    // Delete the hardware wrapping key — makes any remaining wrapped data
    // permanently inaccessible since the hardware key is non-extractable.
    if (_hardwareBinding != null) {
      try { await _hardwareBinding!.deleteHardwareKey(); } catch (_) {}
    }
    // Resolve the storage directory even if init() never ran (the recovery
    // path in main.dart calls wipeAll() before init to mop up after an
    // interrupted emergency wipe).
    String? basePath = _basePath;
    if (basePath == null) {
      try {
        basePath = await io.getStorageBasePath();
      } catch (_) {
        basePath = null;
      }
    }
    if (basePath != null) {
      try { await io.deleteDirRecursive(basePath); } catch (_) {}
    }
  }

  // --- Encrypted I/O ---

  /// H6: best-effort zero of a decrypted plaintext buffer. Called after the
  /// bytes have been consumed by `utf8.decode`. A crypto library may return
  /// a const/immutable `List<int>`, so failures are swallowed — this is a
  /// defense-in-depth step, not a guarantee.
  static void _zeroIfMutable(List<int> bytes) {
    try {
      if (bytes is Uint8List) {
        for (var i = 0; i < bytes.length; i++) {
          bytes[i] = 0;
        }
      }
    } catch (_) {}
  }


  /// Load all non-sensitive data from disk at init.
  ///
  /// Ratchet states (containing private keys) are NOT loaded eagerly.
  /// They are loaded on-demand via [loadRatchetState] to minimize the
  /// window where private keys exist in memory.
  Future<void> _loadAllFromDisk() async {
    if (_basePath == null || _storageKey == null) return;

    final files = await io.listEncFiles(_basePath!);
    for (final filePath in files) {
      // Codex audit-2026-05 P2: normalize path separators so Windows-style
      // backslash paths produce the same slot name as Unix forward-slash
      // paths. Previously the AAD bound at write time ("name") would not
      // match the AAD derived at read time ("C:\path\to\name"), and
      // _loadAllFromDisk would silently drop those entries.
      final normalized = filePath.replaceAll('\\', '/');
      final fileName = normalized.split('/').last.replaceAll('.enc', '');

      // Skip ratchet states — they contain private keys and are loaded
      // on-demand only when a chat session is active.
      if (fileName.startsWith('ratchet_')) continue;

      try {
        final encrypted = await io.readFileBytes(filePath);
        if (encrypted != null) {
          // H2-Crypto: AAD = file/slot name.
          final decrypted = await _encryption.decryptLocal(
            encrypted: encrypted,
            key: _storageKey!,
            aad: fileName,
          );
          _cache[fileName] = utf8.decode(decrypted);
          // H6: see loadRatchetState — best-effort wipe of raw plaintext.
          _zeroIfMutable(decrypted);
          // H2-Crypto Codex R10 P1: opportunistic migration legacy → v2.
          if (!EncryptionService.isLocalV2Format(encrypted)) {
            try {
              final reEnc = await _encryption.encryptLocal(
                plaintext: Uint8List.fromList(utf8.encode(_cache[fileName]!)),
                key: _storageKey!,
                aad: fileName,
              );
              await io.writeFileBytes(filePath, reEnc);
            } catch (_) {/* best-effort */}
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Decrypt failed for local store entry');
      }
    }
  }

  Future<void> _encryptAndWrite(String name, String data) async {
    if (_basePath == null || _storageKey == null) return;
    // B5: snapshot the generation at entry. If `wipeAll` (or a re-init)
    // bumps it while we encrypt/write, abandon the write — otherwise an
    // in-flight save started before the wipe could re-create the storage
    // directory after the user cleared the vault.
    final gen = _generation;

    try {
      final plaintext = Uint8List.fromList(utf8.encode(data));
      // H2-Crypto: bind ciphertext to its storage slot via AAD.
      final encrypted = await _encryption.encryptLocal(
        plaintext: plaintext,
        key: _storageKey!,
        aad: name,
      );
      if (_generation != gen) return; // superseded by wipe/reinit
      if (_basePath == null || _storageKey == null) return;
      await io.writeFileBytes('$_basePath/$name.enc', encrypted);
    } catch (e) {
      if (kDebugMode) debugPrint('Encrypt/write failed for local store entry');
    }
  }
}
