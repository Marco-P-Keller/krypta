# Security Release Checklist

**Last Updated:** 2026-04-21 (post-hardening Tasks 1-12)

Check all items before each release. A single unchecked item blocks the release.

## Code Hygiene

- [ ] `dart analyze lib/` — 0 issues
- [ ] `flutter test` — all tests pass (239+ tests)
- [ ] No `debugPrint` calls that include `$e` in crypto/storage/messenger code
- [ ] No `print()` calls anywhere in lib/
- [ ] No hardcoded keys, tokens, or passwords
- [ ] No `TODO` or `FIXME` in security-critical code
- [ ] `KryptaKeyPair.toString()` does not expose key bytes

## Crypto — Cipher Suite

- [ ] All message encryption uses v2 Double Ratchet (v1 rejected entirely)
- [ ] XChaCha20-Poly1305 with mandatory AAD on all encrypt operations
- [ ] HKDF info strings are versioned (`KryptaDoubleRatchet-v1`)
- [ ] Password-protected messages use Argon2id v2 (PBKDF2 v1 rejected)
- [ ] Access codes and vault password stored as Argon2id hash (never plaintext)
- [ ] Constant-time comparison (`_constantTimeEquals`) for all secret verification

## Crypto — Double Ratchet

- [ ] Ratchet state persisted after every send/receive
- [ ] Skipped message keys limit enforced (max 200)
- [ ] Skipped message keys expire after 7 days (TTL-based prune)
- [ ] DH ratchet step generates fresh X25519 key pairs
- [ ] DH outputs zeroed after KDF consumption (`SensitiveBuffer.zeroBytes`)
- [ ] Message keys zeroed after encrypt/decrypt
- [ ] Associated data includes sender+recipient binding in AAD
- [ ] All-zero DH shared secrets rejected (small-subgroup attack)
- [ ] Key lengths strictly validated (32 bytes for X25519)

## Crypto — X3DH Session

- [ ] Ed25519 signature verified on signed prekeys before session creation
- [ ] v1 unsigned prekey bundles rejected (no fallback)
- [ ] Typed session errors with defined policies (destroy/block/reject/retry)
- [ ] Zero shared secret detection and rejection
- [ ] Fail-closed: unknown error → worst-case policy applied

## PreKeys

- [ ] Signed prekey rotated if > 7 days old
- [ ] Previous signed prekey kept for 48h overlap window
- [ ] One-time prekey pool replenished if < 20
- [ ] PreKey bundle published with Ed25519 signature (v2 mandatory)
- [ ] Private key bytes zeroed on wipe

## Identity Verification

- [ ] Safety Numbers: 60-digit, SHA-512 iterated 5200x, symmetric
- [ ] Key change → trustState=keyChanged → messaging BLOCKED
- [ ] Key change only resolved by re-verification (QR or Safety Number)
- [ ] Block → unblock returns to keyChanged (not unverified)
- [ ] TOFU baseline (`firstSeenIdentityKey`) recorded on first contact
- [ ] Key change counter tracks frequency for risk assessment

## Key Transparency

- [ ] Commitments signed with Ed25519 derived from identity key
- [ ] Hash chain: each commitment includes SHA-256 of predecessor
- [ ] Monotonic epochs: strictly increasing, gaps detected
- [ ] Gossip proofs embedded in encrypted message payloads (`_kt`)
- [ ] Split-view detection: same epoch + different hash = attack
- [ ] Contact `transparencyVerified` set to false on chain break

## Transport Security

- [ ] Sealed Sender: sender identity inside encrypted payload (`_sid`)
- [ ] Sealed sender identity mandatory for v2 messages (rejected if missing)
- [ ] Sealed sender mismatch with routing sender → rejected
- [ ] Delivery tokens: random 32B, 24h expiry, rotated on each send
- [ ] ACKs: single-character type codes (d/r/u/x), no timestamps
- [ ] Push notifications: generic "new_message" only, no sender ID in FCM
- [ ] Typing indicators: local-only, never transmitted to server

## Timing & Traffic Analysis

- [ ] Message padding: power-of-2 blocks, minimum 256 bytes
- [ ] Decryption delay: random 50-200ms (TimingProtection)
- [ ] Privacy polling: randomized intervals with jitter
- [ ] Constant-time byte comparison in all security-critical paths

## Storage — Local

- [ ] All local data encrypted (chats, messages, contacts, ratchet states, KT logs)
- [ ] Database encryption key in platform keychain
- [ ] Hardware key wrapping when StrongBox/Secure Enclave available
- [ ] Software key copy deleted after successful hardware wrapping
- [ ] Storage key rotation API available (`rotateStorageKey()`)
- [ ] Ratchet states loaded on-demand (not eagerly loaded at init)
- [ ] Ratchet state cache TTL: 5 minutes with eviction
- [ ] No plaintext secrets in SharedPreferences or unencrypted files

## Storage — Server (Firestore)

- [ ] Messages deleted after delivery (ephemeral relay)
- [ ] ACKs deleted after processing
- [ ] `keyCommitments/{userId}/log` is append-only
- [ ] `deleteAllUserData()` cleans all collections including commitments
- [ ] Replay protection: processed message IDs persisted (30-day TTL, 50K cap)

## Device Security

- [ ] Device integrity check on app start and resume
- [ ] Graduated policy: block/warnAndDegrade/warnOnly (default: warnAndDegrade)
- [ ] Fail-closed: check failure → worst-case assumed
- [ ] Hardware features disabled on compromised devices (block/warnAndDegrade)
- [ ] Hardware wrapping key: non-extractable (StrongBox/Secure Enclave)
- [ ] Opportunistic migration from software to hardware key wrapping

## RAM Exposure

- [ ] SensitiveBuffer utility used for all key zeroing
- [ ] Identity key cache TTL: 3 minutes
- [ ] Ratchet state cache TTL: 5 minutes
- [ ] Periodic plaintext scrubbing: 2-minute timer for inactive chats
- [ ] DH outputs zeroed immediately after KDF consumption
- [ ] Message keys zeroed after single use
- [ ] Skipped keys zeroed on consumption and TTL expiry
- [ ] Comprehensive wipe: all ratchet state keys zeroed before clearing

## Wipe

- [ ] Emergency wipe: keys → hardware key → local store → secure storage → server → auth → cache
- [ ] Delete code on calculator triggers same wipe sequence (no confirmation)
- [ ] Hardware wrapping key deleted → wrapped data permanently inaccessible
- [ ] Private key bytes zeroed before reference clearing
- [ ] Expired messages cleaned up on app start
- [ ] Self-destruct timer running while app is active

## Decoy

- [ ] Decoy files always exist on disk (even if decoy never used)
- [ ] Screenshot protection enabled in both real and decoy modes
- [ ] Decoy data stored in separate `decoy_*` namespace
- [ ] No forensic distinguishers between real/decoy screen state

## Platform

- [ ] Root/jailbreak detection with graduated policy
- [ ] Screenshot protection on all sensitive screens (FLAG_SECURE)
- [ ] Biometric re-auth on app resume (if enabled)
- [ ] Portrait orientation locked

## Tests

- [ ] `flutter test test/security/` — all 239+ tests pass
- [ ] Double Ratchet: basic, bidirectional, wrong key, tamper, nonce uniqueness, serialization
- [ ] Encryption: keygen, E2E roundtrip, tamper, local storage, Argon2id, password
- [ ] Safety Numbers: symmetry, determinism, uniqueness, formatting, version upgrade
- [ ] Identity Verification: trust states, key change tracking, QR, fingerprints
- [ ] PreKey Signatures: Ed25519 signing, v1 rejection, verification
- [ ] Sealed Sender: token generation, sender embedding, extraction
- [ ] Privacy Polling: interval randomization, jitter, bounds
- [ ] Timing Protection: delay range, randomness
- [ ] Device Integrity: policy enforcement, graduated response, fail-closed
- [ ] Hardware Binding: level detection, wrap/unwrap, integrity integration
- [ ] Sensitive Buffer: zeroing, dispose, use-after-dispose, copy
- [ ] Key Transparency: commitment signing, chain integrity, tampering, split-view
- [ ] Session Errors: policy mapping, error hierarchy
- [ ] Security Hardening: control messages, padding, X3DH validation
- [ ] Wipe/Self-Destruct: expiry, burn-after-read, serialization
