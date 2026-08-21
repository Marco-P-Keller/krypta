# Krypta ECC — Security Architecture

**Version:** 2.0 (post-hardening)
**Last Updated:** 2026-04-21

## Overview

Krypta ECC is a high-security messenger disguised as a fully functional calculator.
Security and user privacy are the primary design goals. The system implements the
Signal Protocol (X3DH + Double Ratchet) with additional hardening measures.

See [THREAT_MODEL.md](THREAT_MODEL.md) for the full adversary model and attack surface analysis.

---

## 1. Encryption System

### Algorithm Stack
| Layer | Algorithm | Purpose |
|-------|-----------|---------|
| Key Agreement | X25519 (Curve25519) | ECDH key agreement (X3DH + Double Ratchet) |
| Signing | Ed25519 | PreKey signatures, Key Transparency commitments |
| Key Derivation | HKDF-SHA256 | Root key → chain key derivation |
| Chain KDF | HMAC-SHA256 | Chain key → message key derivation |
| Message Encryption | XChaCha20-Poly1305 | AEAD symmetric encryption with mandatory AAD |
| Hashing | SHA-256 / SHA-512 | Fingerprints, commitments / Safety Numbers |
| Password KDF | Argon2id (19 MiB, 2 iter) | Password-protected messages, access codes |
| Padding | Power-of-2 blocks (min 256B) | Traffic analysis protection |

### Double Ratchet Encryption (v2 — current)

```
1. Session init: X3DH key agreement (3-DH or 4-DH) → shared secret
2. DH Ratchet: X25519 key rotation per turn → forward secrecy + PCS
3. Symmetric Ratchet: HMAC-SHA256 chain → per-message keys
4. Encrypt: XChaCha20-Poly1305 with AAD = (associatedData || header)
5. AAD includes sender/recipient binding — prevents cross-conversation replay
6. Message keys zeroed after use (SensitiveBuffer.zeroBytes)
7. DH outputs zeroed after KDF consumption
```

### Decryption Flow

```
1. Check skipped message keys (out-of-order delivery, max 200, 7-day TTL)
2. DH ratchet step if sender's key changed
3. Derive message key from chain KDF
4. Decrypt with XChaCha20-Poly1305 + AAD verification
5. Verify sealed sender identity matches routing sender
6. Zero message key after decryption
```

### Key Properties
- **Forward secrecy**: DH ratchet on every turn + symmetric ratchet per message
- **Post-compromise security**: Fresh DH key pair on each ratchet step
- **No key reuse**: Every message encrypted with a unique derived key
- **Server-blind**: Server only sees encrypted payloads, never plaintext
- **Fail-closed**: v1 legacy messages rejected. No fallback paths without AAD.

---

## 2. Key Management

### Identity Key Pair
- Generated on device during first setup
- Stored in platform secure storage (iOS Keychain / Android Keystore)
- Hardware-wrapped when StrongBox/Secure Enclave available
- Private key NEVER leaves the device
- Public key registered on Firebase for key exchange
- Key Transparency commitment published on creation

### PreKey System
- **Signed PreKey**: X25519 pair, Ed25519 signature, rotated every 7 days (48h overlap)
- **One-Time PreKeys**: Pool of 100, replenished when <20 remain
- **Bundle**: Published to Firestore with signing public key (v2 mandatory)
- **Unsigned bundles (v1)**: Rejected — insecure (anyone with public key could forge)

### Key Storage
- iOS: Keychain with `first_unlock_this_device` accessibility + Secure Enclave ECIES P-256
- Android: Encrypted Keystore + StrongBox AES-256-GCM (TEE fallback)
- Database key wrapped by non-extractable hardware key
- Keys are zeroed in memory on cache clear (best-effort in Dart/GC)
- Cache TTL: 3 minutes for identity keys, 5 minutes for ratchet states

---

## 3. Session Establishment (X3DH)

### Outbound Session (Alice → Bob)
```
1. Fetch Bob's PreKeyBundle from Firestore
2. MANDATORY: Verify Ed25519 signature on signed prekey
3. MANDATORY: Reject v1 bundles without signing key
4. DH1 = DH(identity_priv, signed_prekey_pub)
5. DH2 = DH(ephemeral_priv, identity_pub)
6. DH3 = DH(ephemeral_priv, signed_prekey_pub)
7. DH4 = DH(ephemeral_priv, one_time_prekey_pub) [if available]
8. shared_secret = HKDF(DH1 || DH2 || DH3 [|| DH4])
9. MANDATORY: Reject all-zero shared secrets (small-subgroup attack)
10. Initialize Double Ratchet as sender
```

### Session Error Policies
| Error Type | Policy | Action |
|-----------|--------|--------|
| Signature verification failed | destroySession | Destroy ratchet, block until re-init |
| Zero shared secret | destroySession | Small-subgroup attack detected |
| Invalid key material | destroySession | Malformed keys |
| Legacy bundle (v1) | destroySession | Must re-publish with v2 |
| Key change detected | blockUntilVerified | Messaging blocked until Safety Number re-verified |
| Decryption failed | rejectMessage | Single message rejected, session intact |
| Replay detected | rejectMessage | Duplicate message dropped |
| Network error | retryTransient | Automatic retry |

---

## 4. Identity Verification

### Safety Numbers
- 60-digit number derived from both users' identity keys + user IDs
- Algorithm: SHA-512 iterated 5200x, symmetric (A→B == B→A)
- Version-managed: version upgrade forces re-verification
- Displayed as groups of 5 digits, embeddable in QR codes

### Key Transparency
- Hash-chained Ed25519-signed commitments per user
- Canonical format: version(1B) || epoch(8B BE) || key(32B) || prevHash(32B) || timestamp(8B BE)
- Gossip protocol: clients exchange chain heads in encrypted messages
- Split-view detection: same epoch + different hash = server MITM detected
- Stored in EncryptedLocalStore, published to Firestore `keyCommitments/{userId}/log`

### Trust States
- **unverified**: TOFU baseline, messaging allowed with warning
- **verified**: Out-of-band verification complete (QR or Safety Number)
- **keyChanged**: Key changed — messaging BLOCKED until re-verified
- **blocked**: User explicitly blocked — no communication

---

## 5. Calculator Disguise System

### Three-Code Architecture
| Code Type | Action | Security Level |
|-----------|--------|---------------|
| Secret Code | Opens real encrypted messenger | High |
| Decoy Code | Opens fake messenger with dummy data | Medium |
| Delete Code | Immediate full data wipe | Critical |

### Code Storage
- Codes hashed with Argon2id (19 MiB, 2 iterations) — not recoverable
- Stored in Flutter Secure Storage (Keychain/Keystore)
- Constant-time comparison for verification
- Calculator remains fully functional for normal arithmetic

---

## 6. Transport Security

### Sealed Sender
- Sender identity encrypted inside E2E payload (`_sid` field)
- Server routes via delivery tokens (random 32B, 24h expiry)
- Server's routing `sid` field is not trusted — sealed sender is authoritative

### Metadata Minimization
- ACKs: single-character type codes (d/r/u/x), no timestamps
- Push notifications: generic "new_message" only, no sender ID
- Typing indicators: local-only, never transmitted
- Message metadata (self-destruct, burn-after-read, password): inside E2E envelope

### Privacy Polling
- Alternative to FCM push: randomized polling intervals
- Jitter prevents timing analysis
- Configurable via Push Privacy Mode setting

### Timing Protection
- Random delay (50-200ms) added to decryption operations
- Constant-time byte comparisons for all secret verification
- Message padding hides true message length

---

## 7. Device Security

### Integrity Policy
- Graduated response: block / warnAndDegrade / warnOnly
- Default: warnAndDegrade (user warned, hardware features disabled)
- Fail-closed: unknown integrity state = worst case assumed
- Re-checked on app resume from background

### Hardware Key Binding
- Android: AES-256-GCM key in StrongBox (or TEE fallback)
- iOS: ECIES P-256 key in Secure Enclave
- Database encryption key wrapped by hardware key
- Hardware key is non-extractable — even keychain dumps are useless
- Opportunistic migration for existing installations

### RAM Exposure Minimization
- SensitiveBuffer utility for explicit byte zeroing
- DH outputs, message keys, skipped keys zeroed after use
- Periodic plaintext scrubbing (2-minute timer) for inactive chats
- Identity key cache TTL: 3 minutes
- Ratchet state cache TTL: 5 minutes

---

## 8. Data Architecture

### Local Storage (Primary)
- All data encrypted with XChaCha20-Poly1305
- Encryption key: random 256-bit, hardware-wrapped when available
- Atomic key rotation with temp directory swap
- Ratchet states loaded on-demand (not eagerly) to minimize RAM exposure

### Cloud Storage (Ephemeral Relay)
- Firebase Firestore used ONLY as message relay
- Messages deleted immediately after delivery
- No plaintext ever reaches the server
- Anonymous Firebase Auth (no PII collected)

### Collections
| Collection | Purpose | Retention |
|-----------|---------|-----------|
| `publicKeys/{userId}` | Identity public keys | Until wipe |
| `prekeys/{userId}` | PreKey bundles (v2 with signature) | Until rotation |
| `keyCommitments/{userId}/log` | Key Transparency chain | Append-only |
| `messages/{userId}/inbox` | Encrypted message relay | Deleted after delivery |
| `acks/{userId}/inbox` | Delivery/read ACKs | Deleted after processing |
| `deliveryTokens/{userId}` | Sealed Sender routing tokens | 24h rotation |
| `fcmTokens/{userId}` | Push notification tokens | Until logout/wipe |

---

## 9. Emergency Wipe System

### Trigger Points
- Delete code entry on calculator
- Emergency button in chat screens or settings
- Account deletion in settings

### Wipe Sequence (No Confirmation)
```
1. Zero all in-memory key bytes (ratchet states, identity keys)
2. Delete hardware wrapping key (makes wrapped data permanently inaccessible)
3. Delete local encrypted database (all .enc files)
4. Clear all secure storage entries (keys, codes, preferences)
5. Delete server data: messages, acks, public keys, prekeys, tokens, commitments
6. Delete Firebase account + sign out
7. Clear all in-memory caches
8. Reset app to setup state
```

### Design Principles
- **No confirmation dialogs** — instant action under duress
- **Best-effort** — continues even if individual steps fail
- **Hardware binding** ��� deleting the wrapping key is cryptographic destruction
- **Memory-safe** — zeroes key bytes before clearing references
