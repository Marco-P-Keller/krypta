# Security Release Checklist

Check all items before each release. A single unchecked item blocks the release.

## Code Hygiene

- [ ] `flutter analyze` — 0 errors, 0 warnings
- [ ] No `debugPrint` calls that include `$e` in crypto/storage/messenger code
- [ ] No `print()` calls anywhere in lib/
- [ ] No hardcoded keys, tokens, or passwords
- [ ] No `TODO` or `FIXME` in security-critical code
- [ ] `KryptaKeyPair.toString()` does not expose key bytes

## Crypto

- [ ] All new message encryption uses v2 (Double Ratchet)
- [ ] v1 legacy path is read-only (no new v1 messages created)
- [ ] Password-protected messages use Argon2id v2 (not PBKDF2)
- [ ] Vault password stored as Argon2id hash (never plaintext)
- [ ] Access codes stored as Argon2id hash (never plaintext)
- [ ] HKDF info strings are versioned (`KryptaDoubleRatchet-v1`)
- [ ] Constant-time comparison used for all secret verification

## Ratchet

- [ ] Ratchet state persisted after every send/receive
- [ ] Skipped message keys limit enforced (max 1000)
- [ ] DH ratchet step generates fresh key pairs
- [ ] Associated data includes sender identity in AAD

## PreKeys

- [ ] Signed prekey rotated if > 7 days old
- [ ] One-time prekey pool replenished if < 20
- [ ] PreKey bundle published to Firestore on rotation

## Storage

- [ ] All local data encrypted (chats, messages, contacts, ratchet states, decoy data)
- [ ] Database encryption key in platform keychain (not in app files)
- [ ] Storage key rotation API available (`rotateStorageKey()`)
- [ ] No plaintext secrets in SharedPreferences or unencrypted files

## Wipe

- [ ] Emergency wipe deletes: local store, keys, secure storage, cache/temp
- [ ] Server data cleanup: messages, acks, typing, FCM, public keys, prekeys
- [ ] Firebase account deleted + signed out
- [ ] Expired messages cleaned up on app start
- [ ] Self-destruct timer running while app is active

## Decoy

- [ ] Decoy files always exist on disk (even if decoy never used)
- [ ] Screenshot protection enabled in both real and decoy modes
- [ ] Decoy data stored in separate `decoy_*` namespace
- [ ] No forensic distinguishers between real/decoy screen state

## Platform

- [ ] Root/jailbreak detection active
- [ ] Screenshot protection on all sensitive screens
- [ ] Biometric re-auth on app resume (if enabled)
- [ ] Portrait orientation locked

## Verification

- [ ] Safety number generation is symmetric (A→B == B→A)
- [ ] Key change resets verified status
- [ ] Key change warning shown in chat settings
- [ ] QR code contains safety number

## ACK/Typing/Status

- [ ] ACKs only accepted for messages we sent
- [ ] ACK status only advances forward (no downgrade)
- [ ] Typing indicators filtered to known contacts only

## Tests

- [ ] `flutter test` — all tests pass
- [ ] Double Ratchet tests: basic, bidirectional, wrong key, tamper, nonce uniqueness
- [ ] Encryption tests: keygen, E2E roundtrip, tamper, local storage, Argon2id
- [ ] Safety number tests: symmetry, uniqueness, formatting
- [ ] Wipe/self-destruct tests: expiry, burn-after-read, serialization
