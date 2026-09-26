import CryptoKit
import Foundation

/// ML-KEM-768 (FIPS 203) aus CryptoKit — ab iOS 26.
///
/// Wird im Handschlag zusätzlich zu X25519 verwendet (hybrid, wie Signals
/// PQXDH): Wer heute mitschneidet und in Jahren einen Quantenrechner hat,
/// müsste beides brechen. Ältere Systeme und die Flutter-Fassung können es
/// nicht; mit ihnen bleibt der Handschlag rein klassisch.
public enum PostQuantum {
    public static let publicKeyLength = 1184
    public static let ciphertextLength = 1088

    public static var isAvailable: Bool {
        if #available(iOS 26, macOS 26, *) { return true }
        return false
    }

    /// Neues Paar. Aufbewahrt wird nur der 64-Byte-Seed.
    public static func generate() throws -> (seed: Data, publicKey: Data) {
        guard #available(iOS 26, macOS 26, *) else { throw CryptoError.postQuantumUnavailable }
        let key = try MLKEM768.PrivateKey.generate()
        return (key.seedRepresentation, key.publicKey.rawRepresentation)
    }

    /// Absender: gemeinsames Geheimnis und das Chiffrat für die Empfängerin.
    public static func encapsulate(to publicKey: Data) throws -> (sharedSecret: Data, ciphertext: Data) {
        guard #available(iOS 26, macOS 26, *) else { throw CryptoError.postQuantumUnavailable }
        guard publicKey.count == publicKeyLength else { throw CryptoError.invalidKeyLength }
        let result = try MLKEM768.PublicKey(rawRepresentation: publicKey).encapsulate()
        return (result.sharedSecret.withUnsafeBytes { Data($0) }, result.encapsulated)
    }

    /// Empfängerin: dasselbe Geheimnis aus dem Chiffrat. Ein verfälschtes
    /// Chiffrat ergibt (implizite Ablehnung) ein falsches Geheimnis — die
    /// erste Nachricht lässt sich dann nicht entschlüsseln.
    public static func decapsulate(_ ciphertext: Data, seed: Data, publicKey: Data) throws -> Data {
        guard #available(iOS 26, macOS 26, *) else { throw CryptoError.postQuantumUnavailable }
        guard ciphertext.count == ciphertextLength else { throw CryptoError.malformed("kem ciphertext") }
        let pub = try MLKEM768.PublicKey(rawRepresentation: publicKey)
        let key = try MLKEM768.PrivateKey(seedRepresentation: seed, publicKey: pub)
        return try key.decapsulate(ciphertext).withUnsafeBytes { Data($0) }
    }
}
