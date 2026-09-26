import Foundation

/// Welches Bitcoin. Die App nimmt das echte (`mainnet`); die Testnetze gibt
/// es für Tests mit Spielgeld.
public enum BitcoinNetwork: String, Codable, CaseIterable, Sendable {
    case mainnet = "main"
    case testnet4 = "test4"
    case signet
    case regtest

    /// Präfix der Segwit-Adressen.
    public var hrp: String {
        switch self {
        case .mainnet: "bc"
        case .testnet4, .signet: "tb"
        case .regtest: "bcrt"
        }
    }

    /// BIP44-Münztyp: 0 für echtes Geld, 1 für alle Testnetze.
    public var coinType: UInt32 { self == .mainnet ? 0 : 1 }

    public var isTest: Bool { self != .mainnet }

    var p2pkhVersion: UInt8 { self == .mainnet ? 0x00 : 0x6F }
    var p2shVersion: UInt8 { self == .mainnet ? 0x05 : 0xC4 }

    /// Versionsbytes für erweiterte Schlüssel (xpub/tpub).
    public var xpubVersion: UInt32 { self == .mainnet ? 0x0488_B21E : 0x0435_87CF }
    public var xprvVersion: UInt32 { self == .mainnet ? 0x0488_ADE4 : 0x0435_8394 }

    /// Die voreingestellte Esplora-Schnittstelle (mempool.space).
    public var defaultEsplora: URL {
        switch self {
        case .mainnet: URL(string: "https://mempool.space/api/")!
        case .testnet4: URL(string: "https://mempool.space/testnet4/api/")!
        case .signet: URL(string: "https://mempool.space/signet/api/")!
        case .regtest: URL(string: "http://127.0.0.1:3002/")!
        }
    }

    /// Wo man eine Transaktion ansehen kann.
    public func explorerURL(txid: String) -> URL? {
        switch self {
        case .mainnet: URL(string: "https://mempool.space/tx/\(txid)")
        case .testnet4: URL(string: "https://mempool.space/testnet4/tx/\(txid)")
        case .signet: URL(string: "https://mempool.space/signet/tx/\(txid)")
        case .regtest: nil
        }
    }
}
