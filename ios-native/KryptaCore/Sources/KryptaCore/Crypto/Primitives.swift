import CryptoKit
import Foundation
import Clibsodium

/// Fehler der Primitive. Absichtlich knapp: nach außen zählt nur, *dass*
/// etwas nicht stimmt, nicht was — eine Fehlermeldung ist sonst ein Orakel.
public enum CryptoError: Error, Equatable {
    case invalidKeyLength
    case zeroSharedSecret
    case authenticationFailed
    case malformed(String)
    case kdfFailed
}

/// Ein X25519-Schlüsselpaar. Die Bytes sind im selben Format wie in der
/// Flutter-Fassung (`extractPrivateKeyBytes` / `publicKey.bytes`), sodass
/// ein Schlüssel zwischen beiden Welten wandern kann.
public struct KeyPair: Equatable, Sendable {
    public var privateKey: Data
    public let publicKey: Data

    public init(privateKey: Data, publicKey: Data) {
        self.privateKey = privateKey.detached
        self.publicKey = publicKey.detached
    }

    public static func generate() -> KeyPair {
        let key = Curve25519.KeyAgreement.PrivateKey()
        return KeyPair(privateKey: key.rawRepresentation, publicKey: key.publicKey.rawRepresentation)
    }

    /// Das Paar zu einem vorhandenen privaten Schlüssel.
    public static func from(privateKey: Data) throws -> KeyPair {
        guard privateKey.count == 32 else { throw CryptoError.invalidKeyLength }
        let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        return KeyPair(privateKey: privateKey, publicKey: key.publicKey.rawRepresentation)
    }
}

public enum Primitives {
    // MARK: X25519

    /// Diffie-Hellman mit Längenprüfung und Abweisung eines Null-Ergebnisses
    /// (Punkt kleiner Ordnung — ohne diese Prüfung gäbe es keine Geheimhaltung).
    public static func dh(privateKey: Data, publicKey: Data) throws -> Data {
        guard privateKey.count == 32, publicKey.count == 32 else {
            throw CryptoError.invalidKeyLength
        }
        let priv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        let pub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey)
        let shared: SharedSecret
        do {
            shared = try priv.sharedSecretFromKeyAgreement(with: pub)
        } catch {
            // CryptoKit weist Punkte kleiner Ordnung selbst ab. Für uns ist
            // das derselbe Fall wie ein Null-Ergebnis.
            throw CryptoError.zeroSharedSecret
        }
        let bytes = shared.withUnsafeBytes { Data($0) }
        if bytes.isAllZero { throw CryptoError.zeroSharedSecret }
        return bytes
    }

    // MARK: Ed25519

    /// Signiert mit dem Ed25519-Schlüssel, der aus dem X25519-Identitätsseed
    /// entsteht — so, wie PreKeyManager.signPreKey es tut. Liefert
    /// (Signatur, Ed25519-Public-Key).
    public static func ed25519Sign(message: Data, seed: Data) throws -> (signature: Data, publicKey: Data) {
        guard seed.count == 32 else { throw CryptoError.invalidKeyLength }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        let signature = try key.signature(for: message)
        return (signature, key.publicKey.rawRepresentation)
    }

    public static func ed25519PublicKey(seed: Data) throws -> Data {
        try Curve25519.Signing.PrivateKey(rawRepresentation: seed).publicKey.rawRepresentation
    }

    public static func ed25519Verify(signature: Data, message: Data, publicKey: Data) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
            return false
        }
        return key.isValidSignature(signature, for: message)
    }

    // MARK: Hashes, HMAC, HKDF

    public static func hkdfSHA256(ikm: Data, salt: Data, info: Data, length: Int) -> Data {
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: salt,
            info: info,
            outputByteCount: length
        )
        return key.withUnsafeBytes { Data($0) }
    }

    public static func hmacSHA256(key: Data, message: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }

    public static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
    public static func sha512(_ data: Data) -> Data { Data(SHA512.hash(data: data)) }

    // MARK: XChaCha20-Poly1305 (libsodium)

    public struct SealedBox: Equatable, Sendable {
        public let ciphertext: Data
        public let nonce: Data
        public let mac: Data

        public init(ciphertext: Data, nonce: Data, mac: Data) {
            self.ciphertext = ciphertext
            self.nonce = nonce
            self.mac = mac
        }
    }

    /// Verschlüsselt mit zufälliger 24-Byte-Nonce. `nonce` nur für Tests.
    public static func xchachaSeal(_ plaintext: Data, key: Data, aad: Data, nonce: Data? = nil) throws -> SealedBox {
        try ensureSodium()
        guard key.count == 32 else { throw CryptoError.invalidKeyLength }
        let n = [UInt8](nonce ?? Data.random(count: 24))
        guard n.count == 24 else { throw CryptoError.malformed("nonce") }
        var k = [UInt8](key)
        defer { k.withUnsafeMutableBufferPointer { $0.update(repeating: 0) } }
        let m = [UInt8](plaintext), a = [UInt8](aad)
        var c = [UInt8](repeating: 0, count: m.count)
        var mac = [UInt8](repeating: 0, count: 16)
        var macLen: UInt64 = 0
        let rc = crypto_aead_xchacha20poly1305_ietf_encrypt_detached(
            &c, &mac, &macLen, m, UInt64(m.count), a, UInt64(a.count), nil, n, k
        )
        guard rc == 0 else { throw CryptoError.authenticationFailed }
        return SealedBox(ciphertext: Data(c), nonce: Data(n), mac: Data(mac))
    }

    public static func xchachaOpen(_ box: SealedBox, key: Data, aad: Data) throws -> Data {
        try ensureSodium()
        guard key.count == 32 else { throw CryptoError.invalidKeyLength }
        guard box.nonce.count == 24, box.mac.count == 16 else { throw CryptoError.authenticationFailed }
        var k = [UInt8](key)
        defer { k.withUnsafeMutableBufferPointer { $0.update(repeating: 0) } }
        let c = [UInt8](box.ciphertext), a = [UInt8](aad)
        var m = [UInt8](repeating: 0, count: c.count)
        let rc = crypto_aead_xchacha20poly1305_ietf_decrypt_detached(
            &m, nil, c, UInt64(c.count), [UInt8](box.mac), a, UInt64(a.count), [UInt8](box.nonce), k
        )
        guard rc == 0 else { throw CryptoError.authenticationFailed }
        return Data(m)
    }

    // MARK: Argon2id (libsodium)

    /// Argon2id mit den Parametern der Flutter-Fassung: 19 MiB, 2 Durchläufe,
    /// Parallelität 1, 32 Byte Ausgabe, Version 0x13.
    public static func argon2id(password: Data, salt: Data, memoryKiB: Int = 19456, iterations: Int = 2) throws -> Data {
        try ensureSodium()
        guard salt.count == Int(crypto_pwhash_SALTBYTES) else { throw CryptoError.malformed("salt") }
        var out = [UInt8](repeating: 0, count: 32)
        let pw = [CChar](password.map { CChar(bitPattern: $0) })
        let rc = crypto_pwhash(
            &out, 32, pw, UInt64(pw.count), [UInt8](salt),
            UInt64(iterations), memoryKiB * 1024, crypto_pwhash_ALG_ARGON2ID13
        )
        guard rc == 0 else { throw CryptoError.kdfFailed }
        return Data(out)
    }

    private static let sodiumReady: Bool = sodium_init() >= 0

    private static func ensureSodium() throws {
        guard sodiumReady else { throw CryptoError.kdfFailed }
    }
}
