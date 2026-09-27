import Foundation
import KryptaCore

/// Ordnung in der Chatliste: stumm, angepinnt, archiviert, Suche, und die
/// Löschfrist, mit der neue Chats beginnen. Alles nur auf diesem Gerät; die
/// Gegenseite erfährt davon nichts (außer von der Löschfrist, die für beide gilt).
extension MessengerEngine {
    /// Höchstens so viele Chats oben angepinnt.
    public static let maxPinned = 5

    // MARK: - Stumm

    /// `until == nil`: wieder mit Ton. `.distantFuture`: bis zum Einschalten.
    public func setMuted(_ chatId: String, until: Date?) {
        updateChat(chatId) { $0.mutedUntil = until }
    }

    // MARK: - Anpinnen

    /// `false`: schon so viele angepinnt, wie es geht.
    @discardableResult
    public func setPinned(_ chatId: String, _ pinned: Bool) -> Bool {
        guard let chat = chat(chatId), chat.isPinned != pinned else { return true }
        if pinned, chats.filter(\.isPinned).count >= Self.maxPinned { return false }
        updateChat(chatId) {
            $0.pinnedAt = pinned ? Date() : nil
            // Angepinnt gehört in die Liste, nicht ins Archiv.
            if pinned { $0.archived = nil }
        }
        return true
    }

    // MARK: - Archiv

    public func setArchived(_ chatId: String, _ archived: Bool) {
        updateChat(chatId) {
            $0.archived = archived ? true : nil
            if archived { $0.pinnedAt = nil }
        }
    }

    /// Neue Nachricht in einem archivierten Chat: zurück in die Liste, außer
    /// er ist stumm — wie in Signal.
    func surfaceIfArchived(_ chatId: String) {
        guard let chat = chat(chatId), chat.isArchived, !chat.isMuted() else { return }
        updateChat(chatId) { $0.archived = nil }
    }

    // MARK: - Suche

    /// Nachrichten, die den Suchtext enthalten, neueste zuerst. Einmalige
    /// und gesperrte Nachrichten bleiben außen vor.
    public func searchMessages(_ query: String, limit: Int = 50) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        var hits: [SearchHit] = []
        for chat in listedChats {
            for m in messages(in: chat.id) where Self.searchable(m) {
                guard let text = m.text, text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { continue }
                hits.append(SearchHit(chatId: chat.id, messageId: m.id, text: text, timestamp: m.timestamp, mine: m.senderId == userId))
            }
        }
        return Array(hits.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    static func searchable(_ m: Message) -> Bool {
        !m.isSystemEvent && !m.oneTime && !(m.isPasswordProtected && !m.passwordUnlocked)
    }

    // MARK: - Löschfrist für neue Chats

    public var defaultChatRule: ChatRuleChoice {
        get {
            if meta.defaultAfterRead == true { return .afterRead }
            if let t = meta.defaultTimer, t > 0 { return .timer(t) }
            return .off
        }
        set {
            switch newValue {
            case .off: meta.defaultTimer = nil; meta.defaultAfterRead = nil
            case .timer(let t): meta.defaultTimer = t; meta.defaultAfterRead = nil
            case .afterRead: meta.defaultTimer = nil; meta.defaultAfterRead = true
            }
            saveMeta()
        }
    }

    /// Ein Chat ist gerade zustande gekommen: die eingestellte Löschfrist
    /// setzen, wenn für ihn noch nie eine galt. Setzen beide Seiten eine,
    /// einigen sie sich wie bei jeder Regel (adoptForeignRule).
    func applyDefaultRule(_ chatId: String) async {
        guard let chat = chat(chatId), chat.ruleVersion == 0, !chat.ruleIsEphemeral else { return }
        switch defaultChatRule {
        case .off: return
        case .timer(let t): await setChatRule(chatId, timer: t, afterRead: false)
        case .afterRead: await setChatRule(chatId, timer: nil, afterRead: true)
        }
    }
}
