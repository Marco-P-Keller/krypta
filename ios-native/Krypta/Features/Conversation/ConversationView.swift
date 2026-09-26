import KryptaMessenger
import SwiftUI

/// Ein Chat — aufgebaut wie Nachrichten.
struct ConversationView: View {
    @Environment(MessengerEngine.self) private var engine
    @Environment(AppModel.self) private var app
    let chatId: String

    @State private var draft = ""
    @State private var option: ComposeOption = .chatRule
    @State private var password: String?
    @State private var askPassword = false
    @State private var passwordInput = ""
    @State private var unlockTarget: Message?
    @State private var unlockInput = ""
    @State private var unlockError: String?
    @State private var oneTimeText: String?
    @State private var resendTarget: Message?
    @FocusState private var composerFocused: Bool

    var body: some View {
        Group {
            if let chat = engine.chat(chatId), let contact = engine.contact(chat.recipientId) {
                content(chat: chat, contact: contact)
            } else {
                ContentUnavailableView("Chat gelöscht", systemImage: "bubble.left.and.exclamationmark.bubble.right")
            }
        }
        .onAppear { engine.openChat(chatId) }
        .onDisappear { Task { await engine.closeChat(chatId) } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            Task { await engine.reportSystemEvent(chatId: chatId, kind: .screenshot) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            if UIScreen.main.isCaptured {
                Task { await engine.reportSystemEvent(chatId: chatId, kind: .screenRecording) }
            }
        }
    }

    @ViewBuilder
    private func content(chat: Chat, contact: Contact) -> some View {
        let items = TranscriptItem.build(engine.messages(in: chatId), me: engine.userId)
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    row(item, chat: chat)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { banner(contact: contact) }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(chat: chat, contact: contact) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavigationLink(value: Route.contact(contact.id)) {
                    VStack(spacing: 2) {
                        Avatar(id: contact.id, name: chat.name, size: 30)
                        HStack(spacing: 2) {
                            Text(chat.name).font(.caption.weight(.medium))
                            Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.primary)
                    }
                }
                .accessibilityLabel("Kontaktinfo für \(chat.name)")
            }
        }
        .alert("Passwort für diese Nachricht", isPresented: $askPassword) {
            SecureField("Passwort", text: $passwordInput)
            Button("Abbrechen", role: .cancel) { passwordInput = "" }
            Button("Übernehmen") {
                if !passwordInput.isEmpty {
                    password = passwordInput
                    option = .password
                }
                passwordInput = ""
            }
        } message: {
            Text("Dein Kontakt braucht dieses Passwort, um die Nachricht zu lesen. Teile es auf anderem Weg.")
        }
        .alert("Nachricht entsperren", isPresented: Binding(get: { unlockTarget != nil }, set: { if !$0 { unlockTarget = nil } })) {
            SecureField("Passwort", text: $unlockInput)
            Button("Abbrechen", role: .cancel) { unlockInput = "" }
            Button("Entsperren") { unlock() }
        } message: {
            Text(unlockError ?? String(localized: "Gib das Passwort ein, das du bekommen hast."))
        }
        .confirmationDialog("Nachricht wurde nicht zugestellt", isPresented: Binding(get: { resendTarget != nil }, set: { if !$0 { resendTarget = nil } }), titleVisibility: .visible, presenting: resendTarget) { m in
            Button("Erneut senden") { Task { await engine.resend(chatId: chatId, messageId: m.id) } }
            Button("Löschen", role: .destructive) { engine.deleteForMe(chatId: chatId, messageId: m.id) }
        }
        .fullScreenCover(isPresented: Binding(get: { oneTimeText != nil }, set: { if !$0 { oneTimeText = nil } })) {
            ScreenshotShield(isEnabled: app.screenshotShield) {
                OneTimeReveal(text: oneTimeText ?? "") { oneTimeText = nil }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Verlauf

    @ViewBuilder
    private func row(_ item: TranscriptItem, chat: Chat) -> some View {
        switch item.kind {
        case .separator(let date):
            Text(Format.separator(date))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.top, 14)
                .padding(.bottom, 6)
        case .event(let m):
            Text(SystemEventText.text(m.systemEvent!, mine: m.senderId == engine.userId, timer: m.selfDestruct, name: chat.name))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 8)
                .padding(.horizontal, 24)
        case .message(let m, let position):
            MessageRow(message: m, position: position, mine: m.senderId == engine.userId,
                       deadline: engine.deadline(of: m),
                       onTap: { tapped(m) })
                .contextMenu { menu(for: m) }
                .padding(.top, position.isFirst ? 6 : 1)
        case .status(let status):
            Text(statusText(status))
                .font(.caption2.weight(.medium))
                .foregroundStyle(status == .failed ? .red : .secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 4)
                .padding(.top, 2)
                .transition(.opacity)
        }
    }

    private func statusText(_ status: MessageStatus) -> String {
        switch status {
        case .sending: String(localized: "Wird gesendet …")
        case .sent: String(localized: "Gesendet")
        case .delivered: String(localized: "Zugestellt")
        case .read: String(localized: "Gelesen")
        case .failed: String(localized: "Nicht zugestellt")
        }
    }

    @ViewBuilder
    private func menu(for m: Message) -> some View {
        let mine = m.senderId == engine.userId
        if let text = m.text, !m.oneTime, m.passwordUnlocked {
            Button { UIPasteboard.general.string = text } label: { Label("Kopieren", systemImage: "doc.on.doc") }
        }
        if mine && m.status == .failed {
            Button { Task { await engine.resend(chatId: chatId, messageId: m.id) } } label: {
                Label("Erneut senden", systemImage: "arrow.clockwise")
            }
        }
        Button(role: .destructive) { engine.deleteForMe(chatId: chatId, messageId: m.id) } label: {
            Label("Für mich löschen", systemImage: "trash")
        }
        if mine && m.status != .failed {
            Button(role: .destructive) { Task { await engine.deleteForEveryone(chatId: chatId, messageId: m.id) } } label: {
                Label("Für alle löschen", systemImage: "trash.slash")
            }
        }
    }

    private func tapped(_ m: Message) {
        let mine = m.senderId == engine.userId
        if mine && m.status == .failed {
            resendTarget = m
        } else if m.isPasswordProtected && !m.passwordUnlocked && !mine {
            unlockError = nil
            unlockTarget = m
        } else if m.oneTime && !mine {
            oneTimeText = engine.consumeOneTime(chatId: chatId, messageId: m.id)
        }
    }

    private func unlock() {
        guard let m = unlockTarget else { return }
        let input = unlockInput
        unlockInput = ""
        switch engine.unlock(chatId: chatId, messageId: m.id, password: input) {
        case .unlocked:
            unlockTarget = nil
        case .wrongPassword:
            unlockError = String(localized: "Falsches Passwort.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { unlockTarget = m }
        case .coolingDown:
            let wait = Int(engine.unlockCooldownRemaining(messageId: m.id).rounded(.up))
            unlockError = String(localized: "Zu viele Versuche. Warte \(wait) Sekunden.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { unlockTarget = m }
        }
    }

    // MARK: - Hinweise oben

    @ViewBuilder
    private func banner(contact: Contact) -> some View {
        if contact.hasKeyChanged {
            BannerAction(symbol: "exclamationmark.shield.fill", tint: .red,
                         text: "Die Sicherheitsnummer von \(contact.displayName) hat sich geändert. Überprüfe sie, bevor du weiterschreibst.",
                         action: "Überprüfen", route: .contact(contact.id))
        } else if contact.transparencyVerified == false {
            BannerAction(symbol: "exclamationmark.triangle.fill", tint: .red,
                         text: "Das Schlüsselprotokoll von \(contact.displayName) zeigt einen Widerspruch. Vergleicht die Sicherheitsnummer.",
                         action: "Details", route: .contact(contact.id))
        } else if contact.isBlocked {
            Banner(symbol: "hand.raised.fill", text: "Du hast diesen Kontakt blockiert.", tint: .red)
        } else if contact.isGone {
            Banner(symbol: "person.crop.circle.badge.xmark", text: "Dieses Konto wurde gelöscht.", tint: .secondary)
        } else if contact.requestState == .outgoing {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "hourglass").foregroundStyle(.orange)
                Text("Anfrage gesendet. Ihr könnt schreiben, sobald \(contact.displayName) annimmt.")
                    .font(.footnote)
                Spacer(minLength: 0)
                Button("Erneut") { Task { await engine.resendRequest(contact.id) } }
                    .font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    // MARK: - Unten: Eingabe oder Anfrage beantworten

    @ViewBuilder
    private func bottomBar(chat: Chat, contact: Contact) -> some View {
        if contact.requestState == .incoming {
            VStack(spacing: 10) {
                Text("\(contact.displayName) möchte mit dir schreiben.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button(role: .destructive) { Task { await engine.declineRequest(contact.id) } } label: {
                        Text("Ablehnen").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button { Task { await engine.acceptRequest(contact.id) } } label: {
                        Text("Annehmen").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }
            .padding(16)
            .background(.bar)
        } else if contact.canSendMessages {
            Composer(
                draft: $draft, option: $option, focused: $composerFocused,
                chatTimer: chat.timer, chatAfterRead: chat.deleteAfterRead,
                askPassword: { askPassword = true },
                send: { send(chat: chat) }
            )
        }
    }

    private func send(chat: Chat) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let options: SendOptions = switch option {
        case .chatRule: SendOptions(selfDestruct: chat.timer, fromChatRule: true)
        case .timer(let seconds): SendOptions(selfDestruct: seconds)
        case .afterRead: SendOptions(burnAfterRead: true)
        case .oneTime: SendOptions(oneTime: true)
        case .password: SendOptions(selfDestruct: chat.timer, fromChatRule: true, password: password)
        }
        draft = ""
        option = .chatRule
        password = nil
        Task { await engine.send(chatId: chatId, text: text, options: options) }
    }
}

/// Hinweisleiste mit Knopf, der zu einer Seite führt.
private struct BannerAction: View {
    let symbol: String
    let tint: Color
    let text: LocalizedStringKey
    let action: LocalizedStringKey
    let route: Route

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.footnote)
            Spacer(minLength: 0)
            NavigationLink(action, value: route).font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// Eine einmalige Nachricht: groß, einmal, dann weg.
private struct OneTimeReveal: View {
    let text: String
    let done: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.title3)
                    .textSelection(.disabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
            .safeAreaInset(edge: .top) {
                Label("Diese Nachricht verschwindet, sobald du sie schließt.", systemImage: "eye")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig", action: done)
                }
            }
        }
    }
}
