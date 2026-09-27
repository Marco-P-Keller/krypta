import AVFoundation
import KryptaMessenger
import KryptaWallet
import PhotosUI
import SwiftUI

/// Ein Chat — aufgebaut wie Nachrichten.
struct ConversationView: View {
    @Environment(MessengerEngine.self) private var engine
    @Environment(AppModel.self) private var app
    @Environment(WalletEngine.self) private var wallet: WalletEngine?
    let chatId: String
    /// Aus der Suche: zu dieser Nachricht scrollen.
    var highlight: String?

    @State private var draft = ""
    @State private var option: ComposeOption = .chatRule
    @State private var password: String?
    @State private var askPassword = false
    @State private var passwordInput = ""
    @State private var unlockTarget: Message?
    @State private var unlockInput = ""
    @State private var unlockError: String?
    @State private var oneTimeText: String?
    @State private var oneTimeTarget: Message?
    @State private var resendTarget: Message?
    @State private var paying = false
    @State private var payHint: String?
    @State private var paymentDetail: Message?
    /// Antwort auf oder Bearbeitung einer Nachricht (Kennung).
    @State private var context: ComposeContext?
    @State private var scrollTarget: String?
    // Anhänge
    @State private var showPhotos = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var showVoice = false
    @State private var preparing = false
    @State private var pendingAttachment: PendingAttachment?
    @State private var attachmentError: String?
    @State private var viewing: Message?
    @State private var viewingOnce: OnceAttachment?
    @FocusState private var composerFocused: Bool

    var body: some View {
        Group {
            if let chat = engine.chat(chatId), chat.isGroup || engine.contact(chat.recipientId) != nil {
                content(chat: chat, contact: engine.contact(chat.recipientId))
            } else {
                ContentUnavailableView("Chat gelöscht", systemImage: "bubble.left.and.exclamationmark.bubble.right")
            }
        }
        .onAppear {
            engine.openChat(chatId)
            if let highlight {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { scrollTarget = highlight }
            }
            if let contactId = engine.chat(chatId)?.recipientId { PushService.shared.clearDelivered(contactId: contactId) }
        }
        .onDisappear { Task { await engine.closeChat(chatId) } }
        // Leise, wenn im offenen Chat etwas ankommt; deutlich, wenn etwas
        // von mir nicht zugestellt wurde.
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.35), trigger: incomingCount) { old, new in new > old }
        .sensoryFeedback(.error, trigger: failedCount) { old, new in new > old }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            Task { await engine.reportSystemEvent(chatId: chatId, kind: .screenshot) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            if UIScreen.main.isCaptured {
                Task { await engine.reportSystemEvent(chatId: chatId, kind: .screenRecording) }
            }
        }
    }

    private var incomingCount: Int {
        engine.messages(in: chatId).filter { $0.senderId != engine.userId && !$0.isSystemEvent }.count
    }

    private var failedCount: Int {
        engine.messages(in: chatId).filter { $0.senderId == engine.userId && $0.status == .failed }.count
    }

    @ViewBuilder
    private func content(chat: Chat, contact: Contact?) -> some View {
        // In Teilen: am Stück ist die Kette für den Compiler zu lang.
        let base = transcript(chat: chat, contact: contact)
        let dialogs = messageDialogs(base, contact: contact)
        attachmentViewers(attachmentPresentations(dialogs, chat: chat))
    }

    @ViewBuilder
    private func transcript(chat: Chat, contact: Contact?) -> some View {
        let all = engine.messages(in: chatId)
        let items = TranscriptItem.build(all, me: engine.userId)
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        row(item, chat: chat, byId: byId)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.smooth) { proxy.scrollTo(target, anchor: .center) }
                scrollTarget = nil
            }
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let contact {
                banner(contact: contact)
            } else if chat.group?.hasLeft == true {
                Banner(symbol: "person.3", text: "Du bist nicht mehr in dieser Gruppe.", tint: .secondary)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(chat: chat, contact: contact) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavigationLink(value: chat.isGroup ? Route.groupInfo(chat.id) : Route.contact(chat.recipientId)) {
                    VStack(spacing: 2) {
                        ChatAvatar(chat: chat, size: 30)
                        HStack(spacing: 2) {
                            Text(chat.name).font(.caption.weight(.medium))
                            Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.primary)
                    }
                }
                .accessibilityLabel(chat.isGroup ? Text("Gruppeninfo für \(chat.name)") : Text("Kontaktinfo für \(chat.name)"))
            }
        }
    }

    /// Passwort, Entsperren, erneut senden, einmal ansehen, Bitcoin.
    private func messageDialogs<V: View>(_ view: V, contact: Contact?) -> some View {
        view
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
            Button("Erneut senden") { Haptics.confirm(); Task { await engine.resend(chatId: chatId, messageId: m.id) } }
            Button("Löschen", role: .destructive) { Haptics.destructive(); engine.deleteForMe(chatId: chatId, messageId: m.id) }
        }
        .alert("Einmalige Nachricht öffnen?", isPresented: Binding(get: { oneTimeTarget != nil }, set: { if !$0 { oneTimeTarget = nil } }), presenting: oneTimeTarget) { m in
            Button("Abbrechen", role: .cancel) {}
            Button("Öffnen") {
                if m.attachment != nil {
                    if let opened = engine.openOneTimeAttachment(chatId: chatId, messageId: m.id) {
                        viewingOnce = OnceAttachment(data: opened.0, attachment: opened.1)
                    }
                } else {
                    oneTimeText = engine.consumeOneTime(chatId: chatId, messageId: m.id)
                }
            }
        } message: { _ in
            Text("Du kannst sie nur einmal ansehen. Sobald du sie schließt, ist sie für immer weg.")
        }
        .sheet(isPresented: $paying) {
            if let contact {
                ShieldedSheet { SendBitcoinView(target: .contact(chatId: chatId, contactId: contact.id)) }
            }
        }
        .sheet(item: $paymentDetail) { m in
            ShieldedSheet { PaymentDetailView(message: m) }
        }
        .alert("Bitcoin senden", isPresented: Binding(get: { payHint != nil }, set: { if !$0 { payHint = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(payHint ?? "")
        }
        .fullScreenCover(isPresented: Binding(get: { oneTimeText != nil }, set: { if !$0 { oneTimeText = nil } })) {
            ScreenshotShield(isEnabled: app.screenshotShield) {
                OneTimeReveal(text: oneTimeText ?? "") { oneTimeText = nil }
            }
            .ignoresSafeArea()
        }
    }

    /// Auswählen, Aufnehmen, Vorschau und Ansehen von Anhängen.
    private func attachmentPresentations<V: View>(_ view: V, chat: Chat) -> some View {
        view
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .any(of: [.images, .videos]))
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            prepare { try await Self.load(item) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            prepare { try AttachmentPreparer.file(at: url) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { result in
                showCamera = false
                switch result {
                case .photo(let image)?: prepare { try AttachmentPreparer.image(from: image) }
                case .movie(let url)?: prepare { try await AttachmentPreparer.video(at: url) }
                case nil: break
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showVoice) {
            VoiceRecorderSheet { url, duration in
                prepare(sendDirectly: true) {
                    defer { try? FileManager.default.removeItem(at: url) }
                    return try AttachmentPreparer.audio(at: url, duration: duration)
                }
            }
        }
        .sheet(item: $pendingAttachment) { pending in
            AttachmentComposeSheet(pending: pending) { out, caption, once in
                sendAttachment(out, caption: caption, once: once, chat: chat)
            }
        }
    }

    /// Anhänge ansehen und Fehler beim Vorbereiten.
    private func attachmentViewers<V: View>(_ view: V) -> some View {
        view
        .fullScreenCover(item: $viewing) { m in
            ShieldedSheet {
                if let a = m.attachment, let data = engine.attachmentData(m) {
                    AttachmentViewer(data: data, attachment: a)
                }
            }
        }
        .fullScreenCover(item: $viewingOnce) { once in
            ShieldedSheet {
                AttachmentViewer(data: once.data, attachment: once.attachment, once: true)
            }
        }
        .overlay {
            if preparing {
                ProgressView("Wird vorbereitet …")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .alert("Anhang", isPresented: Binding(get: { attachmentError != nil }, set: { if !$0 { attachmentError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(attachmentError ?? "")
        }
    }

    // MARK: - Verlauf

    @ViewBuilder
    private func row(_ item: TranscriptItem, chat: Chat, byId: [String: Message]) -> some View {
        switch item.kind {
        case .separator(let date):
            Text(Format.separator(date))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.top, 14)
                .padding(.bottom, 6)
        case .event(let m):
            Text(chat.isGroup
                 ? SystemEventText.text(m.systemEvent!, mine: m.senderId == engine.userId, timer: m.selfDestruct,
                                        name: engine.memberName(m.senderId), subject: SystemEventText.subject(of: m, engine: engine))
                 : SystemEventText.text(m.systemEvent!, mine: m.senderId == engine.userId, timer: m.selfDestruct, name: chat.name))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 8)
                .padding(.horizontal, 24)
        case .message(let m, let position):
            MessageRow(message: m, position: position, mine: m.senderId == engine.userId,
                       deadline: engine.deadline(of: m),
                       onTap: { tapped(m) },
                       quote: quote(for: m, chat: chat, byId: byId),
                       reactions: ReactionChip.build(m, me: engine.userId),
                       senderName: chat.isGroup ? engine.memberName(m.senderId) : nil,
                       onQuoteTap: { scrollTarget = $0 },
                       onReactionTap: { chip in
                           guard chip.mine else { return }
                           Haptics.selection()
                           Task { await engine.react(chatId: chatId, messageId: m.id, emoji: nil) }
                       })
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

    /// Das Zitat über einer Antwort, aus dem eigenen Verlauf.
    private func quote(for m: Message, chat: Chat, byId: [String: Message]) -> QuoteInfo? {
        guard let target = m.replyTo else { return nil }
        guard let original = byId[target] else {
            return QuoteInfo(targetId: target, author: chat.isGroup ? "" : chat.name, text: nil)
        }
        let author = original.senderId == engine.userId ? String(localized: "Du") : (chat.isGroup ? engine.memberName(original.senderId) : chat.name)
        let text = ReplyPolicy.canQuote(original) ? MessagePreview.text(for: original, me: engine.userId) : nil
        return QuoteInfo(targetId: target, author: author, text: text)
    }

    @ViewBuilder
    private func menu(for m: Message) -> some View {
        let mine = m.senderId == engine.userId
        let extras = engine.supportsExtras(chatId: chatId)
        if extras && ReactionPolicy.canReact(to: m) && m.status != .failed && m.status != .sending {
            Menu {
                ForEach(ReactionPolicy.quick, id: \.self) { emoji in
                    Button {
                        Haptics.selection()
                        Task { await engine.react(chatId: chatId, messageId: m.id, emoji: emoji) }
                    } label: {
                        Text(verbatim: m.reactions?[engine.userId] == emoji ? "\(emoji) ✓" : emoji)
                    }
                }
                if m.reactions?[engine.userId] != nil {
                    Divider()
                    Button(role: .destructive) {
                        Task { await engine.react(chatId: chatId, messageId: m.id, emoji: nil) }
                    } label: {
                        Label("Reaktion entfernen", systemImage: "xmark")
                    }
                }
            } label: {
                Label("Reagieren", systemImage: "face.smiling")
            }
        }
        if engine.canWrite(chatId: chatId) && ReplyPolicy.canQuote(m) && m.status != .failed {
            Button {
                context = .reply(m.id)
                composerFocused = true
            } label: {
                Label("Antworten", systemImage: "arrowshape.turn.up.left")
            }
        }
        if extras && EditPolicy.canEdit(m, me: engine.userId) {
            Button {
                context = .edit(m.id)
                draft = m.text ?? ""
                option = .chatRule
                composerFocused = true
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
        }
        if let text = m.text, !m.oneTime, m.passwordUnlocked {
            Button { SecurePasteboard.copy(text); Haptics.confirm() } label: { Label("Kopieren", systemImage: "doc.on.doc") }
        }
        if mine && m.status == .failed {
            Button { Haptics.confirm(); Task { await engine.resend(chatId: chatId, messageId: m.id) } } label: {
                Label("Erneut senden", systemImage: "arrow.clockwise")
            }
        }
        Button(role: .destructive) { Haptics.destructive(); engine.deleteForMe(chatId: chatId, messageId: m.id) } label: {
            Label("Für mich löschen", systemImage: "trash")
        }
        if mine && m.status != .failed {
            Button(role: .destructive) { Haptics.destructive(); Task { await engine.deleteForEveryone(chatId: chatId, messageId: m.id) } } label: {
                Label("Für alle löschen", systemImage: "trash.slash")
            }
        }
    }

    private func tapped(_ m: Message) {
        let mine = m.senderId == engine.userId
        if let a = m.attachment, !(m.oneTime && !mine), !(mine && m.status == .failed) {
            if a.state == .failed && !mine {
                engine.retryAttachment(chatId: chatId, messageId: m.id)
            } else if a.state == .ready && a.kind != .audio {
                viewing = m
            }
            return
        }
        if m.oneTime && !mine, let a = m.attachment {
            // Erst öffnen, wenn der Anhang da ist.
            if a.state == .ready {
                oneTimeTarget = m
            } else if a.state == .failed {
                engine.retryAttachment(chatId: chatId, messageId: m.id)
            }
            return
        }
        if m.payment != nil && !(mine && m.status == .failed) {
            paymentDetail = m
        } else if mine && m.status == .failed {
            resendTarget = m
        } else if m.isPasswordProtected && !m.passwordUnlocked && !mine {
            unlockError = nil
            unlockTarget = m
        } else if m.oneTime && !mine {
            oneTimeTarget = m
        }
    }

    private func unlock() {
        guard let m = unlockTarget else { return }
        let input = unlockInput
        unlockInput = ""
        switch engine.unlock(chatId: chatId, messageId: m.id, password: input) {
        case .unlocked:
            Haptics.success()
            unlockTarget = nil
        case .wrongPassword:
            Haptics.error()
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
                Button("Erneut") { Haptics.confirm(); Task { await engine.resendRequest(contact.id) } }
                    .font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    // MARK: - Unten: Eingabe oder Anfrage beantworten

    @ViewBuilder
    private func bottomBar(chat: Chat, contact: Contact?) -> some View {
        if chat.isGroup {
            if engine.canWrite(chatId: chat.id) {
                VStack(spacing: 0) {
                    if let context {
                        contextBar(context, chat: chat)
                    }
                    Composer(
                        draft: $draft, option: $option, focused: $composerFocused,
                        chatTimer: chat.timer, chatAfterRead: chat.deleteAfterRead,
                        askPassword: { askPassword = true },
                        payBitcoin: nil,
                        attach: attachmentActions,
                        send: { send(chat: chat) }
                    )
                }
            }
        } else if let contact {
            directBottomBar(chat: chat, contact: contact)
        }
    }

    @ViewBuilder
    private func directBottomBar(chat: Chat, contact: Contact) -> some View {
        if contact.requestState == .incoming {
            VStack(spacing: 10) {
                Text("\(contact.displayName) möchte mit dir schreiben.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button(role: .destructive) { Haptics.destructive(); Task { await engine.declineRequest(contact.id) } } label: {
                        Text("Ablehnen").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button { Haptics.success(); Task { await engine.acceptRequest(contact.id) } } label: {
                        Text("Annehmen").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }
            .padding(16)
            .background(.bar)
        } else if contact.canSendMessages {
            VStack(spacing: 0) {
                if let context {
                    contextBar(context, chat: chat)
                }
                Composer(
                    draft: $draft, option: $option, focused: $composerFocused,
                    chatTimer: chat.timer, chatAfterRead: chat.deleteAfterRead,
                    askPassword: { askPassword = true },
                    payBitcoin: wallet == nil ? nil : { startPayment(contact) },
                    attach: attachmentActions,
                    send: { send(chat: chat) }
                )
            }
        }
    }

    /// Bitcoin an diesen Kontakt: geht nur, wenn er eine Adresse geschickt hat.
    private func startPayment(_ contact: Contact) {
        switch engine.paymentBlock(for: contact.id) {
        case nil:
            paying = true
        case .waitingForAddress?:
            payHint = String(localized: "\(contact.displayName) hat dir noch keine Bitcoin-Adresse geschickt. Sie kommt verschlüsselt mit der nächsten Nachricht von \(contact.displayName).")
        case .noWalletThere?:
            payHint = String(localized: "\(contact.displayName) kann im Chat keine Bitcoin empfangen (ältere Krypta-Version oder Zahlungen im Chat ausgeschaltet).")
        case .otherNetwork?:
            payHint = String(localized: "\(contact.displayName) nutzt ein anderes Bitcoin-Netz als du.")
        case .noWallet?, .cannotMessage?:
            payHint = String(localized: "Gerade nicht möglich.")
        }
    }

    // MARK: - Anhänge

    /// Anhänge nur mit Speicher und nur an die native App (Flutter kennt sie nicht).
    private var attachmentActions: AttachmentActions? {
        guard engine.supportsAttachments, engine.supportsExtras(chatId: chatId) else { return nil }
        return AttachmentActions(
            photo: { showPhotos = true },
            camera: {
                Task {
                    if await Self.cameraAllowed() {
                        showCamera = true
                    } else {
                        attachmentError = String(localized: "Erlaube die Kamera in den iOS-Einstellungen unter Krypta.")
                    }
                }
            },
            file: { showFiles = true },
            voice: { showVoice = true }
        )
    }

    /// Die Frage nach der Kamera (und fürs Video nach dem Mikrofon) selbst
    /// stellen: sie gilt nicht als Verlassen der App.
    private static func cameraAllowed() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await SystemPrompt.during { await AVCaptureDevice.requestAccess(for: .video) }
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await SystemPrompt.during { await AVCaptureDevice.requestAccess(for: .audio) }
        }
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    /// Aus der Mediathek: Video als Datei, Foto als Daten.
    private static func load(_ item: PhotosPickerItem) async throws -> OutgoingAttachment {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }),
           let movie = try await item.loadTransferable(type: PickedMovie.self) {
            defer { try? FileManager.default.removeItem(at: movie.url) }
            return try await AttachmentPreparer.video(at: movie.url)
        }
        guard let data = try await item.loadTransferable(type: Data.self) else { throw AttachmentPreparer.Failure.unreadable }
        return try AttachmentPreparer.image(from: data)
    }

    /// Aufbereiten (Metadaten weg), dann Vorschau oder gleich senden.
    private func prepare(sendDirectly: Bool = false, _ work: @escaping @MainActor () async throws -> OutgoingAttachment) {
        preparing = true
        Task {
            defer { preparing = false }
            do {
                let out = try await work()
                if sendDirectly, let chat = engine.chat(chatId) {
                    sendAttachment(out, caption: "", once: false, chat: chat)
                } else {
                    pendingAttachment = PendingAttachment(out: out)
                }
            } catch {
                Haptics.error()
                attachmentError = (error as? LocalizedError)?.errorDescription ?? String(localized: "Der Anhang konnte nicht vorbereitet werden.")
            }
        }
    }

    private func sendAttachment(_ out: OutgoingAttachment, caption: String, once: Bool, chat: Chat) {
        var options = once ? SendOptions(oneTime: true) : SendOptions(selfDestruct: chat.timer, fromChatRule: true)
        if case .reply(let id)? = context { options.replyTo = id }
        context = nil
        Haptics.confirm()
        Task { await engine.sendAttachment(chatId: chatId, out, caption: caption, options: options) }
    }

    /// Leiste über der Eingabe: worauf man antwortet oder was man bearbeitet.
    @ViewBuilder
    private func contextBar(_ context: ComposeContext, chat: Chat) -> some View {
        let target = engine.messages(in: chatId).first { $0.id == context.messageId }
        HStack(spacing: 10) {
            Image(systemName: context.isEdit ? "pencil" : "arrowshape.turn.up.left")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                if context.isEdit {
                    Text("Nachricht bearbeiten").font(.caption.weight(.semibold))
                } else if target?.senderId == engine.userId {
                    Text("Antwort auf deine Nachricht").font(.caption.weight(.semibold))
                } else {
                    Text("Antwort an \(chat.isGroup ? engine.memberName(target?.senderId ?? "") : chat.name)").font(.caption.weight(.semibold))
                }
                Text(target.map { MessagePreview.text(for: $0, me: engine.userId) } ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                if context.isEdit { draft = "" }
                self.context = nil
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .accessibilityLabel(context.isEdit ? Text("Bearbeiten abbrechen") : Text("Antwort abbrechen"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(.bar)
        .onChange(of: target == nil) { _, gone in if gone { self.context = nil } }
    }

    private func send(chat: Chat) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if case .edit(let id)? = context {
            draft = ""
            context = nil
            Haptics.confirm()
            Task { await engine.edit(chatId: chatId, messageId: id, text: text) }
            return
        }
        var options: SendOptions = switch option {
        case .chatRule: SendOptions(selfDestruct: chat.timer, fromChatRule: true)
        case .timer(let seconds): SendOptions(selfDestruct: seconds)
        case .afterRead: SendOptions(burnAfterRead: true)
        case .oneTime: SendOptions(oneTime: true)
        case .password: SendOptions(selfDestruct: chat.timer, fromChatRule: true, password: password)
        }
        if case .reply(let id)? = context { options.replyTo = id }
        context = nil
        draft = ""
        option = .chatRule
        password = nil
        Haptics.confirm()
        Task { await engine.send(chatId: chatId, text: text, options: options) }
    }
}

/// Ein einmal-Anhang, gerade geöffnet.
struct OnceAttachment: Identifiable {
    let id = UUID()
    let data: Data
    let attachment: Attachment
}

/// Worauf sich die nächste Eingabe bezieht.
enum ComposeContext: Equatable {
    case reply(String)
    case edit(String)

    var messageId: String {
        switch self {
        case .reply(let id), .edit(let id): id
        }
    }

    var isEdit: Bool {
        if case .edit = self { return true }
        return false
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
