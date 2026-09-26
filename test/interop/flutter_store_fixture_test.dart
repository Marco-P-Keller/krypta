// Ein Speicher, wie die Flutter-App ihn hinterlässt — für die Übernahme in
// die native App (ios-native/KryptaCore/Sources/KryptaMessenger/FlutterImport.swift).
//
// Mit KRYPTA_GEN_VECTORS=1 schreibt der Test flutter_store.json: die Werte
// aus flutter_secure_storage, die verschlüsselten Dateien aus krypta_store
// (genau wie EncryptedLocalStore sie schreibt) und eine Antwort von Bob, die
// Alice nach der Übernahme mit ihrer alten Sitzung entschlüsseln muss.
//
// Die Schlüssel sind Wegwerf-Testschlüssel.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/chat_model.dart';
import 'package:kryptaapp/features/messenger/data/models/contact_model.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/security/encryption/encryption_service.dart';
import 'package:kryptaapp/security/encryption/key_pair_model.dart';
import 'package:kryptaapp/security/prekey/prekey_bundle.dart';
import 'package:kryptaapp/security/ratchet/double_ratchet.dart';
import 'package:kryptaapp/security/session/session_handshake_service.dart';
import 'package:kryptaapp/security/transparency/key_commitment.dart';

const _vectorDir = 'ios-native/KryptaCore/Tests/KryptaMessengerTests/Vectors';
const _aliceId = 'aliceFlutter00000000001';
const _bobId = 'bobFlutter0000000000002';
const _chatId = '5b1e4c2a-0000-4000-8000-00000000c4a7';

String _b64(List<int> b) => base64Encode(b);

Future<KryptaKeyPair> _pair() async {
  final kp = await X25519().newKeyPair();
  return KryptaKeyPair(
    privateKey: Uint8List.fromList(await kp.extractPrivateKeyBytes()),
    publicKey: Uint8List.fromList((await kp.extractPublicKey()).bytes),
  );
}

void main() {
  test('Flutter-Speicher fuer die Uebernahme erzeugen', () async {
    final enc = EncryptionService();
    final alice = await _pair();
    final bob = await _pair();
    final aliceSpk = await _pair();
    final bobSpk = await _pair();

    // Bobs Bündel, Alices Sitzung, eine Nachricht hin, eine zurück.
    final ed = Ed25519();
    final bobEd = await ed.newKeyPairFromSeed(bob.privateKey);
    final bobSig = await ed.sign(bobSpk.publicKey, keyPair: bobEd);
    final bundle = PreKeyBundle(
      identityPublicKey: bob.publicKey,
      signedPreKeyPublic: bobSpk.publicKey,
      signedPreKeySignature: Uint8List.fromList(bobSig.bytes),
      signedPreKeyId: 3,
      signingPublicKey:
          Uint8List.fromList((await bobEd.extractPublicKey()).bytes),
    );
    final out = await SessionHandshakeService.createOutboundSession(
      identityKeyPair: alice,
      bundle: bundle,
      pinnedIdentityPublicKey: bob.publicKey,
    );
    final (aliceState, first) = await DoubleRatchet.encrypt(
      state: out.ratchetState,
      plaintext: EncryptionService.padPlaintext(Uint8List.fromList(utf8.encode(
          jsonEncode({'_t': 'Hallo Bob', '_sid': _aliceId, '_seq': 0})))),
      associatedData: Uint8List.fromList(utf8.encode(_aliceId)),
    );
    var bobState = await SessionHandshakeService.createInboundSession(
      identityKeyPair: bob,
      signedPreKeyPrivate: bobSpk.privateKey,
      signedPreKeyPublic: bobSpk.publicKey,
      senderIdentityPublic: alice.publicKey,
      senderEphemeralPublic: out.ephemeralPublicKey,
    );
    (bobState, _) = await DoubleRatchet.decrypt(
      state: bobState,
      message: first,
      associatedData: Uint8List.fromList(utf8.encode(_aliceId)),
    );
    final (_, reply) = await DoubleRatchet.encrypt(
      state: bobState,
      plaintext: EncryptionService.padPlaintext(Uint8List.fromList(utf8.encode(
          jsonEncode({'_t': 'Nach dem Update', '_sid': _bobId, '_seq': 0})))),
      associatedData: Uint8List.fromList(utf8.encode(_bobId)),
    );
    final replyMap = reply.toPayloadMap()..['v'] = 3;

    final now = DateTime.now();
    final contact = Contact(
      id: _bobId,
      displayName: 'Mami',
      publicKey: bob.publicKey,
      addedAt: now,
      trustState: TrustState.verified,
      verifiedAt: now,
      verificationMethod: VerificationMethod.qrCode,
      verifiedFingerprint: 'fp',
      firstSeenIdentityKey: bob.publicKey,
      safetyNumberVersion: 2,
    );
    final chat = Chat(
      id: _chatId,
      recipientId: _bobId,
      recipientName: 'Mami',
      lastMessageTime: now,
      defaultSelfDestruct: const Duration(hours: 1),
      defaultSelfDestructSetAt: now,
      regelVersion: 2,
    );
    final messages = [
      Message(
        id: 'm-1',
        chatId: _chatId,
        senderId: _aliceId,
        recipientId: _bobId,
        encryptedContent: '',
        decryptedContent: 'Hallo Bob',
        timestamp: now,
        deliveredAt: now,
        status: MessageStatus.delivered,
      ),
      Message(
        id: 'm-2',
        chatId: _chatId,
        senderId: _bobId,
        recipientId: _aliceId,
        encryptedContent: '',
        decryptedContent: 'blob-mit-passwort',
        timestamp: now.add(const Duration(minutes: 1)),
        status: MessageStatus.read,
        isPasswordProtected: true,
        passwordUnlocked: false,
        selfDestructDuration: const Duration(minutes: 5),
      ),
      Message(
        id: 'm-3',
        chatId: _chatId,
        senderId: _bobId,
        recipientId: _aliceId,
        encryptedContent: '',
        timestamp: now.add(const Duration(minutes: 2)),
        status: MessageStatus.delivered,
        systemEvent: SystemEventKind.screenshot,
      ),
    ];

    final kt0 = await KeyCommitment.create(
      epoch: 0,
      identityPublicKey: alice.publicKey,
      identityPrivateKey: alice.privateKey,
      previousHash: KeyCommitment.genesisHash,
    );

    final slots = <String, String>{
      'contacts': jsonEncode([contact.toMap()]),
      'chats': jsonEncode([chat.toMap()]),
      'msg_$_chatId': jsonEncode(messages.map((m) => m.toMap()).toList()),
      'ratchet_$_chatId': jsonEncode(aliceState.toMap()),
      'prekey_state': jsonEncode({
        'nextId': 5,
        'spk': SignedPreKey(
          id: 4,
          publicKey: aliceSpk.publicKey,
          privateKey: aliceSpk.privateKey,
          createdAt: now,
        ).toMap(),
        'prevSpks': [],
        'opks': [],
      }),
      'control_counters': jsonEncode({
        'counters': {_chatId: 7},
        'lastSeen': {_chatId: 9},
      }),
      'processed_ids': jsonEncode(['alt-1', 'alt-2']),
      'peer_psid_lineage': jsonEncode({
        _bobId: ['psid-a'],
      }),
      'kt_log_$_aliceId': jsonEncode([kt0.toMap()]),
      'kt_pin_$_aliceId': jsonEncode(_b64(kt0.signingPublicKey)),
    };

    // Verschlüsselt wie EncryptedLocalStore._encryptAndWrite (v2, AAD =
    // Slot). `chats` als altes v1 ohne AAD, das es auf Geräten noch gibt.
    final dbKey = enc.generateLocalStorageKey();
    final files = <String, String>{};
    for (final e in slots.entries) {
      final blob = await enc.encryptLocal(
        plaintext: Uint8List.fromList(utf8.encode(e.value)),
        key: dbKey,
        aad: e.key == 'chats' ? null : e.key,
      );
      files['${e.key}.enc'] = _b64(blob);
    }

    final fixture = {
      'aliceId': _aliceId,
      'bobId': _bobId,
      'chatId': _chatId,
      'bobPub': _b64(bob.publicKey),
      'secrets': {
        'krypta_id_priv': alice.privateKeyBase64,
        'krypta_id_pub': alice.publicKeyBase64,
        'krypta_cfg_userid': _aliceId,
        'krypta_db_key': _b64(dbKey),
        'krypta_code_secret': 'c2FsdA==:aGFzaA==',
        'krypta_code_delete': 'c2FsdDI=:aGFzaDI=',
        'krypta_cfg_biometric': 'true',
        'krypta_vault_hash': 'dmF1bHQ=:aGFzaA==',
        'krypta_vault_enabled': 'true',
        'krypta_vault_fails': '2',
        'krypta_cfg_push_privacy': 'true',
        'krypta_cfg_read_receipts': 'true',
        'krypta_cfg_chat_preview': 'false',
        'krypta_cfg_language': 'it',
      },
      'files': files,
      'reply': replyMap,
      'replyText': 'Nach dem Update',
    };

    if (Platform.environment['KRYPTA_GEN_VECTORS'] == '1') {
      await Directory(_vectorDir).create(recursive: true);
      await File('$_vectorDir/flutter_store.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(fixture));
    }
  });
}
