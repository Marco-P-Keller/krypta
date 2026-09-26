import Foundation

/// BIP32: Schlüsselbäume aus einem Seed.
///
/// Die Wallet braucht zwei Dinge daraus: den öffentlichen Kontoschlüssel
/// (m/84'/c'/0'), aus dem ohne Geheimnis jede Adresse entsteht, und beim
/// Senden die privaten Schlüssel der ausgegebenen Adressen. Beides leitet
/// `WalletKeys` ab; hier steht nur BIP32.
public enum HD {
    public static let hardened: UInt32 = 0x8000_0000

    /// „m/84'/0'/0'" → Indizes.
    public static func parsePath(_ path: String) throws -> [UInt32] {
        var parts = path.split(separator: "/").map(String.init)
        guard parts.first == "m" else { throw BitcoinError.derivationFailed }
        parts.removeFirst()
        return try parts.map { part in
            let isHardened = part.hasSuffix("'") || part.hasSuffix("h")
            guard let n = UInt32(isHardened ? String(part.dropLast()) : part), n < hardened else { throw BitcoinError.derivationFailed }
            return isHardened ? n | hardened : n
        }
    }
}

/// Erweiterter öffentlicher Schlüssel. Nicht geheim, aber privat: wer ihn
/// hat, sieht alle Adressen der Wallet.
public struct ExtendedPublicKey: Equatable, Hashable, Codable, Sendable {
    public let publicKey: [UInt8]
    public let chainCode: [UInt8]
    public let depth: UInt8
    public let parentFingerprint: UInt32
    public let childNumber: UInt32

    public init(publicKey: [UInt8], chainCode: [UInt8], depth: UInt8, parentFingerprint: UInt32, childNumber: UInt32) throws {
        guard chainCode.count == 32 else { throw BitcoinError.invalidKey }
        self.publicKey = try Secp256k1.compressedPublicKey(publicKey)
        self.chainCode = chainCode
        self.depth = depth
        self.parentFingerprint = parentFingerprint
        self.childNumber = childNumber
    }

    /// Die ersten vier Bytes von HASH160(Schlüssel).
    public var fingerprint: UInt32 {
        let h = Hashes.hash160(publicKey)
        return UInt32(h[0]) << 24 | UInt32(h[1]) << 16 | UInt32(h[2]) << 8 | UInt32(h[3])
    }

    /// CKDpub: nur nicht gehärtete Kinder.
    public func child(_ index: UInt32) throws -> ExtendedPublicKey {
        guard index < HD.hardened, depth < 255 else { throw BitcoinError.derivationFailed }
        var data = publicKey
        data.appendBE(index)
        var i = Hashes.hmacSHA512(key: chainCode, data: data)
        defer { i.wipe() }
        let key = try Secp256k1.publicKeyTweakAdd(publicKey, tweak: Array(i[0..<32]))
        return try ExtendedPublicKey(publicKey: key, chainCode: Array(i[32..<64]), depth: depth + 1, parentFingerprint: fingerprint, childNumber: index)
    }

    public func serialized(version: UInt32) -> String {
        var out = [UInt8]()
        out.appendBE(version)
        out.append(depth)
        out.appendBE(parentFingerprint)
        out.appendBE(childNumber)
        out.append(contentsOf: chainCode)
        out.append(contentsOf: publicKey)
        return Base58.encodeCheck(out)
    }

    /// Liest xpub/tpub/zpub …; die Version gibt der Aufrufer vor.
    public static func parse(_ text: String, version: UInt32) throws -> ExtendedPublicKey {
        guard let raw = Base58.decodeCheck(text), raw.count == 78 else { throw BitcoinError.invalidKey }
        var r = ByteReader(raw)
        let v = UInt32(beBytes: try r.read(4))
        guard v == version else { throw BitcoinError.invalidKey }
        let depth = try r.readByte()
        let parent = UInt32(beBytes: try r.read(4))
        let child = UInt32(beBytes: try r.read(4))
        let chain = try r.read(32)
        let key = try r.read(33)
        guard key[0] == 0x02 || key[0] == 0x03 else { throw BitcoinError.invalidKey }
        // Eine Wurzel hat weder Eltern noch Index (BIP32, Vektor 5).
        if depth == 0, parent != 0 || child != 0 { throw BitcoinError.invalidKey }
        return try ExtendedPublicKey(publicKey: key, chainCode: chain, depth: depth, parentFingerprint: parent, childNumber: child)
    }
}

/// Erweiterter privater Schlüssel. Lebt nur, solange signiert wird; der
/// Speicher wird beim Freigeben überschrieben.
public final class ExtendedPrivateKey: @unchecked Sendable {
    private var key: [UInt8]
    private var chain: [UInt8]
    public let depth: UInt8
    public let parentFingerprint: UInt32
    public let childNumber: UInt32

    init(key: [UInt8], chainCode: [UInt8], depth: UInt8, parentFingerprint: UInt32, childNumber: UInt32) {
        self.key = key
        self.chain = chainCode
        self.depth = depth
        self.parentFingerprint = parentFingerprint
        self.childNumber = childNumber
    }

    deinit {
        key.wipe()
        chain.wipe()
    }

    /// Wurzel aus dem 64-Byte-Seed (HMAC-SHA512 mit „Bitcoin seed").
    public static func master(seed: [UInt8]) throws -> ExtendedPrivateKey {
        guard (16...64).contains(seed.count) else { throw BitcoinError.invalidSeed }
        var i = Hashes.hmacSHA512(key: Array("Bitcoin seed".utf8), data: seed)
        defer { i.wipe() }
        let k = Array(i[0..<32])
        guard Secp256k1.isValidPrivateKey(k) else { throw BitcoinError.invalidSeed }
        return ExtendedPrivateKey(key: k, chainCode: Array(i[32..<64]), depth: 0, parentFingerprint: 0, childNumber: 0)
    }

    public var publicKey: ExtendedPublicKey {
        get throws {
            try ExtendedPublicKey(publicKey: Secp256k1.publicKey(privateKey: key), chainCode: chain, depth: depth, parentFingerprint: parentFingerprint, childNumber: childNumber)
        }
    }

    /// CKDpriv; gehärtet ab 2^31.
    public func child(_ index: UInt32) throws -> ExtendedPrivateKey {
        guard depth < 255 else { throw BitcoinError.derivationFailed }
        var data: [UInt8]
        if index >= HD.hardened {
            data = [0] + key
        } else {
            data = try Secp256k1.publicKey(privateKey: key)
        }
        data.appendBE(index)
        defer { data.wipe() }
        var i = Hashes.hmacSHA512(key: chain, data: data)
        defer { i.wipe() }
        let childKey = try Secp256k1.privateKeyTweakAdd(key, tweak: Array(i[0..<32]))
        let parent = try publicKey.fingerprint
        return ExtendedPrivateKey(key: childKey, chainCode: Array(i[32..<64]), depth: depth + 1, parentFingerprint: parent, childNumber: index)
    }

    public func derive(_ path: [UInt32]) throws -> ExtendedPrivateKey {
        var node = self
        for index in path { node = try node.child(index) }
        return node
    }

    /// Der rohe Schlüssel, geborgt — zum Signieren.
    public func withPrivateKey<T>(_ body: ([UInt8]) throws -> T) rethrows -> T {
        try body(key)
    }

    /// Nur für Tests (BIP32-Vektoren).
    public func serialized(version: UInt32) -> String {
        var out = [UInt8]()
        out.appendBE(version)
        out.append(depth)
        out.appendBE(parentFingerprint)
        out.appendBE(childNumber)
        out.append(contentsOf: chain)
        out.append(0)
        out.append(contentsOf: key)
        defer { out.wipe() }
        return Base58.encodeCheck(out)
    }
}

extension UInt32 {
    init(beBytes bytes: [UInt8]) {
        self = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    }
}
