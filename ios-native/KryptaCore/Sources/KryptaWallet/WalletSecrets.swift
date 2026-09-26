import Foundation
import KryptaBitcoin

/// Wo der Schlüssel der Wallet liegt.
///
/// In der App der Schlüsselbund: der Zufall (aus dem die zwölf Wörter
/// entstehen) nur auf diesem Gerät und nur nach Face ID oder Gerätecode
/// lesbar, die öffentlichen Kontoschlüssel ohne Rückfrage. In Tests und im
/// Demo-Modus ein Wörterbuch im Speicher.
public protocol WalletSecrets: AnyObject, Sendable {
    var hasWallet: Bool { get }
    /// Öffentlicher Kontoschlüssel für dieses Netz (m/84'/c'/0').
    func accountKey(for network: BitcoinNetwork) -> ExtendedPublicKey?
    /// Legt eine neue Wallet an. Überschreibt nie eine vorhandene.
    func create() throws
    /// Der geheime Zufall. Fragt nach Face ID oder Code (`reason` steht im Dialog).
    @MainActor func entropy(reason: String) async throws -> SecretBytes
    /// Ersetzt die Wallet durch die aus diesen Wörtern.
    func restore(words: [String]) throws
}

/// Alles, was aus dem Zufall öffentlich abgeleitet und ohne Rückfrage
/// gebraucht wird.
public struct WalletPublicKeys: Codable, Equatable, Sendable {
    /// Münztyp 0 (Bitcoin) und 1 (alle Testnetze).
    public let main: ExtendedPublicKey
    public let test: ExtendedPublicKey

    public init(entropy: [UInt8]) throws {
        let seed = try Mnemonic.seed(entropy: entropy)
        main = try seed.withBytes { try WalletKeys.account(seed: $0, network: .mainnet) }
        test = try seed.withBytes { try WalletKeys.account(seed: $0, network: .testnet4) }
    }

    public func key(for network: BitcoinNetwork) -> ExtendedPublicKey {
        network == .mainnet ? main : test
    }
}

/// Im Speicher, für Tests und den Demo-Modus.
public final class MemoryWalletSecrets: WalletSecrets, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [UInt8]?
    private var keys: WalletPublicKeys?
    /// Für Tests: die nächste Rückfrage wird abgebrochen.
    public var cancelNext = false
    public private(set) var prompts = 0

    public init() {}

    public init(words: [String]) throws {
        try restore(words: words)
    }

    public var hasWallet: Bool { lock.withLock { stored != nil } }

    public func accountKey(for network: BitcoinNetwork) -> ExtendedPublicKey? {
        lock.withLock { keys?.key(for: network) }
    }

    public func create() throws {
        guard !hasWallet else { return }
        let entropy = Mnemonic.generateEntropy()
        let pub = try WalletPublicKeys(entropy: entropy.copy)
        lock.withLock {
            stored = entropy.copy
            keys = pub
        }
    }

    @MainActor
    public func entropy(reason: String) async throws -> SecretBytes {
        try lock.withLock {
            prompts += 1
            if cancelNext {
                cancelNext = false
                throw WalletFailure.authenticationCancelled
            }
            guard let stored else { throw WalletFailure.noWallet }
            return SecretBytes(stored)
        }
    }

    public func restore(words: [String]) throws {
        let entropy = try Mnemonic.entropy(words: words)
        let pub = try WalletPublicKeys(entropy: entropy.copy)
        lock.withLock {
            stored = entropy.copy
            keys = pub
        }
    }
}
