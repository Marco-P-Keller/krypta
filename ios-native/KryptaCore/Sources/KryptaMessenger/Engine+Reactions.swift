import Foundation
import KryptaCore

/// Antworten, Reaktionen und Bearbeiten.
///
/// Alles reist wie eine Nachricht durch die Ende-zu-Ende-Verschlüsselung,
/// mit Wiedereinspiel-Schutz (`_seq`), aber:
/// - `_re`: eine Antwort ist eine gewöhnliche Nachricht mit der Kennung der
///   zitierten. Der zitierte Text reist nicht mit; das Zitat kommt aus dem
///   eigenen Verlauf und verschwindet mit dem Original (Löschfristen gelten).
/// - `_rx`: `{"id": Kennung, "e": Emoji}`, leeres Emoji nimmt die Reaktion
///   zurück. Keine eigene Nachricht im Verlauf, keine Mitteilung.
/// - `_ed`: Kennung der eigenen Nachricht, `_t` der neue Text. Nur eigene,
///   gewöhnliche Textnachrichten, höchstens einen Tag lang. Keine Mitteilung.
///
/// Die Flutter-Fassung kennt die Felder nicht: Reaktionen und Bearbeitungen
/// gehen nur an Kontakte, die selbst schon versiegelt schreiben (`_dk`),
/// also die native App haben.
public enum ReplyPolicy {
    /// Zitieren geht nur, was man lesen kann und was bleibt.
    public static func canQuote(_ m: Message) -> Bool {
        !m.isSystemEvent && !m.oneTime && !(m.isPasswordProtected && !m.passwordUnlocked)
    }
}

public enum ReactionPolicy {
    /// Die Auswahl im Menü; empfangen wird jedes einzelne Emoji.
    public static let quick = ["❤️", "👍", "👎", "😂", "😮", "😢"]

    /// Genau ein Emoji, und nicht zu lang (Familien-Emoji haben viele Teile).
    public static func isValid(_ emoji: String) -> Bool {
        guard emoji.count == 1, emoji.utf8.count <= 32, let first = emoji.unicodeScalars.first else { return false }
        // Ziffern und # sind Emoji-fähig, aber allein keine Reaktion.
        return emoji.unicodeScalars.contains { $0.properties.isEmojiPresentation }
            || (first.properties.isEmoji && emoji.unicodeScalars.count > 1)
    }

    public static func canReact(to m: Message) -> Bool {
        !m.isSystemEvent && !(m.oneTime && m.text != nil)
    }
}

public enum EditPolicy {
    /// So lange lässt sich eine Nachricht bearbeiten.
    public static let window: TimeInterval = 24 * 3600
    /// Beim Empfang etwas großzügiger: die Uhren gehen nicht gleich, und
    /// die Nachricht kann eine Weile auf dem Server gelegen haben.
    static let receiveWindow: TimeInterval = 48 * 3600
    public static let maxLength = 20_000

    public static func canEdit(_ m: Message, me: String, now: Date = Date()) -> Bool {
        m.senderId == me && isEditable(m) && (m.status == .sent || m.status == .delivered || m.status == .read)
            && now.timeIntervalSince(m.timestamp) < window
    }

    static func isEditable(_ m: Message) -> Bool {
        !m.isSystemEvent && !m.oneTime && !m.isPasswordProtected && m.payment == nil && m.text != nil
    }
}

extension MessengerEngine {
    // MARK: - Reagieren

    /// Eigene Reaktion setzen (`nil` oder leer: zurücknehmen).
    public func react(chatId: String, messageId: String, emoji: String?) async {
        let value = emoji ?? ""
        guard value.isEmpty || ReactionPolicy.isValid(value),
              let m = messages(in: chatId).first(where: { $0.id == messageId }), ReactionPolicy.canReact(to: m) else { return }
        let current = m.reactions?[userId]
        guard current != (value.isEmpty ? nil : value) else { return }
        updateMessage(chatId, messageId) { $0.setReaction(value.isEmpty ? nil : value, from: self.userId) }
        let fields: JSONObject = ["_rx": .object(["id": .string(messageId), "e": .string(value)])]
        await sendSide(chatId: chatId, fields: fields)
    }

    // MARK: - Bearbeiten

    /// Eigene Nachricht bearbeiten. `false`: geht (nicht mehr).
    @discardableResult
    public func edit(chatId: String, messageId: String, text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= EditPolicy.maxLength,
              let m = messages(in: chatId).first(where: { $0.id == messageId }),
              EditPolicy.canEdit(m, me: userId), m.text != trimmed else { return false }
        updateMessage(chatId, messageId) {
            $0.text = trimmed
            $0.editedAt = Date()
        }
        await sendSide(chatId: chatId, fields: ["_ed": .string(messageId)], content: trimmed)
        return true
    }

    /// Eine Nachricht ohne eigenen Eintrag im Verlauf: Reaktion, Bearbeitung.
    /// Scheitert sie, bleibt es still bei der lokalen Änderung.
    func sendSide(chatId: String, fields: JSONObject, content: String = "") async {
        if chat(chatId)?.isGroup == true {
            await sendGroupSide(chatId: chatId, fields: fields, content: content)
            return
        }
        guard let chat = chat(chatId), let contact = contact(chat.recipientId) else { return }
        await enqueue(chatId) { [self] in
            guard let current = self.contact(contact.id), sendBlockReason(current) == nil, Self.understandsExtras(current) else { return }
            _ = try? await transmit(chatId: chatId, contact: current, messageId: UUID().uuidString.lowercased(),
                                    content: content, extra: fields, quiet: true)
        }
    }

    /// Die Flutter-Fassung zeigte eine Reaktion als leere Nachricht und eine
    /// Bearbeitung als neue. Wer `_dk` schickt, hat die native App.
    static func understandsExtras(_ c: Contact) -> Bool { c.sealedKey != nil }

    /// Reagieren und Bearbeiten gehen in diesem Chat.
    public func supportsExtras(chatId: String) -> Bool {
        if let g = group(chatId) { return !g.hasLeft }
        guard let chat = chat(chatId), let c = contact(chat.recipientId) else { return false }
        return sendBlockReason(c) == nil && Self.understandsExtras(c)
    }

    // MARK: - Empfangen

    /// Reaktion oder Bearbeitung aus einer angenommenen Nachricht anwenden.
    /// `true`: es war eine, und der Verlauf bekommt keinen Eintrag.
    func applySide(chatId: String, senderId: String, inner: JSONObject) -> Bool {
        if let rx = inner["_rx"]?.objectValue {
            applyReaction(chatId: chatId, senderId: senderId, target: rx["id"]?.stringValue, emoji: rx["e"]?.stringValue)
            return true
        }
        if let target = inner["_ed"]?.stringValue {
            applyEdit(chatId: chatId, senderId: senderId, target: target, text: inner["_t"]?.stringValue)
            return true
        }
        return false
    }

    func applyReaction(chatId: String, senderId: String, target: String?, emoji: String?) {
        guard let target, let emoji, emoji.isEmpty || ReactionPolicy.isValid(emoji),
              let m = messages(in: chatId).first(where: { $0.id == target }), ReactionPolicy.canReact(to: m),
              m.reactions?[senderId] != (emoji.isEmpty ? nil : emoji) else { return }
        updateMessage(chatId, target) { $0.setReaction(emoji.isEmpty ? nil : emoji, from: senderId) }
    }

    func applyEdit(chatId: String, senderId: String, target: String, text: String?) {
        guard let text, !text.isEmpty, text.count <= EditPolicy.maxLength,
              let m = messages(in: chatId).first(where: { $0.id == target }),
              m.senderId == senderId, senderId != userId, EditPolicy.isEditable(m),
              Date().timeIntervalSince(m.timestamp) < EditPolicy.receiveWindow, m.text != text else { return }
        updateMessage(chatId, target) {
            $0.text = text
            $0.editedAt = Date()
        }
    }
}

extension Message {
    mutating func setReaction(_ emoji: String?, from sender: String) {
        var map = reactions ?? [:]
        map[sender] = emoji
        reactions = map.isEmpty ? nil : map
    }
}
