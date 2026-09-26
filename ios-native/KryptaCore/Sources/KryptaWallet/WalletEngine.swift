import Foundation
import KryptaBitcoin
import Observation

/// Verschlüsselter Speicher für den Stand der Wallet (in der App der
/// Tresor von Krypta, dieselben Methoden wie `Vault`).
public protocol WalletStore: AnyObject, Sendable {
    func load(_ slot: String) throws -> Data?
    func save(_ data: Data, slot: String) throws
    func delete(_ slot: String) throws
}

public final class MemoryWalletStore: WalletStore, @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [String: Data] = [:]
    public init() {}
    public func load(_ slot: String) throws -> Data? { lock.withLock { slots[slot] } }
    public func save(_ data: Data, slot: String) throws { lock.withLock { slots[slot] = data } }
    public func delete(_ slot: String) throws { _ = lock.withLock { slots.removeValue(forKey: slot) } }
}

/// Was die Wallet über Neustarts hinweg weiß. Nichts davon ist geheim im
/// Sinne von „damit lässt sich Geld ausgeben", aber alles ist privat: es
/// liegt verschlüsselt im Tresor.
struct WalletState: Codable {
    struct AddressRecord: Codable, Equatable {
        let path: AddressPath
        var stats: AddressStats
    }

    struct Outgoing: Codable {
        let txid: String
        let raw: String
        var state: OutgoingState
        let created: Date
        let inputs: [OutPoint]
        let amount: Int64
        let fee: Int64
        let recipient: String
        let contactId: String?
        let note: String?
        /// Das eigene Wechselgeld, sofort wieder ausgebbar.
        let change: Coin?
    }

    struct Claim: Codable {
        let payment: ChatPayment
        let contactId: String
        let received: Date
        var attempts: Int
        var check: PaymentCheck
    }

    struct Label: Codable {
        var contactId: String?
        var note: String?
    }

    var nextReceive: UInt32 = 0
    var nextChange: UInt32 = 0
    /// Die Adresse für den QR-Code in der Wallet.
    var qrIndex: UInt32?
    /// Jeder Kontakt bekommt seine eigene Empfangsadresse.
    var contactIndex: [String: UInt32] = [:]
    var addresses: [String: AddressRecord] = [:]
    var coins: [Coin] = []
    var history: [String: WalletTransaction] = [:]
    var outgoing: [String: Outgoing] = [:]
    /// Zahlungen im Chat, nach Nachrichtenkennung.
    var claims: [String: Claim] = [:]
    var labels: [String: Label] = [:]
    var backedUp = false
    var chatPayments = true
    var tip: Int?
    var lastSync: Date?
    /// Nach dem Wiederherstellen einmal tiefer suchen.
    var deepScan = false
}

/// Die Bitcoin-Wallet eines Kontos.
///
/// Selbstverwahrt: der Schlüssel entsteht auf dem Gerät und verlässt es nie
/// (außer als zwölf Wörter, die man sich aufschreibt). Die Blockchain liefert
/// ein Esplora-Server; er erfährt die Adressen, aber nichts, womit er Geld
/// bewegen oder eine Zahlung vortäuschen könnte.
@MainActor
@Observable
public final class WalletEngine {
    public let network: BitcoinNetwork
    public internal(set) var balance = Balance()
    public internal(set) var transactions: [WalletTransaction] = []
    public internal(set) var isSyncing = false
    public internal(set) var lastError: WalletFailure?
    public internal(set) var feeEstimates: FeeEstimates?
    /// Kurs je BTC in der gewählten Währung — nur zur Anzeige.
    public internal(set) var fiatRate: (currency: String, price: Double)?
    /// Ändert sich bei jedem neuen Stand, damit die Oberfläche nachzieht.
    public internal(set) var revision = 0

    @ObservationIgnored let account: ExtendedPublicKey
    @ObservationIgnored let secrets: WalletSecrets
    @ObservationIgnored let store: WalletStore
    @ObservationIgnored public let chain: ChainSource
    @ObservationIgnored var state = WalletState()
    @ObservationIgnored var addressCache: [AddressPath: BitcoinAddress] = [:]
    @ObservationIgnored var scriptPaths: [[UInt8]: AddressPath] = [:]
    @ObservationIgnored var loopTask: Task<Void, Never>?
    @ObservationIgnored var claimTasks: Set<String> = []
    @ObservationIgnored public var preferredCurrency = "USD"
    /// Meldet eine geprüfte Zahlung im Chat (Adresse ist jetzt benutzt).
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?

    public static let receiveGap: UInt32 = 20
    public static let changeGap: UInt32 = 10
    /// Nach dem Wiederherstellen: so weit suchen, wie Krypta höchstens
    /// unbenutzte Adressen an Kontakte vergibt.
    public static let deepGap: UInt32 = 200
    /// Mehr unbenutzte Adressen als das vergibt Krypta nicht.
    public static let maxOutstanding: UInt32 = 150

    var slot: String { Self.stateSlot(for: network) }

    /// Wo der Stand einer Wallet im Tresor liegt (je Netz einer).
    public static func stateSlot(for network: BitcoinNetwork) -> String { "wallet.\(network.rawValue)" }

    public init(network: BitcoinNetwork, secrets: WalletSecrets, store: WalletStore, chain: ChainSource) throws {
        guard let account = secrets.accountKey(for: network) else { throw WalletFailure.noWallet }
        self.network = network
        self.account = account
        self.secrets = secrets
        self.store = store
        self.chain = chain
        if let data = try? store.load(slot), let saved = try? JSONDecoder.wallet.decode(WalletState.self, from: data) {
            state = saved
        }
        rebuild()
    }

    func save() {
        guard let data = try? JSONEncoder.wallet.encode(state) else { return }
        try? store.save(data, slot: slot)
    }

    // MARK: - Öffentlicher Zustand

    public var backedUp: Bool { state.backedUp }
    public var tipHeight: Int? { state.tip }
    public var lastSync: Date? { state.lastSync }

    public var chatPaymentsEnabled: Bool {
        get { _ = revision; return state.chatPayments }
        set {
            state.chatPayments = newValue
            save()
            touch()
        }
    }

    /// Die zwölf Wörter sind gesichert (vom Nutzer bestätigt).
    public func confirmBackup() {
        state.backedUp = true
        save()
        touch()
    }

    public func transaction(_ txid: String) -> WalletTransaction? { state.history[txid] }

    func touch() {
        revision &+= 1
    }

    // MARK: - Adressen

    func address(_ chain: WalletKeys.Chain, _ index: UInt32) -> BitcoinAddress {
        let path = AddressPath(chain: chain, index: index)
        if let cached = addressCache[path] { return cached }
        // Ableiten scheitert nur mit Wahrscheinlichkeit 2^-127 (BIP32); dann
        // ist das auch für jede andere Wallet dieser Index nicht nutzbar.
        let address = (try? WalletKeys.address(account: account, chain: chain, index: index, network: network))
            ?? BitcoinAddress.p2wpkh(publicKey: account.publicKey, network: network)
        addressCache[path] = address
        scriptPaths[address.scriptPubKey] = path
        return address
    }

    func isUsed(_ chain: WalletKeys.Chain, _ index: UInt32) -> Bool {
        (state.addresses[address(chain, index).string]?.stats.txCount ?? 0) > 0
    }

    func lastUsed(_ chain: WalletKeys.Chain) -> UInt32? {
        state.addresses.values.filter { $0.path.chain == chain && $0.stats.txCount > 0 }.map(\.path.index).max()
    }

    /// Bis wohin gesucht wird: alles Vergebene plus Lücke.
    func frontier(_ chain: WalletKeys.Chain) -> UInt32 {
        let next = chain == .receive ? state.nextReceive : state.nextChange
        let used = lastUsed(chain).map { $0 + 1 } ?? 0
        let gap = state.deepScan ? Self.deepGap : (chain == .receive ? Self.receiveGap : Self.changeGap)
        return max(next, used) + gap
    }

    /// Gehört dieses Skript zur Wallet (im durchsuchten Bereich)?
    func path(of script: [UInt8]) -> AddressPath? {
        if let known = scriptPaths[script] { return known }
        for chain in [WalletKeys.Chain.receive, .change] {
            for i in 0..<frontier(chain) where address(chain, i).scriptPubKey == script {
                return AddressPath(chain: chain, index: i)
            }
        }
        return nil
    }

    func allocateReceive() -> UInt32 {
        var index = state.nextReceive
        while isUsed(.receive, index) { index += 1 }
        state.nextReceive = index + 1
        return index
    }

    var outstanding: UInt32 {
        let used = lastUsed(.receive).map { $0 + 1 } ?? 0
        return state.nextReceive > used ? state.nextReceive - used : 0
    }

    /// Die Adresse für den QR-Code: bleibt, bis etwas darauf eingeht.
    public func receiveAddress() -> BitcoinAddress {
        if let i = state.qrIndex, !isUsed(.receive, i) { return address(.receive, i) }
        let i = allocateReceive()
        state.qrIndex = i
        save()
        return address(.receive, i)
    }

    /// Eine neue Adresse für den QR-Code (die alte bleibt gültig).
    public func newReceiveAddress() -> BitcoinAddress {
        guard outstanding < Self.maxOutstanding else { return receiveAddress() }
        let i = allocateReceive()
        state.qrIndex = i
        save()
        touch()
        return address(.receive, i)
    }

    /// Die Adresse, die dieser Kontakt verschlüsselt im Chat bekommt. Jeder
    /// Kontakt hat seine eigene; ist sie benutzt, kommt die nächste. `nil`,
    /// wenn Zahlungen im Chat ausgeschaltet sind.
    public func chatAddress(for contactId: String) -> String? {
        guard state.chatPayments else { return nil }
        if let i = state.contactIndex[contactId], !isUsed(.receive, i) || outstanding >= Self.maxOutstanding {
            return address(.receive, i).string
        }
        guard outstanding < Self.maxOutstanding else { return receiveAddress().string }
        let i = allocateReceive()
        state.contactIndex[contactId] = i
        save()
        return address(.receive, i).string
    }

    /// Prüft eine Adresse, die ein Kontakt geschickt hat, für dieses Netz.
    public func parseAddress(_ text: String) -> BitcoinAddress? {
        try? BitcoinAddress(text, network: network)
    }

    // MARK: - Stand ableiten

    /// Guthaben und Verlauf aus Münzen, Verlauf und offenen Sendungen.
    func rebuild() {
        let locked = lockedOutPoints
        var b = Balance()
        for coin in state.coins where !locked.contains(coin.outPoint) {
            if coin.confirmed {
                b.confirmed += coin.value
            } else if isOwn(coin.outPoint.txid) {
                b.ownPending += coin.value
            } else {
                b.incoming += coin.value
            }
        }
        balance = b
        var list = Array(state.history.values)
        for out in state.outgoing.values where state.history[out.txid] == nil && out.state != .failed {
            list.append(WalletTransaction(txid: out.txid, net: -(out.amount + out.fee), fee: out.fee, height: nil, time: out.created,
                                          contactId: out.contactId, note: out.note, outgoing: out.state))
        }
        for i in list.indices {
            if let label = state.labels[list[i].txid] {
                list[i].contactId = list[i].contactId ?? label.contactId
                list[i].note = list[i].note ?? label.note
            }
            if let out = state.outgoing[list[i].txid] { list[i].outgoing = out.state }
        }
        transactions = list.sorted {
            switch ($0.height, $1.height) {
            case (nil, nil): return $0.time > $1.time
            case (nil, _): return true
            case (_, nil): return false
            case let (a?, b?): return a != b ? a > b : $0.time > $1.time
            }
        }
        touch()
    }

    func isOwn(_ txid: String) -> Bool {
        state.outgoing[txid] != nil || (state.history[txid]?.net ?? 0) < 0
    }

    /// Eingänge eigener Sendungen, die noch nicht sicher verbucht sind.
    var lockedOutPoints: Set<OutPoint> {
        Set(state.outgoing.values.filter { $0.state != .failed }.flatMap(\.inputs))
    }

    /// Was jetzt ausgegeben werden darf: bestätigt oder eigenes Wechselgeld.
    var spendableCoins: [Coin] {
        let locked = lockedOutPoints
        return state.coins.filter { !locked.contains($0.outPoint) && ($0.confirmed || isOwn($0.outPoint.txid)) }
    }

    // MARK: - Laufen lassen

    /// Abgleich jetzt und danach in Abständen, solange die App offen ist.
    public func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.sync()
                let busy = self.state.outgoing.values.contains { $0.state != .failed && self.state.history[$0.txid]?.isConfirmed != true }
                    || self.state.claims.values.contains { if case .confirmed = $0.check { return false }; return true }
                    || self.balance.incoming > 0
                try? await Task.sleep(for: .seconds(busy ? 30 : 300))
            }
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    /// Den Stand dieser Wallet löschen (nicht den Schlüssel).
    public func forgetState() {
        stop()
        try? store.delete(slot)
        state = WalletState()
        rebuild()
    }
}

extension JSONEncoder {
    static let wallet: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }()
}

extension JSONDecoder {
    static let wallet: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()
}

extension ChainError {
    var walletFailure: WalletFailure {
        switch self {
        case .unreachable: .offline
        case .rateLimited: .server("rate-limited")
        case .notFound: .server("not-found")
        case .invalidResponse: .server("invalid-response")
        case .rejected(let reason): .rejected(reason)
        }
    }
}
