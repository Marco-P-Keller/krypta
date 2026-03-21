# Krypta ECC — Security Architecture

## Overview

Krypta ECC is a high-security messenger disguised as a fully functional calculator.
Security and user privacy are the primary design goals.

---

## 1. Encryption System

### Algorithm Stack
| Layer | Algorithm | Purpose |
|-------|-----------|---------|
| Key Exchange | X25519 (Curve25519) | ECDH key agreement |
| Key Derivation | HKDF-SHA256 | Derive encryption keys from shared secrets |
| Message Encryption | XChaCha20-Poly1305 | AEAD symmetric encryption |
| Hashing | SHA-256 | Code hashing, integrity checks |

### Encryption Flow (Sending a Message)

```
1. Sender generates ephemeral X25519 key pair
2. Sender performs ECDH: ephemeral_private × recipient_public → shared_secret
3. Derive encryption key via HKDF(shared_secret, "krypta-ecc-message-v1")
4. Encrypt plaintext with XChaCha20-Poly1305 using derived key
5. Transmit: { ciphertext, nonce, ephemeral_public_key }
```

### Decryption Flow (Receiving a Message)

```
1. Recipient performs ECDH: identity_private × ephemeral_public → shared_secret
2. Derive same encryption key via HKDF
3. Decrypt ciphertext with XChaCha20-Poly1305
4. Store plaintext in local encrypted database only
```

### Key Properties
- **Forward secrecy**: Each message uses a fresh ephemeral key pair
- **No key reuse**: Ephemeral keys are discarded after encryption
- **Server-blind**: Server only sees encrypted payloads, never plaintext

---

## 2. Key Management

### Identity Key Pair
- Generated on device during first setup
- Stored in platform secure storage (iOS Keychain / Android Keystore)
- Private key NEVER leaves the device
- Public key registered on Firebase for key exchange

### Key Storage
- iOS: Keychain with `first_unlock_this_device` accessibility
- Android: Encrypted Keystore
- Keys are wiped on emergency delete

---

## 3. Calculator Disguise System

### Three-Code Architecture
| Code Type | Action | Security Level |
|-----------|--------|---------------|
| Secret Code | Opens real encrypted messenger | High |
| Decoy Code | Opens fake messenger with dummy data | Medium |
| Delete Code | Immediate full data wipe | Critical |

### Code Storage
- Codes stored in Flutter Secure Storage (Keychain/Keystore)
- Never stored in plaintext on disk
- Code checking happens locally, no network calls

### Detection Logic
- Codes are checked when user presses "=" on calculator
- Calculator remains fully functional for normal arithmetic
- No visual indication that codes exist

---

## 4. Data Architecture

### Local Storage (Primary)
- All messages stored locally in encrypted format
- Encryption keys derived from device-specific secrets
- Database encrypted at rest

### Cloud Storage (Temporary Relay)
- Firebase Firestore used ONLY as message relay
- Messages auto-deleted after delivery (60s grace period)
- Messages auto-deleted after 24h regardless of status
- Server stores ONLY encrypted ciphertext
- Firestore security rules enforce access control

### Data Flow
```
Sender Device → Encrypt → Firebase Relay → Download → Decrypt → Recipient Device
                              ↓
                    Auto-delete after delivery
```

---

## 5. Emergency Wipe System

### Trigger Points
- Delete code entry on calculator
- Emergency button (⚠️) in chat screens
- Emergency button in settings
- Account deletion in settings

### Wipe Sequence (No Confirmation)
```
1. Delete all encryption keys from secure storage
2. Delete local encrypted database
3. Clear all secure storage entries (codes, preferences)
4. Sign out from Firebase
5. Attempt to delete Firebase anonymous account
6. Clear in-memory caches
7. Reset app to setup state
```

### Design Principles
- **No confirmation dialogs** — instant action
- **Best-effort** — continues even if individual steps fail
- **Parallel execution** — key deletion and storage wipe run simultaneously
- **Memory-safe** — clears in-memory key caches

---

## 6. Firebase Security Rules

### Firestore Rules Summary
- Public keys: authenticated users can read any; can only write their own
- Messages: sender can create; only recipient can read/delete
- FCM tokens: users can only manage their own
- Everything else: denied

### Authentication
- Anonymous Firebase Auth only
- No phone number, no email
- No PII collected

---

## 7. Self-Destructing Messages

### Timer Options
- 30 seconds, 5 minutes, 1 hour, 1 day, 1 week

### Behavior
- Timer starts when message is read by recipient
- Message deleted from local storage after timer expires
- Burn-after-read: delete immediately after first read
- Server relay messages always deleted (TTL is separate)

---

## 8. Platform Security Features

### iOS
- Keychain storage for secrets
- Data protection: Complete Until First Unlock
- Screenshot protection where API allows

### Android
- FLAG_SECURE for screenshot blocking
- Keystore for key material
- Encrypted shared preferences

### Biometric Authentication (Optional)
- Face ID / Touch ID (iOS)
- Fingerprint / Face Unlock (Android)
- Required AFTER correct code entry (second factor)

---

## 9. App Store Compliance

### Apple Guidelines Compliance
- Calculator is fully functional (legitimate utility)
- No misleading privacy claims
- Encryption is a standard privacy feature (Signal, Telegram precedent)
- Proper privacy nutrition labels
- No hidden malicious behavior

### Privacy Disclosures
- Data collected: None (anonymous auth has no PII)
- Data linked to user: None
- Data used to track: None
- Encryption: Yes, end-to-end

---

## 10. Future Security Enhancements

### Double Ratchet Protocol
- Upgrade from per-message ephemeral keys to full Double Ratchet
- Provides continuous forward secrecy and break-in recovery
- Based on Signal Protocol specification

### Panic Shake
- Device shake detection triggers emergency wipe
- Configurable sensitivity

### Hidden Chat Folders
- Additional layer within messenger for ultra-sensitive conversations
- Separate password protection

### Relay Anonymization
- Route messages through multiple relay nodes
- Prevent traffic analysis on server side
