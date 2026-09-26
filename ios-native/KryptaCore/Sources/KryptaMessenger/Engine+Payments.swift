import Foundation
import KryptaBitcoin
import KryptaCore
import KryptaWallet

/// Bitcoin im Chat.
///
/// Alles reist *innerhalb* der Ende-zu-Ende-Verschlüsselung, der Server sieht
/// davon nichts:
/// - `_btc` in jeder Nachricht und jeder Steuernachricht an einen Kontakt:
///   `{"n": Netz}`, und sobald bekannt ist, dass der Kontakt selbst eine
///   Wallet hat, auch `"a"`: meine Empfangsadresse nur für ihn. Eine
///   Flutter-App schickt kein `_btc` und bekommt so nie eine Adresse.
/// - `_pay` in der Nachricht, die eine Zahlung ankündigt:
///   `{"txid", "vout", "sat", "a", "n"}`; `_t` ist die Notiz dazu.
///
/// Gezahlt wird wirklich über die Blockchain. Die Nachricht sagt nur, dass
/// und wohin; die Wallet des Empfängers glaubt ihr nichts, sondern prüft
/// (WalletEngine+Claims).
extension MessengerEngine {
    /// Die Wallet hängt die App an; ohne sie gibt es kein `_btc`.
    public func attach(wallet: WalletEngine?) {
        self.wallet = wallet
        guard let wallet else { return }
        // Zahlungen, die ankamen, bevor die Wallet da war, nachträglich prüfen.
        for (_, list) in messages {
            for m in list where m.senderId != userId {
                if let payment = m.payment { wallet.registerClaim(payment, from: m.senderId, messageId: m.id, note: m.text) }
            }
        }
    }

    func bitcoinField(for contact: Contact) -> JSONValue? {
        guard let wallet, wallet.chatPaymentsEnabled else { return nil }
        var map: JSONObject = ["n": .string(wallet.network.rawValue)]
        if contact.acceptsBitcoin == true, let address = wallet.chatAddress(for: contact.id) {
            map["a"] = .string(address)
        }
        return .object(map)
    }

    /// `_btc` aus einer angenommenen Nachricht übernehmen. Fehlt es, hat der
    /// Kontakt (jetzt) keine Zahlungen im Chat: dann auch keine Adresse mehr.
    func learnBitcoin(from contactId: String, inner: JSONObject) {
        guard let current = contact(contactId) else { return }
        guard let map = inner["_btc"]?.objectValue, let raw = map["n"]?.stringValue, let network = BitcoinNetwork(rawValue: raw) else {
            if current.acceptsBitcoin != false || current.bitcoinAddress != nil {
                updateContact(contactId) {
                    $0.acceptsBitcoin = false
                    $0.bitcoinAddress = nil
                    $0.bitcoinNetwork = nil
                }
            }
            return
        }
        var address = current.bitcoinNetwork == network.rawValue ? current.bitcoinAddress : nil
        if let text = map["a"]?.stringValue, text.count <= 90, let parsed = try? BitcoinAddress(text, network: network) {
            address = parsed.string
        }
        guard current.acceptsBitcoin != true || current.bitcoinAddress != address || current.bitcoinNetwork != network.rawValue else { return }
        updateContact(contactId) {
            $0.acceptsBitcoin = true
            $0.bitcoinAddress = address
            $0.bitcoinNetwork = network.rawValue
        }
    }

    static func payment(in inner: JSONObject) -> ChatPayment? {
        guard let p = inner["_pay"]?.objectValue else { return nil }
        return ChatPayment.parse(txid: p["txid"]?.stringValue, vout: p["vout"]?.intValue, sats: p["sat"]?.intValue,
                                 address: p["a"]?.stringValue, network: p["n"]?.stringValue)
    }

    /// Warum an diesen Kontakt gerade nicht gezahlt werden kann. `nil`: es geht.
    public enum PaymentBlock: Equatable, Sendable {
        case noWallet
        case cannotMessage
        /// Der Kontakt hat keine Wallet (oder Zahlungen im Chat aus).
        case noWalletThere
        /// Noch keine Adresse bekommen; sie kommt mit seiner nächsten Nachricht.
        case waitingForAddress
        case otherNetwork
    }

    public func paymentBlock(for contactId: String) -> PaymentBlock? {
        guard let wallet else { return .noWallet }
        guard let c = contact(contactId), sendBlockReason(c) == nil else { return .cannotMessage }
        guard c.acceptsBitcoin == true else { return c.acceptsBitcoin == false ? .noWalletThere : .waitingForAddress }
        guard let n = c.bitcoinNetwork, n == wallet.network.rawValue else { return c.bitcoinNetwork == nil ? .waitingForAddress : .otherNetwork }
        guard c.bitcoinAddress != nil else { return .waitingForAddress }
        return nil
    }

    /// Die Adresse, an die dieser Kontakt bezahlt werden will — geprüft.
    public func paymentAddress(for contactId: String) -> BitcoinAddress? {
        guard paymentBlock(for: contactId) == nil, let wallet, let text = contact(contactId)?.bitcoinAddress else { return nil }
        return wallet.parseAddress(text)
    }

    /// Einen Kontakt im Chat bezahlen: signieren, senden, dann die Nachricht.
    ///
    /// Die Nachricht geht erst raus, wenn der Server die Transaktion
    /// angenommen hat. Scheitert danach nur die Nachricht, bleibt sie mit
    /// „nicht zugestellt" stehen, und „erneut senden" schickt nur sie.
    public func pay(chatId: String, draft: PaymentDraft, reason: String) async throws -> SentPayment {
        guard let wallet else { throw WalletFailure.noWallet }
        guard let chat = chat(chatId), let c = contact(chat.recipientId), sendBlockReason(c) == nil,
              draft.contactId == c.id, let expected = paymentAddress(for: c.id), expected == draft.recipient else {
            throw WalletFailure.stale
        }
        let sent = try await wallet.send(draft, reason: reason)
        await sendPaymentMessage(chatId: chatId, payment: sent.payment, note: draft.note ?? "")
        return sent
    }

    func sendPaymentMessage(chatId: String, payment: ChatPayment, note: String) async {
        let rule = chat(chatId)?.timer
        await enqueue(chatId) { [self] in
            await sendLocked(chatId: chatId, text: note, options: SendOptions(selfDestruct: rule, fromChatRule: true),
                             asRequest: false, qrToken: nil, preverifiedKey: nil, payment: payment)
        }
    }
}

extension ChatPayment {
    var json: JSONValue {
        .object([
            "txid": .string(txid), "vout": .int(Int(vout)), "sat": .int(Int(sats)),
            "a": .string(address), "n": .string(network.rawValue),
        ])
    }
}
