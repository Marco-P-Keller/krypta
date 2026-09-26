import KryptaMessenger
import SwiftUI

/// Kontaktinfo: Vertrauen, Löschfrist, Blockieren, Löschen.
struct ContactDetailView: View {
    @Environment(MessengerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    let contactId: String

    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmClear = false
    @State private var confirmDelete = false
    @State private var confirmBlock = false
    @State private var showScanner = false
    @State private var scanResult: String?

    var body: some View {
        if let contact = engine.contact(contactId) {
            let chat = engine.chat(forContact: contactId)
            List {
                Section {
                    VStack(spacing: 10) {
                        Avatar(id: contact.id, name: chat?.name ?? contact.displayName, size: 88)
                        Text(chat?.name ?? contact.displayName)
                            .font(.title2.weight(.semibold))
                        trustLabel(contact)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                verification(contact)

                if let chat, contact.requestState == .established {
                    Section {
                        Picker(selection: Binding(
                            get: { chat.deleteAfterRead ? -1 : (chat.timer ?? 0) },
                            set: { value in
                                Task { await engine.setChatRule(chat.id, timer: value > 0 ? value : nil, afterRead: value < 0) }
                            }
                        )) {
                            Text("Aus").tag(TimeInterval(0))
                            ForEach(Timers.chatRule, id: \.self) { Text(Format.duration($0)).tag($0) }
                            Text("Nach dem Lesen").tag(TimeInterval(-1))
                        } label: {
                            Label("Löschfrist", systemImage: "timer")
                        }
                    } footer: {
                        Text("Gilt für neue Nachrichten in beiden Richtungen. Die Frist beginnt mit der Zustellung.")
                    }
                }

                Section {
                    LabeledContent("Kennung") {
                        Text(contact.id)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    LabeledContent("Schlüssel") {
                        Text(contact.shortFingerprint).font(.footnote.monospaced())
                    }
                }

                Section {
                    if let chat {
                        Button("Chat leeren", role: .destructive) { confirmClear = true }
                            .confirmationDialog("Chat leeren?", isPresented: $confirmClear, titleVisibility: .visible) {
                                Button("Chat leeren", role: .destructive) { Task { await engine.clearChat(chat.id) } }
                            } message: {
                                Text("Alle Nachrichten verschwinden hier. Deine eigenen werden auch bei \(chat.name) entfernt.")
                            }
                    }
                    if contact.isBlocked {
                        Button("Nicht mehr blockieren") { engine.unblock(contact.id) }
                    } else {
                        Button("Kontakt blockieren", role: .destructive) { confirmBlock = true }
                            .confirmationDialog("Kontakt blockieren?", isPresented: $confirmBlock, titleVisibility: .visible) {
                                Button("Blockieren", role: .destructive) { engine.block(contact.id) }
                            } message: {
                                Text("Du bekommst keine Nachrichten mehr von diesem Kontakt.")
                            }
                    }
                    if let chat {
                        Button("Chat löschen", role: .destructive) { confirmDelete = true }
                            .confirmationDialog("Chat löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                                Button("Chat löschen", role: .destructive) {
                                    Task {
                                        await engine.deleteChat(chat.id)
                                        dismiss()
                                    }
                                }
                            } message: {
                                Text("Der Chat verschwindet von diesem iPhone. Bei \(chat.name) werden deine Nachrichten entfernt.")
                            }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bearbeiten") {
                        newName = chat?.name ?? contact.displayName
                        renaming = true
                    }
                    .disabled(chat == nil)
                }
            }
            .alert("Name", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Abbrechen", role: .cancel) {}
                Button("Sichern") { if let chat { engine.rename(chatId: chat.id, to: newName) } }
            } message: {
                Text("Nur du siehst diesen Namen.")
            }
            .sheet(isPresented: $showScanner) {
                NavigationStack {
                    QRScannerView { raw in
                        showScanner = false
                        verify(with: raw, contact: contact)
                    }
                    .ignoresSafeArea()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showScanner = false } } }
                }
            }
            .alert(scanResult ?? "", isPresented: Binding(get: { scanResult != nil }, set: { if !$0 { scanResult = nil } })) {
                Button("OK", role: .cancel) {}
            }
        } else {
            ContentUnavailableView("Kontakt gelöscht", systemImage: "person.crop.circle.badge.xmark")
        }
    }

    @ViewBuilder
    private func trustLabel(_ contact: Contact) -> some View {
        if contact.hasKeyChanged {
            Label("Sicherheitsnummer geändert", systemImage: "exclamationmark.shield.fill")
                .font(.subheadline).foregroundStyle(.red)
        } else if contact.isVerified {
            Label("Verifiziert", systemImage: "checkmark.seal.fill")
                .font(.subheadline).foregroundStyle(.tint)
        } else {
            Label("Nicht verifiziert", systemImage: "questionmark.circle")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func verification(_ contact: Contact) -> some View {
        Section {
            if let number = engine.safetyNumber(for: contact.id) {
                SafetyNumberGrid(number: number)
                    .padding(.vertical, 6)
            }
            Button { showScanner = true } label: {
                Label("Code des Kontakts scannen", systemImage: "qrcode.viewfinder")
            }
            if !contact.isVerified {
                Button { engine.markVerified(contact.id) } label: {
                    Label("Als verifiziert markieren", systemImage: "checkmark.seal")
                }
            }
        } header: {
            Text("Sicherheitsnummer")
        } footer: {
            Text("Vergleicht diese Zahl auf beiden Geräten — am besten nebeneinander oder in einem Anruf. Stimmt sie überein, liest niemand mit.")
        }
    }

    /// Verifizieren per QR: der Schlüssel im Code muss der hinterlegte sein.
    private func verify(with raw: String, contact: Contact) {
        guard let payload = try? QRPayload.parse(raw), payload.userId == contact.id else {
            scanResult = String(localized: "Das ist nicht der Code dieses Kontakts.")
            return
        }
        guard payload.publicKey == contact.publicKey else {
            scanResult = String(localized: "Die Schlüssel stimmen nicht überein. Schreibe diesem Kontakt nichts Vertrauliches.")
            return
        }
        engine.markVerified(contact.id, method: .qrCode)
        scanResult = String(localized: "Verifiziert. Die Schlüssel stimmen überein.")
    }
}

/// 60 Ziffern in zwölf Fünfergruppen, wie Signal sie zeigt.
struct SafetyNumberGrid: View {
    let number: String

    var body: some View {
        let groups = SafetyNumberFormat.groups(number)
        Grid(horizontalSpacing: 18, verticalSpacing: 8) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<4, id: \.self) { col in
                        Text(groups[safe: row * 4 + col] ?? "")
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(groups.joined(separator: ", "))
    }
}

enum SafetyNumberFormat {
    static func groups(_ number: String) -> [String] {
        stride(from: 0, to: number.count, by: 5).map {
            let start = number.index(number.startIndex, offsetBy: $0)
            return String(number[start..<number.index(start, offsetBy: min(5, number.count - $0))])
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
