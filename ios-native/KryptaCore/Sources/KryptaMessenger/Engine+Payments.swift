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
///   `{"txid", "vout", "sat", "a", "n"}`, auf eine Bitte hin auch `"rq"`
///   (ihre Kennung); `_t` ist die Notiz dazu.
/// - `_req` in einer Bitte um Bitcoin: `{"sat", "n"}`; `_t` ist die Notiz.
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
    ///
    /// `requestId`: die Bitte, die damit bezahlt wird. Dann muss der Betrag
    /// genau der erbetene sein, und die Bitte darf noch nicht bezahlt sein.
    public func pay(chatId: String, draft: PaymentDraft, reason: String, answering requestId: String? = nil) async throws -> SentPayment {
        guard let wallet else { throw WalletFailure.noWallet }
        guard let chat = chat(chatId), let c = contact(chat.recipientId), sendBlockReason(c) == nil,
              draft.contactId == c.id, let expected = paymentAddress(for: c.id), expected == draft.recipient else {
            throw WalletFailure.stale
        }
        if let requestId {
            guard let r = openRequest(chatId: chatId, messageId: requestId), r.network == wallet.network, r.sats == draft.amount else {
                throw WalletFailure.stale
            }
        }
        let sent = try await wallet.send(draft, reason: reason)
        await sendPaymentMessage(chatId: chatId, payment: sent.payment, note: draft.note ?? "", answering: requestId)
        return sent
    }

    // MARK: - Um Bitcoin bitten

    /// Warum ich diesen Kontakt gerade nicht um Bitcoin bitten kann. `nil`:
    /// es geht. Er braucht eine Wallet im selben Netz, ich Zahlungen im Chat
    /// (sonst reist meine Adresse nicht mit).
    public func requestBlock(for contactId: String) -> PaymentBlock? {
        guard let wallet, wallet.chatPaymentsEnabled else { return .noWallet }
        guard let c = contact(contactId), sendBlockReason(c) == nil else { return .cannotMessage }
        guard c.acceptsBitcoin == true else { return c.acceptsBitcoin == false ? .noWalletThere : .waitingForAddress }
        guard c.bitcoinNetwork == wallet.network.rawValue else { return .otherNetwork }
        return nil
    }

    /// Einen Kontakt um Bitcoin bitten. Die Blase zeigt Betrag und Notiz,
    /// mit derselben Nachricht reist meine Adresse nur für ihn. `false`:
    /// geht gerade nicht (siehe `requestBlock`).
    @discardableResult
    public func requestPayment(chatId: String, sats: Int64, note: String) async -> Bool {
        guard let wallet, let chat = chat(chatId), !chat.isGroup, requestBlock(for: chat.recipientId) == nil,
              sats > 0, sats <= BitcoinAmount.maxSats else { return false }
        let request = ChatPaymentRequest(sats: sats, network: wallet.network)
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = chat.timer
        await enqueue(chatId) { [self] in
            await sendLocked(chatId: chatId, text: text, options: SendOptions(selfDestruct: rule, fromChatRule: true),
                             asRequest: false, qrToken: nil, preverifiedKey: nil, paymentRequest: request)
        }
        return true
    }

    /// Eine offene Bitte des Kontakts in diesem Chat.
    public func openRequest(chatId: String, messageId: String) -> ChatPaymentRequest? {
        guard let chat = chat(chatId), !chat.isGroup,
              let m = messages(in: chatId).first(where: { $0.id == messageId }), m.senderId == chat.recipientId,
              let r = m.paymentRequest, !r.isPaid else { return nil }
        return r
    }

    /// Die Nachricht mit der Zahlung auf eine Bitte.
    public func payment(for request: Message) -> Message? {
        guard let id = request.paymentRequest?.paidBy else { return nil }
        return messages(in: request.chatId).first { $0.id == id && $0.payment != nil }
    }

    static func paymentRequest(in inner: JSONObject) -> ChatPaymentRequest? {
        guard let r = inner["_req"]?.objectValue, let sats = r["sat"]?.intValue, sats > 0, Int64(sats) <= BitcoinAmount.maxSats,
              let raw = r["n"]?.stringValue, let network = BitcoinNetwork(rawValue: raw) else { return nil }
        return ChatPaymentRequest(sats: Int64(sats), network: network)
    }

    /// Eine Bitte als bezahlt vermerken: nur eine offene von `requester`,
    /// im selben Netz, und nur mit mindestens dem erbetenen Betrag. Ob die
    /// Zahlung stimmt, zeigt ihre eigene Blase (die Wallet prüft sie).
    func markRequestPaid(chatId: String, requestId: String, requester: String, payment: ChatPayment, by paymentMessageId: String) {
        guard let m = messages(in: chatId).first(where: { $0.id == requestId }), m.senderId == requester,
              let r = m.paymentRequest, !r.isPaid, r.network == payment.network, payment.sats >= r.sats else { return }
        updateMessage(chatId, requestId) { $0.paymentRequest?.paidBy = paymentMessageId }
    }

    /// Gebühr einer eigenen Zahlung erhöhen. Stand die Zahlung im Chat,
    /// bekommt der Empfänger die neue Transaktion verschlüsselt nachgereicht
    /// (`_payu`), und die Blase zeigt sie.
    public func bumpFee(_ draft: BumpDraft, reason: String) async throws -> SentPayment {
        guard let wallet else { throw WalletFailure.noWallet }
        let sent = try await wallet.bump(draft, reason: reason)
        for (chatId, list) in messages {
            guard let m = list.first(where: { $0.senderId == userId && $0.payment?.txid == draft.originalTxid }) else { continue }
            updateMessage(chatId, m.id) { $0.payment = sent.payment }
            await sendSide(chatId: chatId, fields: ["_payu": .object(["m": .string(m.id), "p": sent.payment.json])])
        }
        return sent
    }

    /// `_payu` vom Absender einer Zahlung: dieselbe Zahlung, neue Transaktion.
    func applyPaymentUpdate(chatId: String, senderId: String, map: JSONObject) {
        guard let messageId = map["m"]?.stringValue, let p = map["p"]?.objectValue,
              let payment = ChatPayment.parse(txid: p["txid"]?.stringValue, vout: p["vout"]?.intValue, sats: p["sat"]?.intValue,
                                              address: p["a"]?.stringValue, network: p["n"]?.stringValue),
              let m = messages(in: chatId).first(where: { $0.id == messageId }), m.senderId == senderId,
              let old = m.payment, old.address == payment.address, old.sats == payment.sats, old.network == payment.network else { return }
        guard wallet?.replaceClaim(messageId: messageId, with: payment) != false else { return }
        updateMessage(chatId, messageId) { $0.payment = payment }
    }

    func sendPaymentMessage(chatId: String, payment: ChatPayment, note: String, answering requestId: String? = nil) async {
        let rule = chat(chatId)?.timer
        await enqueue(chatId) { [self] in
            await sendLocked(chatId: chatId, text: note, options: SendOptions(selfDestruct: rule, fromChatRule: true),
                             asRequest: false, qrToken: nil, preverifiedKey: nil, payment: payment, answering: requestId)
        }
    }
}

extension ChatPayment {
    var fields: JSONObject {
        [
            "txid": .string(txid), "vout": .int(Int(vout)), "sat": .int(Int(sats)),
            "a": .string(address), "n": .string(network.rawValue),
        ]
    }

    var json: JSONValue { .object(fields) }
}

extension ChatPaymentRequest {
    var json: JSONValue { .object(["sat": .int(Int(sats)), "n": .string(network.rawValue)]) }
}
