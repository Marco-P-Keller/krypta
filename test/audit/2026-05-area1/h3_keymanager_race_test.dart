// Audit 2026-05 / Run 1 (Cryptography) — Finding H3-Crypto.
//
// Schwachstelle:
//   `KeyManager.getOrCreateIdentityKeyPair()` reads storage, generates a
//   key, then writes — all with `await` boundaries. Two concurrent callers
//   (e.g. setup_screen.dart + messenger_provider.dart on app boot) can
//   interleave their reads → both see no key → both generate → both write
//   → last write wins on disk while one of them caches the loser. Identity
//   pair in cache vs. on disk silently diverges; on next boot the disk
//   value is loaded, so the device now uses a different identity than what
//   was visible to whatever code accessed the cache between the divergent
//   write and reboot.
//
// Fix:
//   Single-flight gate: while one call is in progress, every other caller
//   awaits the same future and observes the same key pair / single write.
//
// PoC-Status (vor Fix):
//   Test A — RED  (two parallel calls produce two different keys)
//
// PoC-Status (nach Fix):
//   Test A — GREEN (two parallel calls share a single generated key)

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/core/constants/storage_keys.dart';
import 'package:kryptaapp/security/key_management/key_manager.dart';

/// Minimal in-memory mock of FlutterSecureStorage used for race testing.
///
/// Each operation yields once via `Future<void>.delayed(Duration.zero)` so
/// the event loop can schedule a competing caller in the gap between
/// read and write — the same property a real keychain plugin exhibits when
/// its method-channel call yields control.
class _RaceFakeStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  Future<void> _yield() => Future<void>.delayed(Duration.zero);

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _yield();
    return _data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _yield();
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _yield();
    _data.remove(key);
  }

  // We don't use these in the H3 test path; throw clearly if accidentally
  // invoked so the test surface stays narrow.
  @override
  noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
        '_RaceFakeStorage: ${invocation.memberName} not implemented');
  }
}

void main() {
  group('H3-Crypto: KeyManager identity-pair race', () {
    test(
        'A — concurrent getOrCreateIdentityKeyPair calls return the same key '
        'and produce a single storage write', () async {
      final storage = _RaceFakeStorage();
      final mgr = KeyManager(storage: storage);

      // Fire two concurrent calls in the same microtask window — exactly
      // what happens on app boot when two init paths both need the
      // identity key.
      final results = await Future.wait([
        mgr.getOrCreateIdentityKeyPair(),
        mgr.getOrCreateIdentityKeyPair(),
      ]);

      // Both callers must observe the SAME key pair. Pre-fix this fails
      // because each call independently runs read→generate→write and the
      // last writer wins on disk while the loser's cached pair diverges.
      expect(
        results[0].privateKeyBase64,
        equals(results[1].privateKeyBase64),
        reason:
            'concurrent callers must share the single in-flight generation '
            '— otherwise identity diverges between cache and disk',
      );
      expect(results[0].publicKeyBase64, equals(results[1].publicKeyBase64));

      // The persisted key matches the shared one.
      final persistedPriv = await storage.read(
          key: StorageKeys.identityPrivateKey);
      expect(persistedPriv, equals(results[0].privateKeyBase64));
    });

    test(
        'B — sequential calls after a successful create return the cached '
        'key without regenerating', () async {
      final storage = _RaceFakeStorage();
      final mgr = KeyManager(storage: storage);

      final first = await mgr.getOrCreateIdentityKeyPair();
      final second = await mgr.getOrCreateIdentityKeyPair();

      expect(second.privateKeyBase64, equals(first.privateKeyBase64));
    });
  });
}
