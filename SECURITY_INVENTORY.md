# Krypta Security Inventory

## Key Material

| Key | Storage | Format | Created | Rotated | Deleted |
|-----|---------|--------|---------|---------|---------|
| Identity X25519 private | Keychain (`krypta_id_priv`) | Base64 | First setup | Never | Emergency wipe |
| Identity X25519 public | Keychain (`krypta_id_pub`) + Firestore | Base64 | First setup | Never | Emergency wipe |
| Signed PreKey private | EncryptedLocalStore (`prekey_state`) | XChaCha20 | First messenger init | Every 7 days (auto) | Emergency wipe |
| Signed PreKey public | EncryptedLocalStore + Firestore | Base64 | First messenger init | Every 7 days (auto) | Emergency wipe |
| One-Time PreKeys (pool) | EncryptedLocalStore | XChaCha20 | First messenger init | Replenished when <20 | Consumed on use / wipe |
| Database encryption key | Keychain (`krypta_db_key`) | Base64 256-bit | First data write | Via `rotateStorageKey()` | Emergency wipe |
| Ratchet root key (per chat) | EncryptedLocalStore (`ratchet_*`) | XChaCha20 | First message in chat | Every DH ratchet step | Chat delete / wipe |
| Ratchet chain keys | EncryptedLocalStore (`ratchet_*`) | XChaCha20 | Session init | Every message | Overwritten by ratchet |
| Ratchet message keys | In-memory only (skipped keys) | RAM | On decrypt of skipped msg | Never | Used once, then deleted |

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
