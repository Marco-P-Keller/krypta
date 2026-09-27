import KryptaMessenger
import KryptaWallet
import SwiftUI

/// Die Chatliste — aufgebaut wie Nachrichten.
struct ChatsView: View {
    @Environment(MessengerEngine.self) private var engine
    @Environment(AppModel.self) private var app
    @Environment(WalletEngine.self) private var wallet: WalletEngine?

    @State private var path = NavigationPath()
    @State private var search = ""
    @State private var showNewChat = false
    @State private var showSettings = false
    @State private var showWallet = false
    @State private var chatToDelete: Chat?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !engine.incomingRequests.isEmpty && search.isEmpty {
                    Section {
                        NavigationLink(value: Route.requests) {
                            Label {
                                Text("Kontaktanfragen")
                            } icon: {
                                Image(systemName: "person.crop.circle.badge.plus")
                            }
                            .badge(engine.incomingRequests.count)
                        }
                    }
                }

                if !engine.archivedChats.isEmpty && search.isEmpty {
                    Section {
                        NavigationLink(value: Route.archive) {
                            Label {
                                Text("Archiviert")
                            } icon: {
                                Image(systemName: "archivebox")
                            }
                            .badge(engine.archivedChats.count)
                        }
                    }
                }

                Section {
                    ForEach(chats) { chat in
                        ChatListRow(chat: chat, path: $path, chatToDelete: $chatToDelete)
                    }
                } header: {
                    if !search.isEmpty && !chats.isEmpty { Text("Chats") }
                }

                if !hits.isEmpty {
                    Section {
                        ForEach(hits) { hit in
                            NavigationLink(value: Route.message(chatId: hit.chatId, messageId: hit.messageId)) {
                                SearchHitRow(hit: hit, query: search)
                            }
                        }
                    } header: {
                        Text("Nachrichten")
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if engine.chats.isEmpty && engine.incomingRequests.isEmpty {
                    ContentUnavailableView {
                        Label("Keine Chats", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Füge jemanden per QR-Code oder Kennung hinzu.")
                    } actions: {
                        Button("Neuer Chat") { showNewChat = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if !search.isEmpty && chats.isEmpty && hits.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Suchen")
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Einstellungen")
                }
                if let wallet {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showWallet = true } label: {
                            Image(systemName: "bitcoinsign.circle")
                                // Guthaben ohne gesicherte Wörter: ein Punkt, bis sie gesichert sind.
                                .overlay(alignment: .topTrailing) {
                                    if !wallet.backedUp && wallet.balance.total > 0 {
                                        Circle().fill(.orange).frame(width: 8, height: 8).offset(x: 2, y: -2)
                                    }
                                }
                        }
                        .accessibilityLabel("Bitcoin-Wallet")
                        .accessibilityIdentifier("chats.wallet")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewChat = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Neuer Chat")
                    .accessibilityIdentifier("chats.new")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if engine.keysPublished == false {
                    Banner(symbol: "icloud.slash", text: "Deine Schlüssel konnten nicht veröffentlicht werden. Andere können dich gerade nicht erreichen.", tint: .orange)
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .chat(let id): ConversationView(chatId: id)
                case .message(let chatId, let messageId): ConversationView(chatId: chatId, highlight: messageId)
                case .contact(let id): ContactDetailView(contactId: id)
                case .groupInfo(let id): GroupInfoView(chatId: id)
                case .requests: RequestsView()
                case .archive: ArchivedChatsView(path: $path, chatToDelete: $chatToDelete)
                }
            }
        }
        .sheet(isPresented: $showNewChat) {
            NewChatView { chatId in
                showNewChat = false
                path.append(Route.chat(chatId))
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showWallet) {
            ShieldedSheet { WalletView() }
        }
        .onAppear(perform: openFromNotification)
        .onChange(of: app.pendingOpen) { openFromNotification() }
        .confirmationDialog(
            "Chat löschen?", isPresented: Binding(get: { chatToDelete != nil }, set: { if !$0 { chatToDelete = nil } }),
            titleVisibility: .visible, presenting: chatToDelete
        ) { chat in
            Button("Chat löschen", role: .destructive) {
                Haptics.destructive()
                Task { await engine.deleteChat(chat.id) }
            }
        } message: { chat in
            Text("Der Chat verschwindet von diesem iPhone. Bei \(chat.name) werden deine Nachrichten entfernt.")
        }
    }

    /// Eine angetippte Mitteilung führt direkt in den Chat des Absenders.
    private func openFromNotification() {
        guard let target = app.pendingOpen else { return }
        app.pendingOpen = nil
        showNewChat = false
        showSettings = false
        showWallet = false
        switch target {
        case .chat(let contactId):
            guard let contact = engine.contact(contactId) else {
                // Gruppen: `group:<Kennung>` steht wie ein Kontakt in der Mitteilung.
                if let chat = engine.chat(forContact: contactId), chat.isGroup { path = NavigationPath([Route.chat(chat.id)]) }
                return
            }
            if contact.requestState == .incoming {
                path = NavigationPath([Route.requests])
            } else if let chat = engine.chat(forContact: contactId) {
                path = NavigationPath([Route.chat(chat.id)])
            }
        case .requests:
            path = NavigationPath([Route.requests])
        }
    }

    private var chats: [Chat] {
        guard !search.isEmpty else { return engine.sortedChats }
        return (engine.sortedChats + engine.archivedChats).filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var hits: [SearchHit] {
        search.isEmpty ? [] : engine.searchMessages(search)
    }
}

enum Route: Hashable {
    case chat(String)
    /// Ein Chat, zur Nachricht gescrollt (aus der Suche).
    case message(chatId: String, messageId: String)
    case contact(String)
    case groupInfo(String)
    case requests
    case archive
}

/// Ein Chat in der Liste mit allem, was man darauf tun kann.
private struct ChatListRow: View {
    @Environment(MessengerEngine.self) private var engine
    let chat: Chat
    @Binding var path: NavigationPath
    @Binding var chatToDelete: Chat?
    @State private var pinLimit = false

    var body: some View {
        NavigationLink(value: Route.chat(chat.id)) {
            ChatRow(chat: chat)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { chatToDelete = chat } label: {
                Label("Löschen", systemImage: "trash")
            }
            Button { archive(!chat.isArchived) } label: {
                if chat.isArchived {
                    Label("Aus dem Archiv", systemImage: "tray.and.arrow.up")
                } else {
                    Label("Archivieren", systemImage: "archivebox")
                }
            }
            .tint(.indigo)
        }
        .swipeActions(edge: .leading) {
            Button { pin(!chat.isPinned) } label: {
                if chat.isPinned {
                    Label("Lösen", systemImage: "pin.slash")
                } else {
                    Label("Anpinnen", systemImage: "pin")
                }
            }
            .tint(.orange)
            Button { mute(chat.isMuted() ? nil : .distantFuture) } label: {
                if chat.isMuted() {
                    Label("Ton an", systemImage: "bell")
                } else {
                    Label("Stumm", systemImage: "bell.slash")
                }
            }
            .tint(.purple)
        }
        .contextMenu {
            if chat.isGroup {
                Button { path.append(Route.groupInfo(chat.id)) } label: {
                    Label("Gruppeninfo", systemImage: "info.circle")
                }
            } else {
                Button { path.append(Route.contact(chat.recipientId)) } label: {
                    Label("Kontaktinfo", systemImage: "info.circle")
                }
            }
            Button { pin(!chat.isPinned) } label: {
                if chat.isPinned {
                    Label("Lösen", systemImage: "pin.slash")
                } else {
                    Label("Anpinnen", systemImage: "pin")
                }
            }
            MuteMenu(chatId: chat.id)
            Button { archive(!chat.isArchived) } label: {
                if chat.isArchived {
                    Label("Aus dem Archiv", systemImage: "tray.and.arrow.up")
                } else {
                    Label("Archivieren", systemImage: "archivebox")
                }
            }
            Button(role: .destructive) { chatToDelete = chat } label: {
                Label("Chat löschen", systemImage: "trash")
            }
        }
        .alert("Höchstens \(MessengerEngine.maxPinned) Chats lassen sich anpinnen.", isPresented: $pinLimit) {
            Button("OK", role: .cancel) {}
        }
    }

    private func pin(_ on: Bool) {
        Haptics.selection()
        if !engine.setPinned(chat.id, on) { pinLimit = true }
    }

    private func mute(_ until: Date?) {
        Haptics.selection()
        engine.setMuted(chat.id, until: until)
    }

    private func archive(_ on: Bool) {
        Haptics.selection()
        engine.setArchived(chat.id, on)
    }
}

/// Stummschalten für eine Weile oder bis auf Weiteres.
struct MuteMenu: View {
    @Environment(MessengerEngine.self) private var engine
    let chatId: String

    var body: some View {
        if engine.chat(chatId)?.isMuted() == true {
            Button {
                Haptics.selection()
                engine.setMuted(chatId, until: nil)
            } label: {
                Label("Ton an", systemImage: "bell")
            }
        } else {
            Menu {
                Button("1 Stunde") { mute(3600) }
                Button("8 Stunden") { mute(8 * 3600) }
                Button("1 Woche") { mute(7 * 86_400) }
                Button("Bis ich es wieder einschalte") { mute(nil) }
            } label: {
                Label("Stumm", systemImage: "bell.slash")
            }
        }
    }

    private func mute(_ seconds: TimeInterval?) {
        Haptics.selection()
        engine.setMuted(chatId, until: seconds.map { Date().addingTimeInterval($0) } ?? .distantFuture)
    }
}

/// Das Archiv: Chats, die aus der Liste genommen sind.
private struct ArchivedChatsView: View {
    @Environment(MessengerEngine.self) private var engine
    @Binding var path: NavigationPath
    @Binding var chatToDelete: Chat?

    var body: some View {
        List {
            Section {
                ForEach(engine.archivedChats) { chat in
                    ChatListRow(chat: chat, path: $path, chatToDelete: $chatToDelete)
                }
            } footer: {
                Text("Archivierte Chats kommen mit der nächsten Nachricht zurück in die Liste, außer sie sind stumm.")
            }
        }
        .listStyle(.plain)
        .overlay {
            if engine.archivedChats.isEmpty {
                ContentUnavailableView("Keine archivierten Chats", systemImage: "archivebox")
            }
        }
        .navigationTitle("Archiviert")
    }
}

/// Ein Treffer der Suche: Chat, Ausschnitt, Zeit.
private struct SearchHitRow: View {
    @Environment(MessengerEngine.self) private var engine
    let hit: SearchHit
    let query: String

    var body: some View {
        let chat = engine.chat(hit.chatId)
        HStack(spacing: 10) {
            if let chat {
                ChatAvatar(chat: chat, size: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(chat?.name ?? "")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Format.listTime(hit.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(snippet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Der Treffer hervorgehoben, mit etwas Text davor.
    private var snippet: AttributedString {
        let prefix = hit.mine ? String(localized: "Du: ") : ""
        var text = hit.text
        if let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            let start = text.index(range.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
            if start > text.startIndex { text = "…" + String(text[start...]) }
        }
        var result = AttributedString(prefix + text)
        if let found = result.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            result[found].foregroundColor = Color.primary
            result[found].font = Font.subheadline.weight(.semibold)
        }
        return result
    }
}

/// Eine Zeile wie in Nachrichten: Punkt, Monogramm, Name, Vorschau, Zeit.
private struct ChatRow: View {
    @Environment(MessengerEngine.self) private var engine
    let chat: Chat

    var body: some View {
        let unread = engine.unreadCount(chat.id)
        HStack(spacing: 10) {
            Circle()
                .fill(unread > 0 ? (chat.isMuted() ? Color.secondary : Color.accentColor) : .clear)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            ChatAvatar(chat: chat, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(chat.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if chat.isMuted() {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Stumm")
                    }
                    if engine.contact(chat.recipientId)?.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Verifiziert")
                    }
                    Spacer(minLength: 4)
                    if chat.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Angepinnt")
                    }
                    if let time = chat.lastActivity {
                        Text(Format.listTime(time))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    if chat.ruleIsEphemeral {
                        Image(systemName: "timer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint(unread > 0 ? Text("\(unread) ungelesen") : Text(verbatim: ""))
    }

    private var preview: String {
        if chat.isGroup {
            guard let last = engine.lastMessage(chat.id) else { return String(localized: "Keine Nachrichten") }
            if !engine.chatPreviewEnabled { return String(localized: "Nachricht") }
            if last.isSystemEvent { return MessagePreview.text(for: last, me: engine.userId, engine: engine) }
            let who = last.senderId == engine.userId ? String(localized: "Du") : engine.memberName(last.senderId)
            return "\(who): " + MessagePreview.text(for: last, me: engine.userId)
        }
        guard let contact = engine.contact(chat.recipientId) else { return "" }
        if contact.requestState == .outgoing { return String(localized: "Wartet auf Bestätigung") }
        if contact.isGone { return String(localized: "Konto gelöscht") }
        guard let last = engine.lastMessage(chat.id) else { return String(localized: "Keine Nachrichten") }
        if !engine.chatPreviewEnabled { return String(localized: "Nachricht") }
        return MessagePreview.text(for: last, me: engine.userId)
    }
}

@MainActor
enum MessagePreview {
    static func text(for m: Message, me: String, engine: MessengerEngine? = nil) -> String {
        if let event = m.systemEvent {
            if let engine, engine.chat(m.chatId)?.isGroup == true {
                return SystemEventText.text(event, mine: m.senderId == me, timer: m.selfDestruct, name: engine.memberName(m.senderId),
                                            subject: SystemEventText.subject(of: m, engine: engine))
            }
            return SystemEventText.text(event, mine: m.senderId == me, timer: m.selfDestruct)
        }
        // Kein Betrag in der Vorschau: ungeprüft stünde dort, was der Absender behauptet.
        if m.payment != nil { return m.senderId == me ? String(localized: "₿ Du hast Bitcoin gesendet") : String(localized: "₿ Bitcoin-Zahlung") }
        if let r = m.paymentRequest {
            return m.senderId == me ? String(localized: "₿ Du bittest um \(BitcoinFormat.btc(r.sats))") : String(localized: "₿ Bitte um \(BitcoinFormat.btc(r.sats))")
        }
        if m.isPasswordProtected && !m.passwordUnlocked { return String(localized: "🔒 Geschützte Nachricht") }
        if m.oneTime { return String(localized: "Einmal ansehen") }
        if let a = m.attachment {
            let caption = m.text ?? ""
            return caption.isEmpty ? AttachmentLabel.text(a) : AttachmentLabel.text(a) + " " + caption
        }
        return m.text ?? ""
    }
}

/// Hinweisleiste oben, wie iOS sie für Warnungen nutzt.
struct Banner: View {
    let symbol: String
    let text: LocalizedStringKey
    var tint: Color = .orange

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.footnote)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
