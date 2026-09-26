import Csecp256k1
import Foundation

/// secp256k1 über libsecp256k1 aus Bitcoin Core. Jede Rechnung mit einem
/// geheimen Schlüssel läuft dort, in konstanter Zeit; hier steht nur die
/// Übersetzung nach Swift.
public enum Secp256k1 {
    /// `SECP256K1_CONTEXT_NONE` und `SECP256K1_EC_COMPRESSED` aus secp256k1.h.
    /// Die Makros sind zusammengesetzt und kommen nicht zuverlässig nach Swift.
    static let contextNone: UInt32 = 1
    static let compressed: UInt32 = (1 << 1) | (1 << 8)

    /// Ein Kontext für alles, einmal erzeugt und mit Zufall verblendet
    /// (Schutz gegen Seitenkanäle beim Signieren). Danach nur gelesen, also
    /// von jedem Thread aus benutzbar.
    final class Context: @unchecked Sendable {
        let raw: OpaquePointer

        init() {
            guard let ctx = secp256k1_context_create(Secp256k1.contextNone) else {
                fatalError("secp256k1_context_create fehlgeschlagen")
            }
            var seed = SecureRandom.bytes(32)
            defer { seed.wipe() }
            guard secp256k1_context_randomize(ctx, seed) == 1 else {
                fatalError("secp256k1_context_randomize fehlgeschlagen")
            }
            raw = ctx
        }
    }

    static let context = Context()
    static var ctx: OpaquePointer { context.raw }

    /// 0 < k < n.
    public static func isValidPrivateKey(_ key: [UInt8]) -> Bool {
        key.count == 32 && secp256k1_ec_seckey_verify(ctx, key) == 1
    }

    /// Komprimierter öffentlicher Schlüssel (33 Bytes).
    public static func publicKey(privateKey: [UInt8]) throws -> [UInt8] {
        guard privateKey.count == 32 else { throw BitcoinError.invalidKey }
        var pub = secp256k1_pubkey()
        guard secp256k1_ec_pubkey_create(ctx, &pub, privateKey) == 1 else { throw BitcoinError.invalidKey }
        return serialize(pub)
    }

    /// Prüft und normalisiert einen öffentlichen Schlüssel (33 oder 65 Bytes)
    /// auf die komprimierte Form.
    public static func compressedPublicKey(_ key: [UInt8]) throws -> [UInt8] {
        try serialize(parse(key))
    }

    /// k + t mod n. Wirft, wenn t ≥ n oder das Ergebnis 0 ist (BIP32:
    /// dann ist dieser Index ungültig).
    public static func privateKeyTweakAdd(_ key: [UInt8], tweak: [UInt8]) throws -> [UInt8] {
        guard key.count == 32, tweak.count == 32 else { throw BitcoinError.invalidKey }
        var out = key
        guard secp256k1_ec_seckey_tweak_add(ctx, &out, tweak) == 1 else {
            out.wipe()
            throw BitcoinError.derivationFailed
        }
        return out
    }

    /// K + t·G.
    public static func publicKeyTweakAdd(_ key: [UInt8], tweak: [UInt8]) throws -> [UInt8] {
        guard tweak.count == 32 else { throw BitcoinError.invalidKey }
        var pub = try parse(key)
        guard secp256k1_ec_pubkey_tweak_add(ctx, &pub, tweak) == 1 else { throw BitcoinError.derivationFailed }
        return serialize(pub)
    }

    /// ECDSA mit deterministischer Nonce (RFC 6979) und kleinem S, wie
    /// Bitcoin es verlangt. Liefert DER. Zur Sicherheit wird die Signatur
    /// gleich wieder geprüft, bevor sie das Haus verlässt.
    public static func signECDSA(digest: [UInt8], privateKey: [UInt8]) throws -> [UInt8] {
        guard digest.count == 32, privateKey.count == 32 else { throw BitcoinError.signingFailed }
        var sig = secp256k1_ecdsa_signature()
        guard secp256k1_ecdsa_sign(ctx, &sig, digest, privateKey, nil, nil) == 1 else { throw BitcoinError.signingFailed }
        var der = [UInt8](repeating: 0, count: 72)
        var length = der.count
        guard secp256k1_ecdsa_signature_serialize_der(ctx, &der, &length, &sig) == 1 else { throw BitcoinError.signingFailed }
        let result = Array(der.prefix(length))
        let pub = try publicKey(privateKey: privateKey)
        guard verifyECDSA(signature: result, digest: digest, publicKey: pub) else { throw BitcoinError.signingFailed }
        return result
    }

    /// Prüft eine DER-Signatur. Wie Bitcoin Core: nur kleines S gilt.
    public static func verifyECDSA(signature: [UInt8], digest: [UInt8], publicKey: [UInt8]) -> Bool {
        guard digest.count == 32, !signature.isEmpty, let pub = try? parse(publicKey) else { return false }
        var sig = secp256k1_ecdsa_signature()
        guard secp256k1_ecdsa_signature_parse_der(ctx, &sig, signature, signature.count) == 1 else { return false }
        var pubkey = pub
        return secp256k1_ecdsa_verify(ctx, &sig, digest, &pubkey) == 1
    }

    static func parse(_ key: [UInt8]) throws -> secp256k1_pubkey {
        guard key.count == 33 || key.count == 65 else { throw BitcoinError.invalidKey }
        var pub = secp256k1_pubkey()
        guard secp256k1_ec_pubkey_parse(ctx, &pub, key, key.count) == 1 else { throw BitcoinError.invalidKey }
        return pub
    }

    static func serialize(_ pub: secp256k1_pubkey) -> [UInt8] {
        var pub = pub
        var out = [UInt8](repeating: 0, count: 33)
        var length = out.count
        let ok = secp256k1_ec_pubkey_serialize(ctx, &out, &length, &pub, compressed)
        precondition(ok == 1 && length == 33)
        return out
    }
}
