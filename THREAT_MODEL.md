# Krypta ECC — Threat Model

**Version:** 3.0
**Date:** 2026-04-22
**Branch:** security/hardening
**Status:** Post-hardening (Tasks 1-14 + v3 message format migration complete)

---

## 1. Security Objectives

| Objective | Description |
|-----------|-------------|
| **Confidentiality** | Messages readable only by sender and recipient. Server, ISP, and device thieves learn nothing. |
| **Forward Secrecy** | Compromise of current keys cannot decrypt past messages. |
| **Post-Compromise Security** | After a key compromise, security is automatically restored within one DH ratchet step. |
| **Sender Anonymity** | Server cannot determine who is sending messages to whom (Sealed Sender). |
| **Deniability** | No cryptographic proof that a specific user sent a specific message. |
| **Anti-Forensics** | Emergency wipe destroys all evidence. Calculator disguise provides plausible deniability. |
| **Key Integrity** | Users can verify they're talking to the right person, not an impostor (Safety Numbers + Key Transparency). |
| **Metadata Minimization** | Server learns as little as possible about communication patterns. |

---

## 2. Adversary Model

### Adversary Tiers

| Tier | Adversary | Capabilities | Examples |
|------|-----------|--------------|----------|
| **T1** | Passive network observer | Sees encrypted traffic, timing, volume | ISP, Wi-Fi sniffing |
| **T2** | Compromised server | Controls Firestore relay, can read/modify server data | Rogue Firebase admin, legal order |
| **T3** | Active MITM | Can intercept and modify messages in transit | State-level actor on network path |
| **T4** | Device attacker (cold) | Physical access to locked device | Theft, border search |
| **T5** | Device attacker (hot) | Physical access to unlocked device, or malware | Shoulder surfing, spyware |
| **T6** | Coercive adversary | Forces user to unlock device | Authoritarian regime, coerced unlock |

### What Each Adversary Learns

| Adversary | Can Learn | Cannot Learn |
|-----------|-----------|--------------|
| **T1** | That Krypta traffic exists, timing patterns | Message content, who talks to whom (Sealed Sender), message types |
| **T2** | Encrypted message blobs, public keys, timing | Message content, sender identity (Sealed Sender), message metadata (inside E2E envelope) |
| **T3** | Same as T2 + can attempt key substitution | Message content (key substitution detected by Safety Numbers + Key Transparency) |
| **T4** | Device exists, calculator app is installed | Encrypted data (if device locked), secret code, message content |
| **T5** | Calculator app, possibly decoy messenger | Real messenger (if decoy code entered), message content (if secret code not entered) |
| **T6** | Decoy messenger and decoy data | Real messenger (user enters decoy code under duress), real contacts/messages |

---

## 3. Attack Surface Analysis

### 3.1 Cryptographic Protocol

| Attack | Mitigation | Residual Risk |
|--------|-----------|---------------|
| **Key compromise** | Double Ratchet provides PCS — security restored on next DH step | Window between compromise and next DH ratchet |
| **Replay attack** | Monotonic counters per chat + processed message ID set (30-day TTL, 50K cap) | None — replayed messages are rejected |
| **Downgrade attack** | v1 messages rejected entirely. v1 prekey bundles rejected. No fallback paths. | None — strict v2-only enforcement |
| **Small-subgroup attack** | All-zero DH outputs rejected. Key lengths strictly validated (32 bytes). | None |
| **Ratchet skip DoS** | Max 200 skipped messages. Skipped keys pruned after 7 days. Oldest-first eviction. | Legitimate message loss if >200 messages skipped |
| **Weak PRNG** | Platform CSPRNG via `dart:math` `Random.secure()` and cryptography package | Platform PRNG quality (out of scope) |

### 3.2 Key Management

| Attack | Mitigation | Residual Risk |
|--------|-----------|---------------|
| **Key extraction from memory** | 3-min cache TTL, explicit byte zeroing (SensitiveBuffer), periodic RAM scrubbing | Dart GC may retain copies — best-effort |
| **Key extraction from storage** | Platform keychain (iOS Keychain, Android Keystore) + hardware wrapping (StrongBox/Secure Enclave) | Rooted device can access keychain |
| **Key substitution (MITM)** | Safety Numbers (60-digit, SHA-512 iterated 5200x), QR verification, Key Transparency hash chain | User must actually verify Safety Numbers |
| **Split-view attack** | Key Transparency gossip protocol detects if server shows different keys to different users | Requires at least one message exchange to detect |
| **Prekey substitution** | Ed25519 signature on signed prekeys. v1 unsigned bundles rejected. | Signing key binding via Safety Number verification |
| **Key change without detection** | Key change blocks messaging until re-verification. TOFU baseline tracked. Change counter for risk assessment. | First-contact TOFU is trust-on-first-use by definition |

### 3.3 Transport & Metadata

| Attack | Mitigation | Residual Risk |
|--------|-----------|---------------|
| **Traffic analysis** | Message padding to power-of-2 blocks (min 256B). Privacy polling with randomized intervals. | Timing correlation still possible at endpoints |
| **Sender identification** | Sealed Sender: delivery tokens, sender identity inside encrypted envelope only | Server sees delivery token (rotated every 24h) |
| **Timing side channels** | TimingProtection adds random delay (50-200ms) to decryption. Constant-time byte comparisons throughout. | Dart's JIT may introduce non-constant-time paths |
| **Push notification metadata** | Push Privacy Mode: generic "new_message" notification only, no sender ID in FCM payload | FCM infrastructure sees device token |
| **Typing indicator leaks** | Typing indicators are local-only — never sent to server | None |
| **ACK metadata** | Control messages (ACKs, deletes, reads, unlocks) travel through the encrypted message channel as v3 `_ctrl` payloads — HMAC-SHA256 signed, counter-protected, sender-bound. Server cannot distinguish control from content messages. Legacy plaintext ACKs deprecated. | None — server sees only encrypted blobs |

### 3.4 Device Security

| Attack | Mitigation | Residual Risk |
|--------|-----------|---------------|
| **Rooted/jailbroken device** | Graduated integrity policy (block/warnAndDegrade/warnOnly). Hardware features disabled on compromised devices. | Detection evasion by sophisticated root hiders |
| **Forensic data recovery** | XChaCha20-Poly1305 encryption at rest. Emergency wipe destroys all keys. Hardware-bound key makes extraction useless. | SSD wear leveling may retain data fragments |
| **Cold boot attack** | Periodic RAM scrubbing (2-min timer). Key cache TTL (3 min). Explicit byte zeroing. | Dart GC limitations |
| **Evil maid (device tamper)** | Hardware key binding — database key wrapped by non-extractable hardware key | Requires StrongBox/Secure Enclave support |
| **Shoulder surfing** | Calculator disguise. No visual indication of messenger. Screenshot protection (FLAG_SECURE). | Camera recording of screen |
| **Forced unlock** | Three-code system: decoy code shows fake messenger. Delete code destroys everything. | Adversary may know about the code system |

### 3.5 Server-Side

| Attack | Mitigation | Residual Risk |
|--------|-----------|---------------|
| **Server reads messages** | E2E encryption — server only sees ciphertext | None (correct implementation assumed) |
| **Server modifies messages** | AEAD (Poly1305 MAC) detects tampering. AAD binds sender+recipient. | None |
| **Server drops messages** | Not mitigated by crypto — operational concern | Messages can be silently dropped |
| **Server stores messages** | Messages are ephemeral relay — deleted after delivery. 24h TTL. | Server could retain copies despite rules |
| **Server swaps keys** | Safety Numbers for out-of-band verification. Key Transparency hash chain + gossip protocol. | Requires user action to verify Safety Numbers |
| **Server withholds key updates** | Key Transparency epoch tracking detects staleness | Requires comparison with another client's view |
| **Legal compulsion** | Server has only encrypted blobs. Anonymous auth (no PII). No message content to produce. | Metadata (IP addresses, access patterns) in Firebase logs |

---

## 4. Cryptographic Design

### 4.1 Cipher Suite

```
Key Agreement:     X25519 (Curve25519 ECDH)
Signing:           Ed25519
Key Derivation:    HKDF-SHA256
Chain KDF:         HMAC-SHA256
Message Cipher:    XChaCha20-Poly1305 (AEAD, 24-byte nonce)
Hashing:           SHA-256 (fingerprints, commitments), SHA-512 (Safety Numbers)
Password KDF:      Argon2id (19 MiB, 2 iterations, 1 lane)
Padding:           Power-of-2 blocks, minimum 256 bytes
```

### 4.2 Protocol Stack

```
┌─────────────────────────────────────────┐
│           Application Layer             │
│  (self-destruct, burn-after-read, pw)   │
├─────────────────────────────────────────┤
│      v3 Inner Payload (encrypted)       │
│  _t: content  _sid: sender identity     │
│  _ctrl: control messages (ACK/del/read) │
│  _sd, _bar, _pw: message flags          │
│  _dt, _kt: sealed sender + KT gossip   │
├─────────────────────────────────────────┤
│       Control Message Protocol          │
│  HMAC-SHA256 signed, counter replay     │
│  protection, sender + chat binding      │
├─────────────────────────────────────────┤
│         Double Ratchet (v3)             │
│  KDF_RK: HKDF-SHA256  KDF_CK: HMAC-256 │
│  DH: X25519  Cipher: XChaCha20-Poly1305│
├─────────────────────────────────────────┤
│    X3DH Key Agreement (3-DH / 4-DH)    │
│  Identity × SignedPreKey                │
│  Ephemeral × Identity                   │
│  Ephemeral × SignedPreKey               │
│  Ephemeral × OneTimePreKey (optional)   │
├─────────────────────────────────────────┤
│       Sealed Sender Transport           │
│  Delivery tokens, sender inside E2E     │
├─────────────────────────────────────────┤
│    Key Transparency (gossip protocol)   │
│  Ed25519-signed hash-chained commits    │
├─────────────────────────────────────────┤
│      Firebase Relay (ephemeral)         │
│  Encrypted blobs only: {v,dh,n,pn,c,nc,m}│
└─────────────────────────────────────────┘
```

### 4.3 Key Lifecycle

| Key Type | Generation | Rotation | Storage | Destruction |
|----------|-----------|----------|---------|-------------|
| Identity (X25519) | Device setup | Never | Platform keychain + HW wrap | Emergency wipe |
| Signed PreKey | Messenger init | Every 7 days (48h overlap) | EncryptedLocalStore | Rotation / wipe |
| One-Time PreKey | Pool of 100 | Consumed on use, replenished <20 | EncryptedLocalStore | Single use / wipe |
| Ratchet Root Key | Session init | Every DH ratchet step | EncryptedLocalStore (5-min cache TTL) | Chat delete / wipe |
| Ratchet Chain Key | Per message | Every message (KDF chain) | In-memory, overwritten | Overwritten by KDF |
| Ratchet Message Key | Per message | Single use | In-memory only | Zeroed after use |
| Skipped Message Keys | Out-of-order rx | Max 200, 7-day TTL | In-memory / EncryptedLocalStore | TTL expiry / wipe |
| Database Key | First data write | Via rotateStorageKey() | Platform keychain + HW wrap | Emergency wipe |
| Hardware Wrapping Key | Device init | Never (non-extractable) | StrongBox / Secure Enclave | deleteHardwareKey() |

### 4.4 Key Transparency Chain

```
[Genesis]      [Epoch 1]       [Epoch 2]       [Epoch N]
    │              │               │               │
    v              v               v               v
┌────────┐   ┌────────┐     ┌────────┐     ┌────────┐
│ epoch=0│   │ epoch=1│     │ epoch=2│     │ epoch=N│
│ key=K₀ │──>│ key=K₀ │────>│ key=K₁ │────>│ key=Kₙ │
│ prev=0 │   │prev=H₀ │    │prev=H₁ │    │prev=Hₙ₋₁│
│ sig=σ₀ │   │ sig=σ₁ │    │ sig=σ₂ │    │ sig=σₙ │
└────────┘   └────────┘    └────────┘    └────────┘
  H₀=SHA256(C₀)  H₁=SHA256(C₁)  H₂=SHA256(C₂)

Cᵢ = version(1B) || epoch(8B BE) || key(32B) || prevHash(32B) || timestamp(8B BE)
σᵢ = Ed25519.sign(Cᵢ, identityPrivateKey)
```

**Split-view detection:** Clients include their view of the chain head (epoch + commitHash) in encrypted messages. If both clients see the same epoch but different hashes, the server is serving different key material — a MITM attack is in progress.

### 4.5 v3 Message Format

v3 moves ALL application metadata inside the E2E encrypted envelope. The server sees only ratchet protocol fields.

**Wire format (server-visible):**
```json
{
  "v": 3,
  "dh": "<ratchet DH public key, base64>",
  "n": "<message number>",
  "pn": "<previous chain length>",
  "c": "<ciphertext, base64>",
  "nc": "<nonce, base64>",
  "m": "<MAC, base64>"
}
```

**Inner payload (inside E2E ciphertext, invisible to server):**
```json
{
  "_t": "message content",
  "_sid": "sender-user-id",
  "_sd": 60000,
  "_bar": true,
  "_pw": true,
  "_dt": "delivery-token",
  "_kt": { "e": 5, "h": "commit-hash" },
  "_ctrl": { "type": "read", "chatId": "...", "mid": "...", ... }
}
```

| Field | Purpose | Present |
|-------|---------|---------|
| `_t` | Message text content | Always (empty for control-only) |
| `_sid` | Sender identity (sealed sender) | Always |
| `_sd` | Self-destruct timer (ms) | Optional |
| `_bar` | Burn-after-read flag | Optional |
| `_pw` | Password-protected flag | Optional |
| `_dt` | Delivery token for sealed sender | Optional |
| `_kt` | Key Transparency gossip (epoch + hash) | Optional |
| `_ctrl` | Signed control message (ACK/delete/read/unlock) | Control messages only |

**Security properties:**
- Server cannot distinguish content messages from control messages
- Sender identity is truly sealed — only inside encrypted payload
- Message flags (self-destruct, burn, password) invisible to server
- v2 backward compatibility: v2 messages accepted for receiving but `_ctrl` processing is v3-only (prevents server injection of fake control messages into v2 payloads)

### 4.6 Control Message Protocol

Control messages replace the legacy plaintext ACK system. They travel through the same Double Ratchet channel as content messages.

**HMAC key derivation:**
```
sharedSecret = X25519.DH(ourIdentityPrivate, theirIdentityPublic)
hmacKey = HKDF-SHA256(
  ikm: sharedSecret,
  salt: (none),
  info: "KryptaControlHMAC-v1",
  length: 32
)
```

**Signing:**
```
payload = type|chatId|messageId|senderId|timestamp|counter
signature = HMAC-SHA256(payload, hmacKey)
```

**Validation (fail-closed):**
1. Deserialize: any missing field → reject (FormatException)
2. Verify HMAC signature → reject if invalid
3. Check sender identity matches expected contact → reject on mismatch
4. Check monotonic counter > lastSeen → reject replay
5. Check timestamp within ±5 min (30s future tolerance) → reject expired/future
6. Apply action (delivered/read/delete/unlock)

**Receipt privacy:**
- Delivery receipts: disabled by default, user-configurable
- Read receipts: disabled by default, user-configurable
- When disabled, no control messages of that type are sent — contacts receive no status information

---

## 5. Data Flow Diagrams

### 5.1 Message Send (v3)

```
Sender                           Server (Firestore)                   Recipient
  │                                     │                                │
  │─── Trust gate check ──────────────>│                                │
  │    (blocked? key changed? trust?)   │                                │
  │─── Identity consistency verify ───>│                                │
  │                                     │                                │
  │  [Build v3 inner payload:]          │                                │
  │  [  _t: content, _sid: sender]      │                                │
  │  [  _sd, _bar, _pw: flags]         │                                │
  │  [  _dt: delivery token]            │                                │
  │  [  _kt: KT gossip epoch+hash]     │                                │
  │  [Double Ratchet encrypt]           │                                │
  │  [Pad to power-of-2]               │                                │
  │                                     │                                │
  │─── {v:3, dh, n, pn, c, nc, m} ───>│                                │
  │    (server sees ONLY ratchet fields)│                                │
  │                                     │─── Push notification ────────>│
  │                                     │    (generic, no sender ID)     │
  │                                     │                                │
  │                                     │<── Fetch encrypted blob ──────│
  │                                     │─── Delete after delivery ────>│ (ephemeral)
  │                                     │                                │
  │                                     │    [Double Ratchet decrypt]    │
  │                                     │    [Parse v3 inner payload]    │
  │                                     │    [Trust gate + identity check]│
  │                                     │    [Verify sealed sender _sid] │
  │                                     │    [Route _ctrl if present]    │
  │                                     │    [Process KT gossip]         │
  │                                     │    [Conditional delivery ACK]  │
```

### 5.2 Session Establishment (X3DH)

```
Alice (initiator)                Server                         Bob (responder)
  │                                │                                │
  │─── Fetch Bob's PreKeyBundle ──>│                                │
  │<── Bundle(idPub, spkPub, sig, opkPub) ─────────────────────────│
  │                                │                                │
  │  [Verify Ed25519 signature]    │                                │
  │  [Reject v1 unsigned bundles]  │                                │
  │  [3-DH or 4-DH key agreement] │                                │
  │  [Reject zero shared secrets]  │                                │
  │  [DoubleRatchet.initAsSender]  │                                │
  │                                │                                │
  │─── First encrypted message ──>│──────────────────────────────>│
  │    (includes session header)   │                                │
  │                                │    [Find signed prekey by ID]  │
  │                                │    [3-DH or 4-DH receiver]     │
  │                                │    [DoubleRatchet.initAsReceiver]│
```

---

## 6. Trust Model

### Trust Hierarchy

```
1. Out-of-band verification (QR code / Safety Number) — HIGHEST TRUST
   └── Proves: key owner is the person standing in front of you
   
2. Key Transparency chain verification — HIGH TRUST
   └── Proves: server is serving consistent keys to all parties
   
3. TOFU (Trust On First Use) — MODERATE TRUST
   └── Proves: key hasn't changed since first contact
   
4. Server-provided key (unverified) — LOWEST TRUST
   └── Proves: nothing (server could substitute any key)
```

### Trust State Machine

```
                    ┌──────────────┐
                    │  unverified  │ ← Initial state (TOFU)
                    └──────┬───────┘
                           │ QR verify / Safety Number
                           v
                    ┌──────────────┐
             ┌─────│   verified   │
             │     └──────┬───────┘
             │            │ Key change detected
             │            v
             │     ┌──────────────┐
             │     │  keyChanged  │ ← Sending BLOCKED
             │     └──────┬───────┘
             │            │ Re-verify via QR / Safety Number
             │            v
             │     ┌──────────────┐
             └────>│   verified   │
                   └──────────────┘

  Note: keyChanged → unverified is NOT allowed.
  Only re-verification can resolve a key change.
  Block → unblock returns to keyChanged (not unverified).
```

---

## 7. Hardening Measures (Tasks 1-12 + v3 Migration)

| # | Task | Security Property |
|---|------|------------------|
| 1 | Identity Verification | Safety Numbers bind user identity to crypto keys |
| 2 | Key-Change Detection | Key changes block messaging until re-verified (MITM protection) |
| 3 | Remove Legacy Fallback Paths | No v1 without AAD. No unsigned prekeys. No silent downgrades. |
| 4 | Session Failure Policy | Typed errors with defined policies (destroy/block/reject/retry). Fail-closed. |
| 5 | Metadata Minimization | Minimal ACK fields. No typing indicators sent. Short-code metadata. |
| 6 | Sealed Sender | Sender identity inside E2E envelope. Server routing via delivery tokens. |
| 7 | Push Privacy Mode | Generic push notifications. Privacy polling as alternative to FCM. |
| 8 | Timing Analysis Protection | Random decryption delay. Constant-time comparisons. Padded messages. |
| 9 | Device Integrity Policy | Graduated response (block/warnAndDegrade/warnOnly). Fail-closed. |
| 10 | Hardware-Backed Key Binding | StrongBox (Android AES-256-GCM) / Secure Enclave (iOS ECIES P-256). Non-extractable wrapping key. |
| 11 | RAM Exposure Minimization | SensitiveBuffer zeroing. DH/message/skipped key zeroing. Periodic plaintext scrubbing. Cache TTL. |
| 12 | Key Transparency | Hash-chained signed commitments. Gossip-based split-view detection. Auditable key history. |

### v3 Message Format Migration (Tasks 13-17)

| # | Task | Security Property |
|---|------|------------------|
| 13 | v3 Encrypted Inner Payload | ALL metadata (_sid, _sd, _bar, _pw, _dt, _kt) moved inside E2E envelope. Server sees only ratchet protocol fields {v, dh, n, pn, c, nc, m}. |
| 14 | Encrypted Control Messages | ACKs, deletes, read receipts, unlocks travel as `_ctrl` inside encrypted payload. HMAC-SHA256 signed (DH-derived key), monotonic counter replay prevention, sender + chat binding. Replaces plaintext ACK channel. |
| 15 | Centralized Trust Gates | Single `_validateSendPermission` / `_validateReceivePermission` functions enforce blocked, keyChanged, and trust checks before any send or receive. No bypass paths. |
| 16 | Receipt Privacy | Delivery and read receipts disabled by default. User-configurable toggles. When disabled, no status information leaks to contacts. |
| 17 | Fail-Closed Deserialization | ControlMessage.fromMap throws FormatException on any missing security field. No default values for counter (0), signature (''), or other fields. v2 messages cannot inject `_ctrl` (version >= 3 guard). |

---

## 8. Known Limitations & Residual Risks

### Dart/Flutter Platform Limitations

| Limitation | Impact | Mitigation |
|-----------|--------|-----------|
| **GC prevents guaranteed memory zeroing** | Private key bytes may persist in GC heap after zeroing | Best-effort zeroing + short cache TTL + periodic scrubbing |
| **String immutability** | Decrypted message text cannot be securely erased from RAM | Timer-based scrubbing of inactive chat content |
| **JIT non-constant-time** | Dart JIT may optimize constant-time loops into variable-time | Use of bitwise OR accumulator pattern; risk accepted |

### Operational Limitations

| Limitation | Impact | Mitigation |
|-----------|--------|-----------|
| **TOFU on first contact** | First contact is vulnerable to MITM until verified | Safety Numbers prominently shown; key change blocks messaging |
| **No server-side transparency auditor** | Split-view detection requires pairwise message exchange | Gossip protocol in every message; chain fingerprint for manual audit |
| **Message drop by server** | Server can silently drop messages | Out of scope for crypto — operational monitoring needed |
| **Firebase metadata in logs** | Google may log IP addresses and access patterns | Anonymous auth, no PII; consider Tor in future |
| **Root/jailbreak detection evasion** | Sophisticated root hiders can bypass detection | Hardware key binding provides defense-in-depth even on rooted devices |

### Intentional Non-Goals

| Non-Goal | Reason |
|----------|--------|
| **Group messaging** | Single-user E2E focus; group protocols (MLS/Sender Keys) add complexity |
| **Multi-device sync** | Single-device model simplifies key management and reduces attack surface |
| **Message delivery guarantee** | Ephemeral relay model — messages may be lost if recipient is offline too long |
| **Metadata-free communication** | Requires onion routing; Firebase relay inherently sees some metadata |

---

## 9. Incident Response

### Key Compromise Detected
1. Double Ratchet automatically restores security on next DH ratchet step
2. User sees key change warning → messaging blocked until re-verification
3. Old ratchet state destroyed, new session required
4. Safety Numbers will change — users must re-verify

### Split-View Attack Detected
1. ConsistencyChecker flags `splitView` result
2. Contact's `transparencyVerified` set to false
3. User should re-verify Safety Numbers out-of-band
4. Consider the server compromised — verify all contacts

### Device Compromise Detected
1. Device integrity check reports compromised
2. Policy action applied (block/warnAndDegrade/warnOnly)
3. Hardware features disabled (no wrapping key, no StrongBox/SE operations)
4. User warned via banner in messenger UI

### Emergency Wipe
1. Delete code on calculator → instant full wipe
2. Emergency button in settings/chat → same wipe sequence
3. Sequence: keys → local store → secure storage → server data → auth → memory
4. Best-effort: continues even if individual steps fail
5. Hardware wrapping key deleted → remaining wrapped data permanently inaccessible

---

## 10. Test Coverage

| Area | Tests | Verified Properties |
|------|-------|-------------------|
| Double Ratchet | 6 | Basic flow, bidirectional, wrong key, tamper, serialization, nonce uniqueness |
| Encryption | 12 | Keygen, E2E roundtrip, tamper detection, local storage, Argon2id, password messages |
| Safety Numbers | 10 | Symmetry, determinism, uniqueness, formatting, version upgrade |
| Identity Verification | 15 | Contact trust states, key change tracking, QR verification, fingerprints |
| PreKey Signatures | 10 | Ed25519 signing, v1 rejection, signature verification |
| Sealed Sender | 6 | Token generation, sender embedding, extraction |
| Privacy Polling | 8 | Interval randomization, jitter, bounds |
| Timing Protection | 6 | Delay range, randomness |
| Device Integrity | 31 | Policy enforcement, graduated response, fail-closed |
| Hardware Binding | 12 | Level detection, wrap/unwrap, device integrity integration |
| Sensitive Buffer | 12 | Zeroing, dispose, use-after-dispose, copy |
| Key Transparency | 44 | Commitment signing, chain integrity, tampering, serialization, split-view |
| Session Errors | 14 | Policy mapping, error hierarchy |
| Wipe/Self-Destruct | 8 | Expiry, burn-after-read, serialization |
| Security Hardening | 39 | Control messages (signing, verification, replay, fail-closed deserialization, serialization roundtrip, timestamp validation), counter persistence (isolation, clear, callbacks), padding, X3DH validation |
| **Total** | **~266** | |
