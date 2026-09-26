// Brücke zwischen der Flutter-App und dem nativen Neubau in ios-native/.
//
// Beide Fassungen müssen miteinander sprechen können, Byte für Byte. Dieser
// Test tut zwei Dinge:
//
// 1. Mit KRYPTA_GEN_VECTORS=1 erzeugt er echte Nachrichten mit dem Dart-Code
//    und schreibt sie nach dart_vectors.json. Der Swift-Test entschlüsselt
//    sie dort.
// 2. Liegt swift_vectors.json vor (vom Swift-Test geschrieben), entschlüsselt
//    er, was Swift gebaut hat: Antworten im Ratchet, eine Sitzung, die Swift
//    eröffnet hat, ein Passwort-Blob, eine Steuernachricht.
//
// Die Schlüssel in den Dateien sind Wegwerf-Testschlüssel.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/encryption/encryption_service.dart';
import 'package:kryptaapp/security/encryption/key_pair_model.dart';
import 'package:kryptaapp/security/messaging/control_message.dart';
import 'package:kryptaapp/security/prekey/prekey_bundle.dart';
import 'package:kryptaapp/security/prekey/prekey_manager.dart';
import 'package:kryptaapp/security/ratchet/double_ratchet.dart';
import 'package:kryptaapp/security/ratchet/ratchet_message.dart';
import 'package:kryptaapp/security/ratchet/ratchet_state.dart';
import 'package:kryptaapp/security/session/session_handshake_service.dart';
import 'package:kryptaapp/security/verification/safety_number.dart';

const _vectorDir = 'ios-native/KryptaCore/Tests/KryptaCoreTests/Vectors';
const _aliceId = 'aliceUid0000000000000001';
const _bobId = 'bobUid00000000000000000002';

String _b64(List<int> b) => base64Encode(b);
Uint8List _unb64(String s) => Uint8List.fromList(base64Decode(s));

Future<KryptaKeyPair> _x25519Pair() async {
  final kp = await X25519().newKeyPair();
  return KryptaKeyPair(
    privateKey: Uint8List.fromList(await kp.extractPrivateKeyBytes()),
    publicKey: Uint8List.fromList((await kp.extractPublicKey()).bytes),
  );
}

/// Genau so, wie MessengerProvider._encryptWithRatchet es baut:
/// innerer JSON-Text → Padding → Ratchet mit AD = eigene Nutzerkennung.
Future<(RatchetState, Map<String, dynamic>)> _send(RatchetState state,
    String senderId, Map<String, dynamic> inner) async {
  final padded = EncryptionService.padPlaintext(
      Uint8List.fromList(utf8.encode(jsonEncode(inner))));
  final (s, msg) = await DoubleRatchet.encrypt(
    state: state,
    plaintext: padded,
    associatedData: Uint8List.fromList(utf8.encode(senderId)),
  );
  final map = msg.toPayloadMap();
  map['v'] = 3;
  return (s, map);
}

Future<(RatchetState, Map<String, dynamic>)> _receive(RatchetState state,
    String senderId, Map<String, dynamic> payload) async {
  final (s, padded) = await DoubleRatchet.decrypt(
    state: state,
    message: RatchetMessage.fromPayloadMap(payload),
    associatedData: Uint8List.fromList(utf8.encode(senderId)),
  );
  final plain = EncryptionService.unpadPlaintext(padded);
  return (s, jsonDecode(utf8.decode(plain)) as Map<String, dynamic>);
}

void main() {
  test('Vektoren fuer den Swift-Neubau erzeugen', () async {
    final alice = await _x25519Pair();
    final bob = await _x25519Pair();

    // Bobs signierter Vorabschlüssel — so, wie die App ihn veröffentlicht.
    final bobSpk = await _x25519Pair();
    final (spkSig, sigPk) = await _signPreKey(bobSpk.publicKey, bob.privateKey);
    final bundle = PreKeyBundle(
      identityPublicKey: bob.publicKey,
      signedPreKeyPublic: bobSpk.publicKey,
      signedPreKeySignature: spkSig,
      signedPreKeyId: 7,
      signingPublicKey: sigPk,
    );

    // Alice eröffnet die Sitzung über das Bündel und schickt drei
    // Nachrichten. Die zweite wird in der Datei nach der dritten stehen,
    // damit Swift die Nachholschlüssel beweisen muss.
    final out = await SessionHandshakeService.createOutboundSession(
      identityKeyPair: alice,
      bundle: bundle,
      pinnedIdentityPublicKey: bob.publicKey,
    );
    var aliceState = out.ratchetState;
    final texte = ['Hallo Bob', 'Zweite Nachricht, ueberholt', 'Dritte 🦊 ümlaut'];
    final bundleMessages = <Map<String, dynamic>>[];
    for (var i = 0; i < texte.length; i++) {
      final inner = <String, dynamic>{
        '_t': texte[i],
        '_sid': _aliceId,
        '_seq': i,
        if (i == 0) '_sd': 3600000,
        if (i == 2) '_bar': true,
      };
      final (s, map) = await _send(aliceState, _aliceId, inner);
      aliceState = s;
      if (i == 0) {
        map['ek'] = _b64(out.ephemeralPublicKey);
        map['spkId'] = out.signedPreKeyId;
      }
      bundleMessages.add({'payload': map, 'inner': inner});
    }

    // Rückweg-Kontrolle: Bob (Dart) muss Alices Nachrichten selbst lesen
    // können, sonst sind die Vektoren wertlos.
    var bobCheck = await SessionHandshakeService.createInboundSession(
      identityKeyPair: bob,
      signedPreKeyPrivate: bobSpk.privateKey,
      signedPreKeyPublic: bobSpk.publicKey,
      senderIdentityPublic: alice.publicKey,
      senderEphemeralPublic: out.ephemeralPublicKey,
    );
    for (final m in bundleMessages) {
      final (s, inner) = await _receive(
          bobCheck, _aliceId, m['payload'] as Map<String, dynamic>);
      bobCheck = s;
      expect(inner['_t'], (m['inner'] as Map)['_t']);
    }

    // Rückfallweg ohne Bündel: drei unabhängige DH-Werte über den
    // Identitätsschlüssel, markiert durch ek2.
    final carol = await _x25519Pair();
    final (ephPub, ephPriv) = await DoubleRatchet.generateEphemeralKeyPair();
    final (fbSecret, eph2Pub) =
        await SessionHandshakeService.deriveFallbackSecret(
      identityPrivate: carol.privateKey,
      ephemeralPrivate: ephPriv,
      recipientIdentityPublic: bob.publicKey,
    );
    var carolState = await DoubleRatchet.initAsSender(
      sharedSecret: fbSecret,
      recipientRatchetPublicKey: bob.publicKey,
    );
    final (cs, fbMap) = await _send(carolState, 'carolUid000000000003', {
      '_t': 'Rueckfallweg',
      '_sid': 'carolUid000000000003',
      '_seq': 0,
    });
    carolState = cs;
    fbMap['ek'] = _b64(ephPub);
    fbMap['ek2'] = _b64(eph2Pub);

    // Primitive, einzeln prüfbar.
    final passwortBlob = await EncryptionService().encryptWithPassword(
      plaintext: 'Geheim hinter Passwort',
      password: 'korrekt pferd',
      aad: 'pwd-v1|$_aliceId|$_bobId|msg-1234',
    );
    final safety = await SafetyNumber.generate(
      localUserId: _aliceId,
      localIdentityPublic: alice.publicKey,
      remoteUserId: _bobId,
      remoteIdentityPublic: bob.publicKey,
    );
    final ctrlKey = Uint8List.fromList(List.generate(32, (i) => i * 7 % 256));
    final ctrl = await ControlMessage.create(
      type: 'delivered',
      chatId: 'chat-local-uuid',
      messageId: 'msg-1234',
      senderId: _aliceId,
      counter: 42,
      signingKey: ctrlKey,
    );
    final hmacKey = await _controlHmacKey(alice, bob.publicKey, _aliceId, _bobId);

    // Bob2: ein zweites Bündel, gegen das Swift als Absender eine Sitzung
    // eröffnet. Die privaten Teile stehen drin, damit dieser Test sie
    // später wieder aufnehmen kann.
    final bob2Spk = await _x25519Pair();
    final (bob2Sig, bob2SigPk) =
        await _signPreKey(bob2Spk.publicKey, bob.privateKey);

    final vectors = {
      'aliceId': _aliceId,
      'bobId': _bobId,
      'alice': {'priv': _b64(alice.privateKey), 'pub': _b64(alice.publicKey)},
      'bob': {'priv': _b64(bob.privateKey), 'pub': _b64(bob.publicKey)},
      'bobSpk': {
        'id': 7,
        'priv': _b64(bobSpk.privateKey),
        'pub': _b64(bobSpk.publicKey),
      },
      'bundle': bundle.toMap(),
      'bundleMessages': bundleMessages,
      'deliveryOrder': [0, 2, 1],
      'aliceStateAfterSend': aliceState.toMap(),
      'fallback': {
        'senderId': 'carolUid000000000003',
        'carolPub': _b64(carol.publicKey),
        'payload': fbMap,
        'text': 'Rueckfallweg',
      },
      'password': {
        'blob': passwortBlob,
        'password': 'korrekt pferd',
        'aad': 'pwd-v1|$_aliceId|$_bobId|msg-1234',
        'plaintext': 'Geheim hinter Passwort',
      },
      'safetyNumber': safety,
      'control': {
        'key': _b64(ctrlKey),
        'message': ctrl.toMap(),
        'pairHmacKey': _b64(hmacKey),
      },
      'bob2': {
        'spkPriv': _b64(bob2Spk.privateKey),
        'bundle': PreKeyBundle(
          identityPublicKey: bob.publicKey,
          signedPreKeyPublic: bob2Spk.publicKey,
          signedPreKeySignature: bob2Sig,
          signedPreKeyId: 11,
          signingPublicKey: bob2SigPk,
        ).toMap(),
      },
    };

    if (Platform.environment['KRYPTA_GEN_VECTORS'] == '1') {
      await Directory(_vectorDir).create(recursive: true);
      await File('$_vectorDir/dart_vectors.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(vectors));
    }
  });

  test('Was Swift gebaut hat, liest Dart', () async {
    final swiftFile = File('$_vectorDir/swift_vectors.json');
    final dartFile = File('$_vectorDir/dart_vectors.json');
    if (!swiftFile.existsSync() || !dartFile.existsSync()) {
      markTestSkipped('swift_vectors.json fehlt — erst swift test laufen lassen');
      return;
    }
    final d = jsonDecode(await dartFile.readAsString()) as Map<String, dynamic>;
    final s = jsonDecode(await swiftFile.readAsString()) as Map<String, dynamic>;
    final aliceId = d['aliceId'] as String;
    final bobId = d['bobId'] as String;
    final alice = KryptaKeyPair.fromBase64(
      privateKeyBase64: d['alice']['priv'] as String,
      publicKeyBase64: d['alice']['pub'] as String,
    );
    final bob = KryptaKeyPair.fromBase64(
      privateKeyBase64: d['bob']['priv'] as String,
      publicKeyBase64: d['bob']['pub'] as String,
    );

    // 1. Bobs (Swift) Antworten auf Alices Sitzung.
    var aliceState = RatchetState.fromMap(
        Map<String, dynamic>.from(d['aliceStateAfterSend'] as Map));
    for (final r in (s['replies'] as List)) {
      final (st, inner) = await _receive(
          aliceState, bobId, Map<String, dynamic>.from(r['payload'] as Map));
      aliceState = st;
      expect(inner['_t'], r['text']);
      expect(inner['_sid'], bobId);
    }

    // 2. Eine Sitzung, die Swift als Absender gegen Bob2 eröffnet hat.
    final b2 = Map<String, dynamic>.from(d['bob2'] as Map);
    final b2Bundle =
        PreKeyBundle.fromMap(Map<String, dynamic>.from(b2['bundle'] as Map));
    final first = Map<String, dynamic>.from(s['outbound']['payload'] as Map);
    var inbound = await SessionHandshakeService.createInboundSession(
      identityKeyPair: bob,
      signedPreKeyPrivate: _unb64(b2['spkPriv'] as String),
      signedPreKeyPublic: b2Bundle.signedPreKeyPublic,
      senderIdentityPublic: alice.publicKey,
      senderEphemeralPublic: _unb64(first['ek'] as String),
    );
    expect(first['spkId'], 11);
    final (_, inner) = await _receive(inbound, aliceId, first);
    expect(inner['_t'], s['outbound']['text']);

    // 3. Passwort-Blob aus Swift.
    final pw = Map<String, dynamic>.from(s['password'] as Map);
    final klar = await EncryptionService().decryptWithPassword(
      encryptedBase64: pw['blob'] as String,
      password: pw['password'] as String,
      aad: pw['aad'] as String,
    );
    expect(klar, pw['plaintext']);

    // 4. Steuernachricht aus Swift, signiert mit dem Paarschlüssel.
    final ctrl = ControlMessage.fromMap(
        Map<String, dynamic>.from(s['control'] as Map));
    final key = await _controlHmacKey(bob, alice.publicKey, bobId, aliceId);
    expect(await ctrl.verify(key), isTrue);

    // 5. Ein Bündel, das Swift signiert hat.
    final sb = PreKeyBundle.fromMap(
        Map<String, dynamic>.from(s['bundle'] as Map));
    expect(
      await PreKeyManager.verifyPreKeySignature(
        preKeyPublic: sb.signedPreKeyPublic,
        signature: sb.signedPreKeySignature,
        identityPublicKey: sb.identityPublicKey,
        signingPublicKey: sb.signingPublicKey,
      ),
      isTrue,
    );

    // 6. Sicherheitsnummer: beide Seiten kommen auf dieselbe Zahl.
    expect(s['safetyNumber'], d['safetyNumber']);
  });
}

/// Wie MessengerProvider._deriveControlHmacKey.
Future<Uint8List> _controlHmacKey(KryptaKeyPair own, Uint8List theirPub,
    String ownId, String theirId) async {
  final x = X25519();
  final kp = await x.newKeyPairFromSeed(own.privateKey);
  final shared = await x.sharedSecretKey(
    keyPair: kp,
    remotePublicKey: SimplePublicKey(theirPub, type: KeyPairType.x25519),
  );
  final pairTag = ([ownId, theirId]..sort()).join('|');
  final derived = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: SecretKey(await shared.extractBytes()),
    nonce: Uint8List(32),
    info: utf8.encode('KryptaControlHMAC-v2|$pairTag'),
  );
  return Uint8List.fromList(await derived.extractBytes());
}

/// Wie PreKeyManager.signPreKey: Ed25519 aus dem X25519-Identitätsseed.
Future<(Uint8List, Uint8List)> _signPreKey(
    Uint8List preKeyPublic, Uint8List identityPrivateKey) async {
  final ed = Ed25519();
  final kp = await ed.newKeyPairFromSeed(identityPrivateKey);
  final sig = await ed.sign(preKeyPublic, keyPair: kp);
  return (
    Uint8List.fromList(sig.bytes),
    Uint8List.fromList((await kp.extractPublicKey()).bytes),
  );
}
