import Foundation

/// Ein Blockkopf (80 Bytes) und seine Arbeit.
public struct BlockHeader: Equatable, Sendable {
    public let raw: [UInt8]

    public init(_ raw: [UInt8]) throws {
        guard raw.count == 80 else { throw BitcoinError.invalidTransaction("Blockkopf") }
        self.raw = raw
    }

    /// Kennung wie im Block-Explorer.
    public var hash: String { Array(Hashes.hash256(raw).reversed()).hex }
    /// Merkle-Wurzel in der Byte-Reihenfolge des Kopfs.
    var merkleRoot: [UInt8] { Array(raw[36..<68]) }
    public var bits: UInt32 { UInt32(raw[72]) | UInt32(raw[73]) << 8 | UInt32(raw[74]) << 16 | UInt32(raw[75]) << 24 }

    /// Ziel aus `bits` als 32 Bytes (groß vorne). `nil`, wenn ungültig.
    static func target(bits: UInt32) -> [UInt8]? {
        let exponent = Int(bits >> 24)
        let mantissa = bits & 0x007F_FFFF
        guard bits & 0x0080_0000 == 0, mantissa != 0, exponent <= 32 else { return nil }
        var t = [UInt8](repeating: 0, count: 32)
        let m = [UInt8((mantissa >> 16) & 0xFF), UInt8((mantissa >> 8) & 0xFF), UInt8(mantissa & 0xFF)]
        for (i, byte) in m.enumerated() {
            let position = 32 - exponent + i
            if position < 0 { if byte != 0 { return nil } else { continue } }
            if position < 32 { t[position] = byte }
        }
        return t
    }

    /// Hash ≤ Ziel, und das Ziel mindestens so schwer wie `hardest`
    /// verlangt (ein kleineres Ziel ist mehr Arbeit).
    public func hasProofOfWork(maximumTarget: [UInt8]) -> Bool {
        guard let target = Self.target(bits: bits) else { return false }
        let hash = Array(Hashes.hash256(raw).reversed())
        return !target.lexicographicallyPrecedes(hash) && !maximumTarget.lexicographicallyPrecedes(target)
    }

    /// Das leichteste Ziel, das Krypta für eine Bestätigung akzeptiert.
    ///
    /// Bitcoin: Schwierigkeit 50 T (Anfang 2023; 2026 liegt sie weit
    /// darüber). Wer Krypta einen erfundenen Block als Bestätigung
    /// unterschieben will, muss so einen Block wirklich rechnen: Strom für
    /// sechsstellige Beträge. Testnetze: keine Untergrenze, ihre Blöcke sind
    /// ohnehin wertlos.
    public static func maximumTarget(for network: BitcoinNetwork) -> [UInt8] {
        switch network {
        case .mainnet:
            // 0xFFFF·2^208 / 50e12 in Kompaktform (Schwierigkeit 50,00003 T).
            return target(bits: 0x1705_A121)!
        case .testnet4, .signet, .regtest:
            return [UInt8](repeating: 0xFF, count: 32)
        }
    }
}

/// Merkle-Beweis (Esplora `/tx/:txid/merkle-proof`, wie Electrum): die
/// Nachbarn von unten nach oben und die Position im Block.
public enum MerkleProof {
    public static func root(txid: String, siblings: [String], position: Int) -> [UInt8]? {
        guard OutPoint.isTxid(txid), position >= 0, siblings.count <= 32, position >> siblings.count == 0 else { return nil }
        var current = Array([UInt8](hex: txid)!.reversed())
        for (level, sibling) in siblings.enumerated() {
            guard OutPoint.isTxid(sibling) else { return nil }
            let s = Array([UInt8](hex: sibling)!.reversed())
            current = (position >> level) & 1 == 1 ? Hashes.hash256(s + current) : Hashes.hash256(current + s)
        }
        return current
    }

    /// Steckt die Transaktion in diesem Block, und hat der Block echte Arbeit?
    public static func verify(txid: String, siblings: [String], position: Int, header: BlockHeader, network: BitcoinNetwork) -> Bool {
        guard let root = root(txid: txid, siblings: siblings, position: position) else { return false }
        return root == header.merkleRoot && header.hasProofOfWork(maximumTarget: BlockHeader.maximumTarget(for: network))
    }
}
