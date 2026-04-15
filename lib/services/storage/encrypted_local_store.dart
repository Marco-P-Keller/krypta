import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants/storage_keys.dart';
import '../../features/messenger/data/models/chat_model.dart';
import '../../features/messenger/data/models/contact_model.dart';
import '../../features/messenger/data/models/message_model.dart';
import '../../security/encryption/encryption_service.dart';
import 'file_helper.dart' as io;

/// Encrypted local data store.
///
/// Native: Data is XChaCha20-Poly1305 encrypted and written to app-private files.
/// Web: Data lives in memory only (no persistence = more secure for web).
/// The encryption key is a random 256-bit key stored in the platform keychain.
class EncryptedLocalStore {
  final EncryptionService _encryption;
  final FlutterSecureStorage _secureStorage;

  Uint8List? _storageKey;
  String? _basePath;
  final Map<String, String> _cache = {};

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

  Future<void> init() async {
    final existingKey = await _secureStorage.read(key: StorageKeys.databaseKey);
    if (existingKey != null) {
      _storageKey = base64Decode(existingKey);
    } else {
      _storageKey = _encryption.generateLocalStorageKey();
      await _secureStorage.write(
        key: StorageKeys.databaseKey,
        value: base64Encode(_storageKey!),
      );
    }

    _basePath = await io.getStorageBasePath();
    await _loadAllFromDisk();
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

  // --- Ratchet State (Double Ratchet per chat) ---

  Future<Map<String, dynamic>?> loadRatchetState(String chatId) async {
    final data = _cache['ratchet_$chatId'];
    if (data == null) return null;
    try {
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRatchetState(String chatId, Map<String, dynamic> state) async {
    final json = jsonEncode(state);
    _cache['ratchet_$chatId'] = json;
    await _encryptAndWrite('ratchet_$chatId', json);
  }

  Future<void> deleteRatchetState(String chatId) async {
    _cache.remove('ratchet_$chatId');
    if (_basePath != null) {
      await io.deleteFileAt('$_basePath/ratchet_$chatId.enc');
    }
  }

  // --- Wipe ---

  Future<void> wipeAll() async {
    _cache.clear();
    _storageKey = null;
    try { await _secureStorage.delete(key: StorageKeys.databaseKey); } catch (_) {}
    if (_basePath != null) {
      try { await io.deleteDirRecursive(_basePath!); } catch (_) {}
    }
  }

  // --- Encrypted I/O ---

  Future<void> _loadAllFromDisk() async {
    if (_basePath == null || _storageKey == null) return;

    final files = await io.listEncFiles(_basePath!);
    for (final filePath in files) {
      final fileName = filePath.split('/').last.replaceAll('.enc', '');
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
        debugPrint('Decrypt $fileName failed: $e');
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
      debugPrint('Encrypt/write $name failed: $e');
    }
  }
}
