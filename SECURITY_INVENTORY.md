# Krypta Security Inventory

## Key Material

| Key | Storage | Format | Lifecycle |
|-----|---------|--------|-----------|
| Identity X25519 private | Keychain/Keystore (`krypta_id_priv`) | Base64 | Created once, deleted on wipe |
| Identity X25519 public | Keychain/Keystore (`krypta_id_pub`) + Firestore | Base64 | Created once, deleted on wipe |
| Signed PreKey private | EncryptedLocalStore (`prekey_state`) | XChaCha20 encrypted | Rotated every 7 days |
| Signed PreKey public | EncryptedLocalStore + Firestore | Base64 in bundle | Rotated every 7 days |
| One-Time PreKeys | EncryptedLocalStore | XChaCha20 encrypted | Consumed on use |
| Database encryption key | Keychain/Keystore (`krypta_db_key`) | Base64 (256-bit) | Created once, deleted on wipe |
| Double Ratchet state (per chat) | EncryptedLocalStore (`ratchet_{chatId}`) | XChaCha20 encrypted | Evolves per message |

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
| Chat list | `{appDir}/chats.enc` | XChaCha20-Poly1305 | Database key |
| Messages per chat | `{appDir}/msg_{id}.enc` | XChaCha20-Poly1305 | Database key |
| Contacts | `{appDir}/contacts.enc` | XChaCha20-Poly1305 | Database key |
| Ratchet states | `{appDir}/ratchet_{id}.enc` | XChaCha20-Poly1305 | Database key |
| Decoy data | `{appDir}/decoy_*.enc` | XChaCha20-Poly1305 | Database key |
| PreKey state | `{appDir}/prekey_state.enc` | XChaCha20-Poly1305 | Database key |

## Plaintext Data

| Data | Storage | Reason |
|------|---------|--------|
| Setup complete flag | Keychain (`krypta_cfg_setup`) | No secret value |
| Biometric enabled flag | Keychain (`krypta_cfg_biometric`) | No secret value |
| User ID | Keychain (`krypta_cfg_userid`) | Not a secret (Firebase UID) |
| Vault enabled flag | Keychain (`krypta_vault_enabled`) | Boolean, not secret |

## Deletion Paths

### Emergency Wipe
Phase 1 (local, no network): EncryptedLocalStore, all keys, SecureStorage
Phase 2 (server): Firestore user data, prekeys, public keys
Phase 3 (auth): Firebase account deletion, sign out

### Delete Code (calculator)
Same as emergency wipe — triggered by entering delete code on calculator.

### Decoy Path
Decoy data is in a separate `decoy_*` namespace. Real data is NOT accessible from decoy mode.

## Message Encryption Protocol

### v2 (Double Ratchet — current)
1. Session init: simplified X3DH → shared secret
2. Each message: Double Ratchet encrypt (DH ratchet + symmetric ratchet)
3. Cipher: XChaCha20-Poly1305 with AAD
4. Forward secrecy: DH ratchet on each turn
5. Post-compromise security: new DH keys restore security

### v1 (Legacy — read-only migration)
1. Ephemeral X25519 per message
2. HKDF-SHA256 key derivation
3. XChaCha20-Poly1305
4. Forward secrecy only (no PCS)

### Password-Protected Messages
- v2: Argon2id(19MiB, 2 iter, p=1) → 256-bit key → XChaCha20-Poly1305
- v1 (legacy read): PBKDF2-SHA256(100k iter) → 256-bit key → XChaCha20-Poly1305
