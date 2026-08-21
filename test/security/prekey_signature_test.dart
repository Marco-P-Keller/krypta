import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/security/encryption/key_pair_model.dart';
import 'package:kryptaapp/security/prekey/prekey_manager.dart';

void main() {
  group('PreKey Signature Verification', () {
    late KryptaKeyPair identityKeyPair;
    final x25519 = X25519();

    setUp(() async {
      // We can't easily create a full EncryptedLocalStore in tests,
      // so we test the static verification method directly.
      final kp = await x25519.newKeyPair();
      identityKeyPair = KryptaKeyPair(
        privateKey: Uint8List.fromList(await kp.extractPrivateKeyBytes()),
        publicKey: Uint8List.fromList((await kp.extractPublicKey()).bytes),
      );
    });

    test('sign and verify roundtrip with signingPublicKey (v2)', () async {
      final preKeyKp = await x25519.newKeyPair();
      final preKeyPublic = Uint8List.fromList(
          (await preKeyKp.extractPublicKey()).bytes);

      // Sign using the Ed25519 key derived from identity private key
      final ed25519 = Ed25519();
      final signingKp = await ed25519.newKeyPairFromSeed(
          identityKeyPair.privateKey);
      final signingPub = Uint8List.fromList(
          (await signingKp.extractPublicKey()).bytes);
      final signature = await ed25519.sign(preKeyPublic, keyPair: signingKp);
      final sigBytes = Uint8List.fromList(signature.bytes);

      // Verify with signing public key (v2 path)
      final result = await PreKeyManager.verifyPreKeySignature(
        preKeyPublic: preKeyPublic,
        signature: sigBytes,
        identityPublicKey: identityKeyPair.publicKey,
        signingPublicKey: signingPub,
      );

      expect(result, isTrue);
    });

    test('verification fails with wrong signing key', () async {
      final preKeyKp = await x25519.newKeyPair();
      final preKeyPublic = Uint8List.fromList(
          (await preKeyKp.extractPublicKey()).bytes);

      // Sign with correct key
      final ed25519 = Ed25519();
      final signingKp = await ed25519.newKeyPairFromSeed(
          identityKeyPair.privateKey);
      final signature = await ed25519.sign(preKeyPublic, keyPair: signingKp);
      final sigBytes = Uint8List.fromList(signature.bytes);

      // Verify with WRONG signing key (attacker's key)
      final attackerKp = await x25519.newKeyPair();
      final attackerPriv = Uint8List.fromList(
          await attackerKp.extractPrivateKeyBytes());
      final attackerSigningKp = await ed25519.newKeyPairFromSeed(attackerPriv);
      final attackerSigningPub = Uint8List.fromList(
          (await attackerSigningKp.extractPublicKey()).bytes);

      final result = await PreKeyManager.verifyPreKeySignature(
        preKeyPublic: preKeyPublic,
        signature: sigBytes,
        identityPublicKey: identityKeyPair.publicKey,
        signingPublicKey: attackerSigningPub,
      );

      expect(result, isFalse);
    });

    test('verification fails with tampered prekey', () async {
      final preKeyKp = await x25519.newKeyPair();
      final preKeyPublic = Uint8List.fromList(
          (await preKeyKp.extractPublicKey()).bytes);

      final ed25519 = Ed25519();
      final signingKp = await ed25519.newKeyPairFromSeed(
          identityKeyPair.privateKey);
      final signingPub = Uint8List.fromList(
          (await signingKp.extractPublicKey()).bytes);
      final signature = await ed25519.sign(preKeyPublic, keyPair: signingKp);
      final sigBytes = Uint8List.fromList(signature.bytes);

      // Tamper with the prekey
      final tampered = Uint8List.fromList(preKeyPublic);
      tampered[0] ^= 0xFF;

      final result = await PreKeyManager.verifyPreKeySignature(
        preKeyPublic: tampered,
        signature: sigBytes,
        identityPublicKey: identityKeyPair.publicKey,
        signingPublicKey: signingPub,
      );

      expect(result, isFalse);
    });

    test('v1 legacy path (no signingPublicKey) returns false for real keys', () async {
      // This documents the known v1 bug: verification with identity PUBLIC key
      // as Ed25519 seed produces a different key pair than signing with identity
      // PRIVATE key. So v1 verification always fails, forcing fallback to
      // simplified DH. New bundles include signingPublicKey to fix this.
      final preKeyKp = await x25519.newKeyPair();
      final preKeyPublic = Uint8List.fromList(
          (await preKeyKp.extractPublicKey()).bytes);

      final ed25519 = Ed25519();
      final signingKp = await ed25519.newKeyPairFromSeed(
          identityKeyPair.privateKey);
      final signature = await ed25519.sign(preKeyPublic, keyPair: signingKp);
      final sigBytes = Uint8List.fromList(signature.bytes);

      // v1 path: no signingPublicKey → uses identity public key as seed
      final result = await PreKeyManager.verifyPreKeySignature(
        preKeyPublic: preKeyPublic,
        signature: sigBytes,
        identityPublicKey: identityKeyPair.publicKey,
        // No signingPublicKey — legacy v1 path
      );

      // This SHOULD fail because identity public ≠ identity private as Ed25519 seed
      expect(result, isFalse);
    });
  });
}
