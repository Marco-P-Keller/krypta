import Foundation
import KryptaBitcoin
import KryptaWallet

/// Einstellungen der Wallet, die nichts Geheimes enthalten.
@MainActor
enum WalletSettings {
    private static let networkKey = "wallet.network"

    /// Netze, die man in der App wählen kann (Regtest nur im Demo-Modus).
    static let selectable: [BitcoinNetwork] = [.mainnet, .testnet4, .signet]

    static var network: BitcoinNetwork {
        get {
            #if DEBUG
            if DemoMode.isActive || DemoMode.isOffline { return .regtest }
            #endif
            let raw = UserDefaults.standard.string(forKey: networkKey) ?? ""
            guard let n = BitcoinNetwork(rawValue: raw), selectable.contains(n) else { return .mainnet }
            return n
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: networkKey) }
    }

    /// Eigener Esplora-Server (z. B. der eigene Knoten), sonst mempool.space.
    static func server(for network: BitcoinNetwork) -> URL {
        if let text = UserDefaults.standard.string(forKey: "wallet.server.\(network.rawValue)"), let url = validServer(text) {
            return url
        }
        return network.defaultEsplora
    }

    static func customServer(for network: BitcoinNetwork) -> String? {
        UserDefaults.standard.string(forKey: "wallet.server.\(network.rawValue)")
    }

    static func setServer(_ text: String?, for network: BitcoinNetwork) {
        let key = "wallet.server.\(network.rawValue)"
        if let text, let url = validServer(text) {
            UserDefaults.standard.set(url.absoluteString, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Nur HTTPS mit Host; ergänzt den Schrägstrich am Ende.
    static func validServer(_ text: String) -> URL? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if !t.hasSuffix("/") { t += "/" }
        guard let url = URL(string: t), url.scheme == "https", let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// Währung für die ungefähre Anzeige (nur, was mempool.space kennt).
    static var currency: String {
        let code = Locale.current.currency?.identifier ?? "USD"
        return ["USD", "EUR", "GBP", "CAD", "CHF", "AUD", "JPY"].contains(code) ? code : "USD"
    }

    /// Der Schlüssel der Wallet: im Schlüsselbund, im Demo im Speicher.
    static var secrets: WalletSecrets {
        #if DEBUG
        if DemoMode.isOffline { return DemoMode.offlineWalletSecrets }
        #endif
        return WalletKeychain.shared
    }

    static func chain(for network: BitcoinNetwork) -> ChainSource {
        #if DEBUG
        if DemoMode.isOffline { return DemoMode.offlineChain }
        #endif
        let url = server(for: network)
        // mempool.space sperrt nach gut zwanzig schnellen Anfragen; der eigene
        // Knoten nicht.
        return EsploraClient(baseURL: url, pacer: url == network.defaultEsplora ? .publicServer : nil)
    }
}
