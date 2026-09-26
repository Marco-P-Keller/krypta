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

                Section {
                    ForEach(chats) { chat in
                        NavigationLink(value: Route.chat(chat.id)) {
                            ChatRow(chat: chat)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { chatToDelete = chat } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button { path.append(Route.contact(chat.recipientId)) } label: {
                                Label("Kontaktinfo", systemImage: "info.circle")
                            }
                            Button(role: .destructive) { chatToDelete = chat } label: {
                                Label("Chat löschen", systemImage: "trash")
                            }
                        }
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
                } else if !search.isEmpty && chats.isEmpty {
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
                if app.iCloudMissing {
                    Banner(symbol: "icloud.slash", text: "Nicht bei iCloud angemeldet. Andere erreichen dich erst, wenn du dich in den Einstellungen anmeldest.", tint: .orange)
                } else if engine.keysPublished == false {
                    Banner(symbol: "icloud.slash", text: "Deine Schlüssel konnten nicht veröffentlicht werden. Andere können dich gerade nicht erreichen.", tint: .orange)
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .chat(let id): ConversationView(chatId: id)
                case .contact(let id): ContactDetailView(contactId: id)
                case .requests: RequestsView()
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
            guard let contact = engine.contact(contactId) else { return }
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
        let all = engine.sortedChats
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
}

enum Route: Hashable {
    case chat(String)
    case contact(String)
    case requests
}

/// Eine Zeile wie in Nachrichten: Punkt, Monogramm, Name, Vorschau, Zeit.
private struct ChatRow: View {
    @Environment(MessengerEngine.self) private var engine
    let chat: Chat

    var body: some View {
        let unread = engine.unreadCount(chat.id)
        HStack(spacing: 10) {
            Circle()
                .fill(unread > 0 ? Color.accentColor : .clear)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Avatar(id: chat.recipientId, name: chat.name, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(chat.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if engine.contact(chat.recipientId)?.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Verifiziert")
                    }
                    Spacer(minLength: 4)
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
        guard let contact = engine.contact(chat.recipientId) else { return "" }
        if contact.requestState == .outgoing { return String(localized: "Wartet auf Bestätigung") }
        if contact.isGone { return String(localized: "Konto gelöscht") }
        guard let last = engine.lastMessage(chat.id) else { return String(localized: "Keine Nachrichten") }
        if !engine.chatPreviewEnabled { return String(localized: "Nachricht") }
        return MessagePreview.text(for: last, me: engine.userId)
    }
}

enum MessagePreview {
    static func text(for m: Message, me: String) -> String {
        if let event = m.systemEvent { return SystemEventText.text(event, mine: m.senderId == me, timer: m.selfDestruct) }
        // Kein Betrag in der Vorschau: ungeprüft stünde dort, was der Absender behauptet.
        if m.payment != nil { return m.senderId == me ? String(localized: "₿ Du hast Bitcoin gesendet") : String(localized: "₿ Bitcoin-Zahlung") }
        if m.isPasswordProtected && !m.passwordUnlocked { return String(localized: "🔒 Geschützte Nachricht") }
        if m.oneTime { return String(localized: "Einmal ansehen") }
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
