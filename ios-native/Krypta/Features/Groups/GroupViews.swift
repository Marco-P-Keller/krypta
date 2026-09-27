import KryptaMessenger
import SwiftUI

/// Bild einer Gruppe: Kreis mit Personen, die Farbe hängt an der Kennung.
struct GroupAvatar: View {
    let id: String
    var size: CGFloat = 44

    var body: some View {
        Circle()
            .fill(Avatar.gradient(for: id))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "person.3.fill")
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// Einzelchat oder Gruppe: das passende Bild.
struct ChatAvatar: View {
    let chat: Chat
    var size: CGFloat = 44

    var body: some View {
        if chat.isGroup {
            GroupAvatar(id: chat.recipientId, size: size)
        } else {
            Avatar(id: chat.recipientId, name: chat.name, size: size)
        }
    }
}

/// Kontakte auswählen, mit Häkchen.
private struct ContactPicker: View {
    @Environment(MessengerEngine.self) private var engine
    let candidates: [Contact]
    @Binding var selection: Set<String>
    let limit: Int

    var body: some View {
        ForEach(candidates) { contact in
            let chosen = selection.contains(contact.id)
            Button {
                Haptics.selection()
                if chosen { selection.remove(contact.id) } else if selection.count < limit { selection.insert(contact.id) }
            } label: {
                HStack(spacing: 12) {
                    Avatar(id: contact.id, name: engine.memberName(contact.id), size: 36)
                    Text(engine.memberName(contact.id)).foregroundStyle(.primary)
                    if contact.isVerified {
                        Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.tint)
                            .accessibilityLabel("Verifiziert")
                    }
                    Spacer()
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(chosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(chosen ? .isSelected : [])
        }
    }
}

/// Neue Gruppe: Name und Mitglieder.
struct NewGroupView: View {
    @Environment(MessengerEngine.self) private var engine
    let open: (String) -> Void

    @State private var name = ""
    @State private var selection: Set<String> = []
    @State private var creating = false
    @State private var failed = false

    var body: some View {
        Form {
            Section {
                TextField("Name der Gruppe", text: $name)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("group.name")
            } footer: {
                Text("Alle Mitglieder sehen den Namen der Gruppe. Wie du deine Kontakte genannt hast, sehen sie nicht.")
            }
            Section {
                if engine.groupCandidates.isEmpty {
                    Text("Noch niemand, den du einladen kannst. Mitglieder brauchen die aktuelle Krypta-App und müssen deine Anfrage angenommen haben.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ContactPicker(candidates: engine.groupCandidates, selection: $selection, limit: GroupPolicy.maxMembers - 1)
                }
            } header: {
                Text("Mitglieder")
            } footer: {
                Text("Jede Nachricht geht einzeln und Ende-zu-Ende-verschlüsselt an jedes Mitglied. Der Server erfährt nicht, dass es eine Gruppe gibt. Mitglieder, die sich noch nicht kennen, stellt Krypta einander vor; ihre Sicherheitsnummer vergleichen sie selbst.")
            }
        }
        .navigationTitle("Neue Gruppe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if creating {
                    ProgressView()
                } else {
                    Button("Erstellen", action: create)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selection.isEmpty)
                        .accessibilityIdentifier("group.create")
                }
            }
        }
        .alert("Die Gruppe konnte nicht erstellt werden.", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func create() {
        creating = true
        Task {
            let chatId = await engine.createGroup(name: name, memberIds: Array(selection))
            creating = false
            if let chatId {
                Haptics.success()
                open(chatId)
            } else {
                Haptics.error()
                failed = true
            }
        }
    }
}

/// Gruppeninfo: Mitglieder, Name, Löschfrist, stumm, austreten.
struct GroupInfoView: View {
    @Environment(MessengerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    let chatId: String

    @State private var renaming = false
    @State private var newName = ""
    @State private var adding = false
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @State private var memberToRemove: String?

    var body: some View {
        if let chat = engine.chat(chatId), let group = chat.group {
            let isAdmin = group.isAdmin(engine.userId) && !group.hasLeft
            List {
                Section {
                    VStack(spacing: 10) {
                        GroupAvatar(id: chat.recipientId, size: 88)
                        Text(chat.name).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                        Text(group.hasLeft ? String(localized: "Du bist nicht mehr in dieser Gruppe.") : String(localized: "\(group.members.count) Mitglieder"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                if !group.hasLeft {
                    Section {
                        ForEach(sortedMembers(group), id: \.self) { uid in
                            memberLink(uid, group: group)
                                .swipeActions(edge: .trailing) {
                                    if isAdmin && uid != engine.userId {
                                        Button(role: .destructive) { memberToRemove = uid } label: {
                                            Label("Entfernen", systemImage: "person.badge.minus")
                                        }
                                    }
                                }
                                .contextMenu {
                                    if isAdmin && uid != engine.userId {
                                        Button(role: .destructive) { memberToRemove = uid } label: {
                                            Label("Aus der Gruppe entfernen", systemImage: "person.badge.minus")
                                        }
                                    }
                                }
                        }
                        if isAdmin && group.members.count < GroupPolicy.maxMembers {
                            Button { adding = true } label: {
                                Label("Mitglieder hinzufügen", systemImage: "person.badge.plus")
                            }
                        }
                    } header: {
                        Text("Mitglieder")
                    } footer: {
                        if isAdmin {
                            Text("Du verwaltest diese Gruppe: nur du kannst Mitglieder hinzufügen oder entfernen, sie umbenennen und die Löschfrist ändern.")
                        } else {
                            Text("\(engine.memberName(group.admin)) verwaltet diese Gruppe. Mitglieder, die du nicht kennst, sind nicht verifiziert, bis du ihre Sicherheitsnummer vergleichst.")
                        }
                    }

                    Section {
                        Picker(selection: Binding(
                            get: { chat.deleteAfterRead ? -1 : (chat.timer ?? 0) },
                            set: { value in
                                Haptics.selection()
                                Task { await engine.setGroupRule(chatId, timer: value > 0 ? value : nil, afterRead: value < 0) }
                            }
                        )) {
                            Text("Aus").tag(TimeInterval(0))
                            ForEach(Timers.chatRule, id: \.self) { Text(Format.duration($0)).tag($0) }
                            Text("Nach dem Lesen").tag(TimeInterval(-1))
                        } label: {
                            Label("Löschfrist", systemImage: "timer")
                        }
                        .disabled(!isAdmin)
                        Toggle(isOn: Binding(
                            get: { chat.isMuted() },
                            set: { on in
                                Haptics.selection()
                                engine.setMuted(chatId, until: on ? .distantFuture : nil)
                            }
                        )) {
                            Label("Stumm", systemImage: "bell.slash")
                        }
                    }
                }

                Section {
                    if !group.hasLeft {
                        Button("Gruppe verlassen", role: .destructive) { confirmLeave = true }
                    }
                    Button("Gruppe löschen", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Verlassen: die anderen erfahren es, der Verlauf bleibt bei dir zum Lesen. Löschen: der Verlauf verschwindet von diesem iPhone.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isAdmin {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Umbenennen") {
                            newName = chat.name
                            renaming = true
                        }
                    }
                }
            }
            .alert("Name der Gruppe", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Abbrechen", role: .cancel) {}
                Button("Sichern") { Task { await engine.renameGroup(chatId, to: newName) } }
            } message: {
                Text("Alle Mitglieder sehen den neuen Namen.")
            }
            .sheet(isPresented: $adding) {
                AddMembersSheet(chatId: chatId)
            }
            .confirmationDialog("Gruppe verlassen?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Verlassen", role: .destructive) {
                    Haptics.destructive()
                    Task { await engine.leaveGroup(chatId) }
                }
            } message: {
                Text("Du bekommst keine Nachrichten mehr aus dieser Gruppe.")
            }
            .confirmationDialog("Gruppe löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Gruppe löschen", role: .destructive) {
                    Haptics.destructive()
                    Task {
                        await engine.deleteChat(chatId)
                        dismiss()
                    }
                }
            } message: {
                if group.hasLeft {
                    Text("Der Verlauf verschwindet von diesem iPhone.")
                } else {
                    Text("Du verlässt die Gruppe, und der Verlauf verschwindet von diesem iPhone.")
                }
            }
            .confirmationDialog(
                "Aus der Gruppe entfernen?",
                isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }),
                titleVisibility: .visible, presenting: memberToRemove
            ) { uid in
                Button("Entfernen", role: .destructive) {
                    Haptics.destructive()
                    Task { await engine.removeMember(chatId, uid) }
                }
            } message: { uid in
                Text("\(engine.memberName(uid)) bekommt keine Nachrichten mehr aus dieser Gruppe.")
            }
        } else {
            ContentUnavailableView("Gruppe gelöscht", systemImage: "person.3")
        }
    }

    private func sortedMembers(_ group: GroupInfo) -> [String] {
        let me = engine.userId
        return group.members.sorted { a, b in
            if a == me { return true }
            if b == me { return false }
            return engine.memberName(a).localizedCaseInsensitiveCompare(engine.memberName(b)) == .orderedAscending
        }
    }

    /// Bekannte Mitglieder führen zur Kontaktinfo (Sicherheitsnummer).
    @ViewBuilder
    private func memberLink(_ uid: String, group: GroupInfo) -> some View {
        if uid != engine.userId, engine.contact(uid) != nil {
            NavigationLink(value: Route.contact(uid)) { memberRow(uid, group: group) }
        } else {
            memberRow(uid, group: group)
        }
    }

    @ViewBuilder
    private func memberRow(_ uid: String, group: GroupInfo) -> some View {
        let me = uid == engine.userId
        let contact = engine.contact(uid)
        HStack(spacing: 12) {
            Avatar(id: uid, name: me ? "User \(uid)" : engine.memberName(uid), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(me ? String(localized: "Du") : engine.memberName(uid))
                if !me, contact == nil {
                    Text("Schlüssel nicht bestätigt, bekommt nichts von dir")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if !me, contact?.introducedBy != nil, contact?.isVerified == false {
                    Text("In der Gruppe kennengelernt, nicht verifiziert")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if group.isAdmin(uid) {
                Text("Verwaltet")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if contact?.isVerified == true {
                Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.tint)
                    .accessibilityLabel("Verifiziert")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Weitere Kontakte in die Gruppe holen (nur die Verwalterin).
private struct AddMembersSheet: View {
    @Environment(MessengerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    let chatId: String
    @State private var selection: Set<String> = []

    var body: some View {
        NavigationStack {
            let members = Set(engine.group(chatId)?.members ?? [])
            let candidates = engine.groupCandidates.filter { !members.contains($0.id) }
            List {
                if candidates.isEmpty {
                    Text("Alle, die du einladen kannst, sind schon dabei.")
                        .foregroundStyle(.secondary)
                } else {
                    ContactPicker(candidates: candidates, selection: $selection, limit: max(0, GroupPolicy.maxMembers - members.count))
                }
            }
            .navigationTitle("Mitglieder hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        let ids = Array(selection)
                        Haptics.success()
                        Task { await engine.addMembers(chatId, ids) }
                        dismiss()
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
    }
}
