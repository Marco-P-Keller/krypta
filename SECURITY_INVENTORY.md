# Krypta Security Inventory

**Last Updated:** 2026-04-21 (post-hardening Tasks 1-12)

## Key Material

| Key | Storage | Format | Created | Rotated | Zeroed | Deleted |
|-----|---------|--------|---------|---------|--------|---------|
| Identity X25519 private | Keychain (`krypta_id_priv`) | Base64 | First setup | Never | Cache clear (3-min TTL) | Emergency wipe |
| Identity X25519 public | Keychain (`krypta_id_pub`) + Firestore | Base64 | First setup | Never | N/A (public) | Emergency wipe |
| Signed PreKey private | EncryptedLocalStore (`prekey_state`) | XChaCha20 | Messenger init | Every 7 days (48h overlap) | On rotation/wipe | Emergency wipe |
| Signed PreKey public | EncryptedLocalStore + Firestore | Base64 | Messenger init | Every 7 days (auto) | N/A (public) | Emergency wipe |
| One-Time PreKeys (pool) | EncryptedLocalStore | XChaCha20 | Messenger init | Replenished when <20 | Private key zeroed | Consumed on use / wipe |
| Database encryption key | Keychain (`krypta_db_key`) or HW-wrapped (`krypta_db_key_hw`) | Base64 / HW-encrypted | First data write | Via `rotateStorageKey()` | N/A (in keychain) | Emergency wipe |
| Hardware wrapping key | StrongBox (Android) / Secure Enclave (iOS) | Non-extractable | Device init | Never | N/A (hardware) | `deleteHardwareKey()` |
| Ratchet root key (per chat) | EncryptedLocalStore (`ratchet_*`) | XChaCha20 | First message in chat | Every DH ratchet step | On wipe (SensitiveBuffer) | Chat delete / wipe |
| Ratchet chain keys | EncryptedLocalStore (`ratchet_*`) | XChaCha20 | Session init | Every message | On wipe (SensitiveBuffer) | Overwritten by ratchet |
| Ratchet message keys | In-memory only (skipped keys store) | RAM | On decrypt of skipped msg | Never | Zeroed after single use | 7-day TTL / wipe |
| DH intermediate outputs | In-memory only | RAM | During DH computation | N/A | Zeroed immediately after KDF | N/A |
| Ed25519 signing key | Derived from identity private | RAM | On sign/commit | N/A | GC-managed | N/A |

## Hashed Secrets (not recoverable)

| Secret | Storage Key | Hash | Salt |
|--------|-------------|------|------|
| Secret code | `krypta_code_secret` | Argon2id (19MiB, 2 iter) | Random 16B |
| Decoy code | `krypta_code_decoy` | Argon2id (19MiB, 2 iter) | Random 16B |
| Delete code | `krypta_code_delete` | Argon2id (19MiB, 2 iter) | Random 16B |
| Vault password | `krypta_vault_hash` | Argon2id (19MiB, 2 iter) | Random 16B |

## Encrypted Data (at rest)

| Data | Storage | Cipher | Key Source |
|------|---------|--------|------------|
| Chat list | `{appDir}/chats.enc` | XChaCha20-Poly1305 | Database key (HW-wrapped) |
| Messages per chat | `{appDir}/msg_{id}.enc` | XChaCha20-Poly1305 | Database key (HW-wrapped) |
| Contacts | `{appDir}/contacts.enc` | XChaCha20-Poly1305 | Database key (HW-wrapped) |
| Ratchet states | `{appDir}/ratchet_{id}.enc` | XChaCha20-Poly1305 | Database key (HW-wrapped) |
| Decoy data | `{appDir}/decoy_*.enc` | XChaCha20-Poly1305 | Database key (HW-wrapped) |
| PreKey state | `{appDir}/prekey_state.enc` | XChaCha20-Poly1305 | Database key (HW-wrapped) |
| Key Transparency logs | `{appDir}/kt_log_{userId}.enc` | XChaCha20-Poly1305 | Database key (HW-wrapped) |
| Control counters | `{appDir}/control_counters.enc` | XChaCha20-Poly1305 | Database key (HW-wrapped) |
| Processed message IDs | `{appDir}/processed_ids.enc` | XChaCha20-Poly1305 | Database key (HW-wrapped) |

## Plaintext Data

| Data | Storage | Reason |
|------|---------|--------|
| Setup complete flag | Keychain (`krypta_cfg_setup`) | No secret value |
| Biometric enabled flag | Keychain (`krypta_cfg_biometric`) | No secret value |
| User ID | Keychain (`krypta_cfg_userid`) | Not a secret (Firebase UID) |
| Vault enabled flag | Keychain (`krypta_vault_enabled`) | Boolean, not secret |
| Push privacy mode | Keychain (`krypta_cfg_push_privacy`) | Boolean, not secret |
| Screenshot protection | Keychain (`krypta_cfg_screenshot`) | Boolean, not secret |
| Vault fail count | Keychain (`krypta_vault_fails`) | Integer, not secret |
| Vault last fail time | Keychain (`krypta_vault_lastfail`) | Timestamp, not secret |

## Server-Side Data (Firestore)

| Collection | Data | Retention | Contains Secret? |
|-----------|------|-----------|-----------------|
| `publicKeys/{userId}` | X25519 public key (Base64) | Until wipe | No (public) |
| `prekeys/{userId}` | PreKeyBundle (public keys + signature) | Until rotation | No (public) |
| `keyCommitments/{userId}/log/{epoch}` | Signed commitment (public key + hash chain) | Append-only | No (public) |
| `messages/{userId}/inbox` | Encrypted message blobs | Deleted after delivery | Yes (E2E encrypted) |
| `acks/{userId}/inbox` | ACK type + message ID | Deleted after processing | No |
| `deliveryTokens/{userId}` | Random 32B token | 24h rotation | Bearer token |
| `fcmTokens/{userId}` | FCM push token | Until logout/wipe | Device identifier |

## Deletion Paths

### Emergency Wipe
```
Phase 1 (memory):   Zero all in-memory key bytes (ratchet states, identity keys, chain keys)
Phase 2 (hardware): Delete hardware wrapping key (StrongBox/Secure Enclave)
Phase 3 (local):    Delete EncryptedLocalStore, all .enc files
Phase 4 (keychain): Clear all SecureStorage entries (keys, codes, config)
Phase 5 (server):   Delete Firestore data (messages, acks, keys, prekeys, tokens, commitments)
Phase 6 (auth):     Delete Firebase account, sign out
Phase 7 (cache):    Clear all in-memory caches, reset app state
```

### Delete Code (calculator)
Same as emergency wipe — triggered by entering delete code on calculator. No confirmation.

### Decoy Path
Decoy data is in a separate `decoy_*` namespace. Real data is NOT accessible from decoy mode.

## Message Encryption Protocol

### v2 (Double Ratchet — current, mandatory)
1. Session init: X3DH (3-DH or 4-DH) → shared secret
2. Each message: Double Ratchet encrypt (DH ratchet + symmetric ratchet)
3. Cipher: XChaCha20-Poly1305 with mandatory AAD
4. AAD: associatedData || ratchet header (binds sender/recipient/message)
5. Forward secrecy: DH ratchet on each turn
6. Post-compromise security: new DH keys restore security
7. Message keys zeroed after use
8. DH outputs zeroed after KDF

### v1 (Legacy — REJECTED)
v1 messages are rejected entirely. No read-only migration, no fallback.
v1 prekey bundles without Ed25519 signature are rejected.

### Password-Protected Messages
- v2: Argon2id(19MiB, 2 iter, p=1) → 256-bit key → XChaCha20-Poly1305
- v1 (PBKDF2): Rejected — no migration path

## RAM Exposure Timeline

| Material | In-Memory Duration | Zeroing Method |
|---------|-------------------|---------------|
| Identity private key | 3-minute cache TTL | `_zeroBytes()` on cache clear |
| Ratchet state | 5-minute cache TTL | `SensitiveBuffer.zeroBytes()` on wipe |
| DH output | Microseconds (within function) | `SensitiveBuffer.zeroBytes()` after KDF |
| Message key | Microseconds (within function) | `SensitiveBuffer.zeroBytes()` after encrypt/decrypt |
| Skipped message keys | Up to 7 days | `SensitiveBuffer.zeroBytes()` on prune/consume |
| Decrypted message text | Until chat becomes inactive | Timer-based scrubbing (2-min interval) |
