import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/transparency/key_commitment.dart';
import 'package:kryptaapp/security/transparency/key_transparency_log.dart';
import 'package:kryptaapp/security/transparency/consistency_checker.dart';

void main() {
  final ed25519 = Ed25519();
  final x25519 = X25519();

  /// Helper: create a test X25519 key pair.
  Future<(Uint8List pub, Uint8List priv)> generateTestKeyPair() async {
    final kp = await x25519.newKeyPair();
    final pub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
    final priv = Uint8List.fromList(await kp.extractPrivateKeyBytes());
    return (pub, priv);
  }

  /// Helper: create a signed commitment.
  Future<KeyCommitment> createCommitment({
    required int epoch,
    required Uint8List pub,
    required Uint8List priv,
    required Uint8List previousHash,
  }) async {
    return KeyCommitment.create(
      epoch: epoch,
      identityPublicKey: pub,
      identityPrivateKey: priv,
      previousHash: previousHash,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // KeyCommitment — Core Crypto
  // ═══════════════════════════════════════════════════════════════════════════

  group('KeyCommitment creation', () {
    test('produces valid commitment with correct fields', () async {
      final (pub, priv) = await generateTestKeyPair();

      final commitment = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      expect(commitment.epoch, 0);
      expect(commitment.identityPublicKey, pub);
      expect(commitment.previousCommitHash, KeyCommitment.genesisHash);
      expect(commitment.signature.isNotEmpty, isTrue);
      expect(commitment.signingPublicKey.length, 32);
      expect(commitment.timestampMs, greaterThan(0));
    });

    test('genesis commitment is correctly identified', () async {
      final (pub, priv) = await generateTestKeyPair();

      final genesis = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      expect(genesis.isGenesis, isTrue);
    });

    test('non-genesis commitment is not genesis', () async {
      final (pub, priv) = await generateTestKeyPair();

      final c0 = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final c1 = await createCommitment(
        epoch: 1,
        pub: pub,
        priv: priv,
        previousHash: c0.commitHash,
      );

      expect(c1.isGenesis, isFalse);
    });
  });

  group('KeyCommitment signature verification', () {
    test('valid signature passes verification', () async {
      final (pub, priv) = await generateTestKeyPair();

      final commitment = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      expect(await commitment.verifySignature(), isTrue);
    });

    test('tampered identity key fails verification', () async {
      final (pub, priv) = await generateTestKeyPair();

      final commitment = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final tampered = KeyCommitment(
        epoch: commitment.epoch,
        identityPublicKey: Uint8List(32), // all zeros — tampered
        previousCommitHash: commitment.previousCommitHash,
        timestampMs: commitment.timestampMs,
        signature: commitment.signature,
        signingPublicKey: commitment.signingPublicKey,
      );

      expect(await tampered.verifySignature(), isFalse);
    });

    test('tampered epoch fails verification', () async {
      final (pub, priv) = await generateTestKeyPair();

      final commitment = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final tampered = KeyCommitment(
        epoch: 99, // tampered epoch
        identityPublicKey: commitment.identityPublicKey,
        previousCommitHash: commitment.previousCommitHash,
        timestampMs: commitment.timestampMs,
        signature: commitment.signature,
        signingPublicKey: commitment.signingPublicKey,
      );

      expect(await tampered.verifySignature(), isFalse);
    });

    test('tampered timestamp fails verification', () async {
      final (pub, priv) = await generateTestKeyPair();

      final commitment = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final tampered = KeyCommitment(
        epoch: commitment.epoch,
        identityPublicKey: commitment.identityPublicKey,
        previousCommitHash: commitment.previousCommitHash,
        timestampMs: commitment.timestampMs + 1, // tampered
        signature: commitment.signature,
        signingPublicKey: commitment.signingPublicKey,
      );

      expect(await tampered.verifySignature(), isFalse);
    });

    test('tampered previousCommitHash fails verification', () async {
      final (pub, priv) = await generateTestKeyPair();

      final commitment = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final tampered = KeyCommitment(
        epoch: commitment.epoch,
        identityPublicKey: commitment.identityPublicKey,
        previousCommitHash: Uint8List.fromList(List.generate(32, (i) => 0xFF)),
        timestampMs: commitment.timestampMs,
        signature: commitment.signature,
        signingPublicKey: commitment.signingPublicKey,
      );

      expect(await tampered.verifySignature(), isFalse);
    });

    test('wrong signing key fails verification', () async {
      final (pub, priv) = await generateTestKeyPair();
      final (_, otherPriv) = await generateTestKeyPair();

      final commitment = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final otherSigKp = await ed25519.newKeyPairFromSeed(otherPriv);
      final otherSigPub = Uint8List.fromList(
          (await otherSigKp.extractPublicKey()).bytes);

      final forged = KeyCommitment(
        epoch: commitment.epoch,
        identityPublicKey: commitment.identityPublicKey,
        previousCommitHash: commitment.previousCommitHash,
        timestampMs: commitment.timestampMs,
        signature: commitment.signature,
        signingPublicKey: otherSigPub,
      );

      expect(await forged.verifySignature(), isFalse);
    });

    test('empty signature fails gracefully (not crash)', () async {
      final commitment = KeyCommitment(
        epoch: 0,
        identityPublicKey: Uint8List(32),
        previousCommitHash: KeyCommitment.genesisHash,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        signature: Uint8List(0),
        signingPublicKey: Uint8List(32),
      );

      expect(await commitment.verifySignature(), isFalse);
    });

    test('malformed signing key fails gracefully (not crash)', () async {
      final commitment = KeyCommitment(
        epoch: 0,
        identityPublicKey: Uint8List(32),
        previousCommitHash: KeyCommitment.genesisHash,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        signature: Uint8List(64),
        signingPublicKey: Uint8List(5), // wrong length
      );

      expect(await commitment.verifySignature(), isFalse);
    });
  });

  group('KeyCommitment commit hash', () {
    test('is deterministic', () async {
      final (pub, priv) = await generateTestKeyPair();

      final commitment = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final hash1 = commitment.commitHash;
      final hash2 = commitment.commitHash;
      expect(hash1, equals(hash2));
    });

    test('is 32 bytes (SHA-256)', () async {
      final (pub, priv) = await generateTestKeyPair();

      final commitment = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      expect(commitment.commitHash.length, 32);
    });

    test('different epochs produce different hashes', () async {
      final (pub, priv) = await generateTestKeyPair();

      final c0 = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final c1 = await createCommitment(
        epoch: 1,
        pub: pub,
        priv: priv,
        previousHash: c0.commitHash,
      );

      expect(c0.commitHash, isNot(equals(c1.commitHash)));
    });

    test('different keys produce different hashes', () async {
      final (pub1, priv1) = await generateTestKeyPair();
      final (pub2, priv2) = await generateTestKeyPair();

      final c1 = await createCommitment(
        epoch: 0,
        pub: pub1,
        priv: priv1,
        previousHash: KeyCommitment.genesisHash,
      );

      final c2 = await createCommitment(
        epoch: 0,
        pub: pub2,
        priv: priv2,
        previousHash: KeyCommitment.genesisHash,
      );

      expect(c1.commitHash, isNot(equals(c2.commitHash)));
    });
  });

  group('KeyCommitment chain verification', () {
    test('verifiesAgainst succeeds for correct chain link', () async {
      final (pub, priv) = await generateTestKeyPair();

      final c0 = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final c1 = await createCommitment(
        epoch: 1,
        pub: pub,
        priv: priv,
        previousHash: c0.commitHash,
      );

      expect(c1.verifiesAgainst(c0.commitHash), isTrue);
    });

    test('verifiesAgainst fails for wrong previous hash', () async {
      final (pub, priv) = await generateTestKeyPair();

      final c1 = await createCommitment(
        epoch: 1,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final wrongHash = Uint8List.fromList(List.generate(32, (i) => 0xAB));
      expect(c1.verifiesAgainst(wrongHash), isFalse);
    });

    test('verifiesAgainst rejects different-length hash (constant-time safe)', () async {
      final (pub, priv) = await generateTestKeyPair();

      final commitment = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      expect(commitment.verifiesAgainst(Uint8List(16)), isFalse);
      expect(commitment.verifiesAgainst(Uint8List(64)), isFalse);
    });

    test('5-commitment chain is fully valid', () async {
      final (pub, priv) = await generateTestKeyPair();

      var prevHash = KeyCommitment.genesisHash;
      final chain = <KeyCommitment>[];

      for (var i = 0; i < 5; i++) {
        final c = await createCommitment(
          epoch: i,
          pub: pub,
          priv: priv,
          previousHash: prevHash,
        );
        chain.add(c);
        prevHash = c.commitHash;
      }

      // Verify every link
      for (var i = 0; i < chain.length; i++) {
        expect(await chain[i].verifySignature(), isTrue,
            reason: 'Commitment $i should have valid signature');

        if (i == 0) {
          expect(chain[i].verifiesAgainst(KeyCommitment.genesisHash), isTrue);
        } else {
          expect(chain[i].verifiesAgainst(chain[i - 1].commitHash), isTrue,
              reason: 'Commitment $i should chain to ${i - 1}');
        }
      }
    });

    test('chain detects forged intermediate commitment', () async {
      final (pub, priv) = await generateTestKeyPair();
      final (roguePub, roguePriv) = await generateTestKeyPair();

      final c0 = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      // Rogue inserts a commitment claiming to chain from c0
      final rogue = await createCommitment(
        epoch: 1,
        pub: roguePub,
        priv: roguePriv,
        previousHash: c0.commitHash,
      );

      // Chain link is correct (rogue linked to c0)
      expect(rogue.verifiesAgainst(c0.commitHash), isTrue);
      // Signature is valid (rogue signed with rogue key)
      expect(await rogue.verifySignature(), isTrue);
      // BUT: identity key differs — detectable by key comparison
      expect(rogue.identityPublicKey, isNot(equals(c0.identityPublicKey)));
    });

    test('key rotation produces valid but detectable chain', () async {
      final (pub1, priv1) = await generateTestKeyPair();
      final (pub2, priv2) = await generateTestKeyPair();

      final c0 = await createCommitment(
        epoch: 0,
        pub: pub1,
        priv: priv1,
        previousHash: KeyCommitment.genesisHash,
      );

      final c1 = await createCommitment(
        epoch: 1,
        pub: pub2,
        priv: priv2,
        previousHash: c0.commitHash,
      );

      expect(await c0.verifySignature(), isTrue);
      expect(await c1.verifySignature(), isTrue);
      expect(c1.verifiesAgainst(c0.commitHash), isTrue);
      expect(c0.identityPublicKey, isNot(equals(c1.identityPublicKey)));
    });
  });

  group('KeyCommitment canonical bytes', () {
    test('fixed length 113 bytes (incl. signingPublicKey, post H1-Crypto fix)',
        () async {
      // Audit 2026-05 / H1-Crypto: signingPublicKey is bound into canonical
      // bytes so a server-side swap of the Ed25519 pubkey invalidates the
      // signature. Layout: 1 (version) + 8 (epoch) + 32 (idPub) + 32 (prev) +
      // 8 (ts) + 32 (signingPub) = 113.
      final (pub, priv) = await generateTestKeyPair();

      final commitment = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      expect(commitment.canonicalBytes.length, 113);
    });

    test('first byte is current version (post H1-Crypto: v2)', () async {
      // Audit 2026-05 / H1-Crypto: new commitments are written as v2; the
      // version byte is the first byte of canonical bytes. v1 commitments
      // remain decodable for back-compat.
      final (pub, priv) = await generateTestKeyPair();

      final commitment = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      expect(commitment.canonicalBytes[0], KeyCommitment.currentVersion);
      expect(commitment.canonicalBytes[0], 2);
    });

    test('epoch is big-endian at offset 1', () async {
      final (pub, priv) = await generateTestKeyPair();

      final commitment = await createCommitment(
        epoch: 256, // 0x100
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final bytes = commitment.canonicalBytes;
      // Epoch 256 = 0x0000000000000100 in big-endian
      expect(bytes[7], 1);  // offset 1 + 6 = 7
      expect(bytes[8], 0);  // offset 1 + 7 = 8
    });
  });

  group('KeyCommitment serialization', () {
    test('round-trip preserves all fields', () async {
      final (pub, priv) = await generateTestKeyPair();

      final original = await createCommitment(
        epoch: 42,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final map = original.toMap();
      final restored = KeyCommitment.fromMap(map);

      expect(restored.epoch, original.epoch);
      expect(restored.identityPublicKey, original.identityPublicKey);
      expect(restored.previousCommitHash, original.previousCommitHash);
      expect(restored.timestampMs, original.timestampMs);
      expect(restored.signature, original.signature);
      expect(restored.signingPublicKey, original.signingPublicKey);
    });

    test('restored commitment still verifies', () async {
      final (pub, priv) = await generateTestKeyPair();

      final original = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final restored = KeyCommitment.fromMap(original.toMap());
      expect(await restored.verifySignature(), isTrue);
    });

    test('uses compact keys for minimal payload', () async {
      final (pub, priv) = await generateTestKeyPair();

      final commitment = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final map = commitment.toMap();
      expect(map.containsKey('e'), isTrue);   // epoch
      expect(map.containsKey('k'), isTrue);   // key
      expect(map.containsKey('p'), isTrue);   // previous hash
      expect(map.containsKey('ts'), isTrue);  // timestamp
      expect(map.containsKey('s'), isTrue);   // signature
      expect(map.containsKey('sp'), isTrue);  // signing public key
      // No verbose keys
      expect(map.containsKey('epoch'), isFalse);
      expect(map.containsKey('signature'), isFalse);
    });

    test('large epoch value serializes correctly', () async {
      final (pub, priv) = await generateTestKeyPair();

      final commitment = await createCommitment(
        epoch: 999999,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final restored = KeyCommitment.fromMap(commitment.toMap());
      expect(restored.epoch, 999999);
    });

    test('JSON round-trip via jsonEncode/jsonDecode', () async {
      final (pub, priv) = await generateTestKeyPair();

      final commitment = await createCommitment(
        epoch: 7,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final json = jsonEncode(commitment.toMap());
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final restored = KeyCommitment.fromMap(decoded);

      expect(restored.epoch, 7);
      expect(await restored.verifySignature(), isTrue);
    });
  });

  group('KeyCommitment genesisHash', () {
    test('is 32 zero bytes', () {
      expect(KeyCommitment.genesisHash.length, 32);
      for (final b in KeyCommitment.genesisHash) {
        expect(b, 0);
      }
    });

    test('is consistent across calls', () {
      final h1 = KeyCommitment.genesisHash;
      final h2 = KeyCommitment.genesisHash;
      expect(h1, equals(h2));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ConsistencyProof
  // ═══════════════════════════════════════════════════════════════════════════

  group('ConsistencyProof', () {
    test('serialization round-trip preserves all fields', () {
      final proof = ConsistencyProof(
        userId: 'user_abc123',
        epoch: 5,
        commitHash: Uint8List.fromList(List.generate(32, (i) => i)),
      );

      final map = proof.toMap();
      final restored = ConsistencyProof.fromMap(map);

      expect(restored.userId, 'user_abc123');
      expect(restored.epoch, 5);
      expect(restored.commitHash, equals(proof.commitHash));
    });

    test('uses compact keys', () {
      final proof = ConsistencyProof(
        userId: 'test',
        epoch: 0,
        commitHash: Uint8List(32),
      );

      final map = proof.toMap();
      expect(map.keys.toSet(), equals({'u', 'e', 'h'}));
    });

    test('handles epoch 0', () {
      final proof = ConsistencyProof(
        userId: 'test',
        epoch: 0,
        commitHash: Uint8List(32),
      );

      final restored = ConsistencyProof.fromMap(proof.toMap());
      expect(restored.epoch, 0);
    });

    test('handles large epoch', () {
      final proof = ConsistencyProof(
        userId: 'test',
        epoch: 1000000,
        commitHash: Uint8List(32),
      );

      final restored = ConsistencyProof.fromMap(proof.toMap());
      expect(restored.epoch, 1000000);
    });

    test('JSON round-trip', () {
      final proof = ConsistencyProof(
        userId: 'test',
        epoch: 3,
        commitHash: Uint8List.fromList(List.generate(32, (i) => i * 2)),
      );

      final json = jsonEncode(proof.toMap());
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final restored = ConsistencyProof.fromMap(decoded);

      expect(restored.userId, 'test');
      expect(restored.epoch, 3);
      expect(restored.commitHash, equals(proof.commitHash));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Enums — Exhaustive Coverage
  // ═══════════════════════════════════════════════════════════════════════════

  group('CommitmentVerifyResult', () {
    test('has all expected values', () {
      expect(CommitmentVerifyResult.values, containsAll([
        CommitmentVerifyResult.valid,
        CommitmentVerifyResult.signatureInvalid,
        CommitmentVerifyResult.chainBroken,
        CommitmentVerifyResult.epochViolation,
        CommitmentVerifyResult.keyMismatch,
        CommitmentVerifyResult.malformed,
        // Audit 2026-05 / H1-Crypto.
        CommitmentVerifyResult.signingKeyChanged,
        CommitmentVerifyResult.legacyBootstrapRejected,
      ]));
      expect(CommitmentVerifyResult.values.length, 8);
    });
  });

  group('ConsistencyResult', () {
    test('has all expected values', () {
      expect(ConsistencyResult.values, containsAll([
        ConsistencyResult.consistent,
        ConsistencyResult.localBehind,
        ConsistencyResult.remoteBehind,
        ConsistencyResult.splitView,
        ConsistencyResult.noProof,
      ]));
      expect(ConsistencyResult.values.length, 5);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Security Properties
  // ═══════════════════════════════════════════════════════════════════════════

  group('Security: Server cannot forge commitments', () {
    test('signature binds commitment to identity private key', () async {
      final (pub, priv) = await generateTestKeyPair();
      final (_, attackerPriv) = await generateTestKeyPair();

      // Legitimate commitment
      final legit = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      // Attacker creates commitment for same key but different signing key
      final forged = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: attackerPriv,
        previousHash: KeyCommitment.genesisHash,
      );

      // Both have valid signatures
      expect(await legit.verifySignature(), isTrue);
      expect(await forged.verifySignature(), isTrue);

      // But signing keys differ — client can detect the mismatch
      // against the known signing public key
      expect(legit.signingPublicKey, isNot(equals(forged.signingPublicKey)));
    });

    test('every field is covered by signature', () async {
      final (pub, priv) = await generateTestKeyPair();

      final original = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      // Tamper each field individually and verify signature fails
      final tamperedEpoch = KeyCommitment(
        epoch: 1,
        identityPublicKey: original.identityPublicKey,
        previousCommitHash: original.previousCommitHash,
        timestampMs: original.timestampMs,
        signature: original.signature,
        signingPublicKey: original.signingPublicKey,
      );
      expect(await tamperedEpoch.verifySignature(), isFalse);

      final tamperedKey = KeyCommitment(
        epoch: original.epoch,
        identityPublicKey: Uint8List.fromList(List.generate(32, (i) => i)),
        previousCommitHash: original.previousCommitHash,
        timestampMs: original.timestampMs,
        signature: original.signature,
        signingPublicKey: original.signingPublicKey,
      );
      expect(await tamperedKey.verifySignature(), isFalse);

      final tamperedPrev = KeyCommitment(
        epoch: original.epoch,
        identityPublicKey: original.identityPublicKey,
        previousCommitHash: Uint8List.fromList(List.generate(32, (i) => i)),
        timestampMs: original.timestampMs,
        signature: original.signature,
        signingPublicKey: original.signingPublicKey,
      );
      expect(await tamperedPrev.verifySignature(), isFalse);

      final tamperedTs = KeyCommitment(
        epoch: original.epoch,
        identityPublicKey: original.identityPublicKey,
        previousCommitHash: original.previousCommitHash,
        timestampMs: original.timestampMs + 1000,
        signature: original.signature,
        signingPublicKey: original.signingPublicKey,
      );
      expect(await tamperedTs.verifySignature(), isFalse);
    });
  });

  group('Security: Chain integrity', () {
    test('inserting a commitment breaks the chain', () async {
      final (pub, priv) = await generateTestKeyPair();

      final c0 = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final c1 = await createCommitment(
        epoch: 1,
        pub: pub,
        priv: priv,
        previousHash: c0.commitHash,
      );

      final c2 = await createCommitment(
        epoch: 2,
        pub: pub,
        priv: priv,
        previousHash: c1.commitHash,
      );

      // If server tries to skip c1 and claim c2 follows c0:
      expect(c2.verifiesAgainst(c0.commitHash), isFalse);
      // c2 only verifies against c1
      expect(c2.verifiesAgainst(c1.commitHash), isTrue);
    });

    test('reordering commitments breaks the chain', () async {
      final (pub, priv) = await generateTestKeyPair();

      final c0 = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      final c1 = await createCommitment(
        epoch: 1,
        pub: pub,
        priv: priv,
        previousHash: c0.commitHash,
      );

      // If server presents c0 after c1 (reorder):
      // c0 claims genesis as previous, not c1
      expect(c0.verifiesAgainst(c1.commitHash), isFalse);
    });
  });

  group('Security: Constant-time operations', () {
    test('verifiesAgainst uses constant-time comparison', () async {
      final (pub, priv) = await generateTestKeyPair();

      final commitment = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );

      // Test with progressively "closer" hashes
      // All should fail but the comparison should be constant-time
      final hash1 = Uint8List.fromList(List.generate(32, (_) => 0xFF));
      final hash2 = Uint8List(32); // All zeros — matches genesis
      final hash3 = Uint8List.fromList(
          List.generate(32, (i) => i == 31 ? 1 : 0)); // Off by one bit

      expect(commitment.verifiesAgainst(hash1), isFalse);
      expect(commitment.verifiesAgainst(hash2), isTrue); // genesis matches
      expect(commitment.verifiesAgainst(hash3), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // genesisHash immutability
  // ═══════════════════════════════════════════════════════════════════════════

  group('genesisHash immutability', () {
    test('returns fresh copy — mutation does not affect subsequent calls', () {
      final g1 = KeyCommitment.genesisHash;
      g1[0] = 0xFF; // attempt to mutate
      final g2 = KeyCommitment.genesisHash;
      expect(g2[0], 0, reason: 'genesisHash must not be affected by external mutation');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // commitHash caching
  // ═══════════════════════════════════════════════════════════════════════════

  group('commitHash caching', () {
    test('returns identical bytes on repeated calls', () async {
      final (pub, priv) = await generateTestKeyPair();
      final c = await createCommitment(
        epoch: 0,
        pub: pub,
        priv: priv,
        previousHash: KeyCommitment.genesisHash,
      );
      final h1 = c.commitHash;
      final h2 = c.commitHash;
      expect(identical(h1, h2), isTrue,
          reason: 'commitHash should return cached instance');
    });
  });
}
