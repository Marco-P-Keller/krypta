import KryptaMessenger
import SwiftUI

/// Neuer Chat: QR-Code scannen, eigenen Code zeigen oder Kennung eingeben.
struct NewChatView: View {
    @Environment(MessengerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    let open: (String) -> Void

    @State private var contactId = ""
    @State private var isAdding = false
    @State private var error: String?
    @State private var showScanner = false
    @State private var showMyCode = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showScanner = true } label: {
                        Label("QR-Code scannen", systemImage: "qrcode.viewfinder")
                    }
                    Button { showMyCode = true } label: {
                        Label("Meinen Code zeigen", systemImage: "qrcode")
                    }
                } footer: {
                    Text("Am sichersten: Scannt euch gegenseitig, wenn ihr nebeneinandersteht. Dann ist der Kontakt sofort verifiziert.")
                }

                Section {
                    TextField("Kennung", text: $contactId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .submitLabel(.go)
                        .onSubmit(add)
                        .accessibilityIdentifier("newchat.id")
                    if UIPasteboard.general.hasStrings {
                        Button("Aus Zwischenablage einfügen") {
                            contactId = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        }
                    }
                } header: {
                    Text("Mit Kennung hinzufügen")
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("Dein Kontakt bekommt eine Anfrage und muss sie annehmen.")
                    }
                }
            }
            .navigationTitle("Neuer Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAdding {
                        ProgressView()
                    } else {
                        Button("Hinzufügen", action: add)
                            .disabled(contactId.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("newchat.add")
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                ScannerSheet { payload in
                    showScanner = false
                    addFromQR(payload)
                }
            }
            .sheet(isPresented: $showMyCode) {
                MyCodeView()
            }
        }
    }

    private func add() {
        let id = contactId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !isAdding else { return }
        isAdding = true
        error = nil
        Task {
            let result = await engine.addContact(id: id)
            isAdding = false
            switch result {
            case .added(let contact):
                Haptics.success()
                if let chat = engine.chat(forContact: contact.id) { open(chat.id) } else { dismiss() }
            case .notFound: Haptics.error(); error = String(localized: "Zu dieser Kennung gibt es kein Konto.")
            case .invalidId: Haptics.error(); error = String(localized: "Das ist keine gültige Kennung.")
            case .isSelf: Haptics.error(); error = String(localized: "Das ist deine eigene Kennung.")
            }
        }
    }

    private func addFromQR(_ payload: QRPayload) {
        isAdding = true
        Task {
            let result = await engine.addContact(qr: payload)
            isAdding = false
            switch result {
            case .verified(let contact):
                if let chat = engine.chat(forContact: contact.id) { open(chat.id) } else { dismiss() }
            case .keyMismatch:
                Haptics.error()
                error = String(localized: "Der Schlüssel im QR-Code passt nicht zu dem auf dem Server. Möglicher Angriff — der Kontakt wurde gesperrt.")
            case .notFound:
                Haptics.error()
                error = String(localized: "Zu diesem QR-Code gibt es kein Konto.")
            }
        }
    }
}

/// Kamera mit Sucher und Erklärung.
private struct ScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let found: (QRPayload) -> Void
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerView { raw in
                    do {
                        found(try QRPayload.parse(raw))
                    } catch QRPayload.ParseError.fingerprintMismatch {
                        message = String(localized: "Dieser Code wurde verändert und wird abgelehnt.")
                    } catch {
                        message = String(localized: "Das ist kein Krypta-Code.")
                    }
                }
                .ignoresSafeArea()

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 240, height: 240)

                VStack {
                    Spacer()
                    Text(message ?? String(localized: "Richte die Kamera auf den Krypta-Code deines Kontakts."))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

/// Anfragen, die noch auf eine Antwort warten.
struct RequestsView: View {
    @Environment(MessengerEngine.self) private var engine

    var body: some View {
        List {
            ForEach(engine.incomingRequests) { contact in
                HStack(spacing: 12) {
                    Avatar(id: contact.id, name: contact.displayName, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.displayName).font(.body.weight(.semibold))
                        Text(contact.id).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { Haptics.destructive(); Task { await engine.declineRequest(contact.id) } } label: {
                        Label("Ablehnen", systemImage: "xmark")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button { Haptics.success(); Task { await engine.acceptRequest(contact.id) } } label: {
                        Label("Annehmen", systemImage: "checkmark")
                    }
                    .tint(.green)
                }
                .contextMenu {
                    Button { Haptics.success(); Task { await engine.acceptRequest(contact.id) } } label: { Label("Annehmen", systemImage: "checkmark") }
                    Button(role: .destructive) { Haptics.destructive(); Task { await engine.declineRequest(contact.id) } } label: { Label("Ablehnen", systemImage: "xmark") }
                }
            }
        }
        .overlay {
            if engine.incomingRequests.isEmpty {
                ContentUnavailableView("Keine Anfragen", systemImage: "person.crop.circle.badge.checkmark")
            }
        }
        .navigationTitle("Kontaktanfragen")
    }
}
