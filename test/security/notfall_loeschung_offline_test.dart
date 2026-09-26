import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/key_management/key_manager.dart';
import 'package:kryptaapp/services/emergency/emergency_wipe_service.dart';
import 'package:kryptaapp/services/firebase/firestore_service.dart';
import 'package:kryptaapp/services/storage/encrypted_local_store.dart';
import 'package:kryptaapp/services/storage/secure_storage_service.dart';

/// Die Notfall-Loeschung ohne Netz.
///
/// Firestore meldet einen Schreibvorgang erst fertig, wenn der Server ihn
/// bestaetigt hat — im Flugmodus also nie. Bis zum 25.09.2026 wartete die
/// Loeschung darauf ohne Frist. Die Attrappen hier tun genau das: der
/// Server-Teil antwortet nie.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sie laeuft ohne Netz zu Ende, und das Lokale zuerst', () async {
    final protokoll = <String>[];
    final wipe = EmergencyWipeService(
      secureStorage: _Speicher(protokoll),
      keyManager: _Schluessel(protokoll),
      localStore: _Platte(protokoll),
      firestore: _StummerServer(protokoll),
      auth: _Anmeldung(protokoll),
      serverTimeout: const Duration(milliseconds: 50),
    );

    await wipe.wipeEverything().timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('die Loeschung haengt am Server'),
        );

    expect(protokoll, containsAllInOrder(['platte', 'schluessel', 'speicher']));
    expect(protokoll.indexOf('platte'), lessThan(protokoll.indexOf('server')));
    expect(protokoll, contains('abgemeldet'));
  });
}

class _Platte implements EncryptedLocalStore {
  _Platte(this.p);
  final List<String> p;
  @override
  Future<void> wipeAll() async => p.add('platte');
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Schluessel implements KeyManager {
  _Schluessel(this.p);
  final List<String> p;
  @override
  Future<void> deleteAllKeys() async => p.add('schluessel');
  @override
  void clearMemoryCache() {}
  @override
  Future<bool> hasIdentityKeys() async => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Speicher implements SecureStorageService {
  _Speicher(this.p);
  final List<String> p;
  @override
  Future<void> deleteAll() async => p.add('speicher');
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _StummerServer implements FirestoreService {
  _StummerServer(this.p);
  final List<String> p;
  @override
  Future<void> deleteAllUserData(String userId) {
    p.add('server');
    return Completer<void>().future; // antwortet nie
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Anmeldung implements FirebaseAuth {
  _Anmeldung(this.p);
  final List<String> p;
  @override
  User? get currentUser => _Konto();
  @override
  Future<void> signOut() async => p.add('abgemeldet');
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Konto implements User {
  @override
  String get uid => 'konto-1';
  @override
  Future<void> delete() => Completer<void>().future; // antwortet nie
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
