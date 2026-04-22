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

  // --- Decoy Data (separate namespace for fake messenger) ---

  Future<dynamic> loadDecoyData(String key) async {
    final data = _cache[key];
    if (data == null) return null;
    try {
      return jsonDecode(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDecoyData(String key, dynamic data) async {
    final json = jsonEncode(data);
    _cache[key] = json;
    await _encryptAndWrite(key, json);
  }

  // --- Generic Key-Value (used by Key Transparency logs, etc.) ---

  /// Load generic encrypted data by key.
  Future<dynamic> loadData(String key) async => loadDecoyData(key);

  /// Save generic encrypted data by key.
  Future<void> saveData(String key, dynamic data) async =>
      saveDecoyData(key, data);

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
            final decrypted = await _encryption.decryptLocal(
              encrypted: encrypted,
              key: _storageKey!,
            );
            final json = utf8.decode(decrypted);
            _cache[key] = json;
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
  /// Atomic flow:
  /// 1. Generate new key
  /// 2. Write all re-encrypted files to a temporary directory
  /// 3. Only after ALL files succeed: swap temp → main and update keychain
  /// 4. Clean up the old directory
  ///
  /// If interrupted at any point before step 3, the original data remains intact.
  /// Call only when the app is in the foreground and has battery.
  Future<bool> rotateStorageKey() async {
    if (_storageKey == null || _basePath == null) return false;

    final oldKey = _storageKey!;
    final newKey = _encryption.generateLocalStorageKey();
    final tempPath = '${_basePath!}_rotation_tmp';

    try {
      // Phase 1: Write re-encrypted files to temp directory
      await io.createDir(tempPath);

      for (final entry in _cache.entries) {
        final plaintext = Uint8List.fromList(utf8.encode(entry.value));
        final encrypted = await _encryption.encryptLocal(
          plaintext: plaintext,
          key: newKey,
        );
        await io.writeFileBytes('$tempPath/${entry.key}.enc', encrypted);
      }

      // Phase 2: Atomic swap — delete old, rename temp to main
      // Store the new key BEFORE removing old files (safer: if we crash here,
      // we still have the temp dir with new-key-encrypted data)
      _storageKey = newKey;
      await _storeKey(newKey);

      // Remove old directory and rename temp to main
      final oldBackupPath = '${_basePath!}_rotation_old';
      try { await io.deleteDirRecursive(oldBackupPath); } catch (_) {}

      // Rename current → backup, temp → current
      // We copy temp files to main and then clean up (dart:io rename
      // doesn't work across filesystems, and we're in app-private storage)
      for (final entry in _cache.entries) {
        final tempFile = '$tempPath/${entry.key}.enc';
        final mainFile = '$_basePath/${entry.key}.enc';
        final bytes = await io.readFileBytes(tempFile);
        if (bytes != null) {
          await io.writeFileBytes(mainFile, bytes);
        }
      }

      // Phase 3: Clean up temp directory
      try { await io.deleteDirRecursive(tempPath); } catch (_) {}

      return true;
    } catch (e) {
      // Rollback: restore old key, clean up temp
      _storageKey = oldKey;
      try {
        await _secureStorage.write(
          key: StorageKeys.databaseKey,
          value: base64Encode(oldKey),
        );
      } catch (_) {}
      try { await io.deleteDirRecursive(tempPath); } catch (_) {}
      if (kDebugMode) debugPrint('Key rotation failed');
      return false;
    }
  }

  // --- Wipe ---

  Future<void> wipeAll() async {
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
    if (_basePath != null) {
      try { await io.deleteDirRecursive(_basePath!); } catch (_) {}
    }
  }

  // --- Encrypted I/O ---

  /// Load all non-sensitive data from disk at init.
  ///
  /// Ratchet states (containing private keys) are NOT loaded eagerly.
  /// They are loaded on-demand via [loadRatchetState] to minimize the
  /// window where private keys exist in memory.
  Future<void> _loadAllFromDisk() async {
    if (_basePath == null || _storageKey == null) return;

    final files = await io.listEncFiles(_basePath!);
    for (final filePath in files) {
      final fileName = filePath.split('/').last.replaceAll('.enc', '');

      // Skip ratchet states — they contain private keys and are loaded
      // on-demand only when a chat session is active.
      if (fileName.startsWith('ratchet_')) continue;

      try {
        final encrypted = await io.readFileBytes(filePath);
        if (encrypted != null) {
          final decrypted = await _encryption.decryptLocal(
            encrypted: encrypted,
            key: _storageKey!,
          );
          _cache[fileName] = utf8.decode(decrypted);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Decrypt failed for local store entry');
      }
    }
  }

  Future<void> _encryptAndWrite(String name, String data) async {
    if (_basePath == null || _storageKey == null) return;

    try {
      final plaintext = Uint8List.fromList(utf8.encode(data));
      final encrypted = await _encryption.encryptLocal(
        plaintext: plaintext,
        key: _storageKey!,
      );
      await io.writeFileBytes('$_basePath/$name.enc', encrypted);
    } catch (e) {
      if (kDebugMode) debugPrint('Encrypt/write failed for local store entry');
    }
  }
}
