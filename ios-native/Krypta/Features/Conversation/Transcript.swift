import KryptaMessenger
import SwiftUI

/// Der Verlauf als Zeilen: Zeittrenner, Blasen (gruppiert), Hinweise und
/// der Status unter der letzten eigenen Nachricht — wie in Nachrichten.
struct TranscriptItem: Identifiable {
    enum Kind {
        case separator(Date)
        case message(Message, BubblePosition)
        case event(Message)
        case status(MessageStatus)
    }

    let id: String
    let kind: Kind

    /// Nach einer Stunde Pause ein neuer Zeittrenner; nach fünf Minuten oder
    /// einem Absenderwechsel eine neue Gruppe.
    static func build(_ messages: [Message], me: String) -> [TranscriptItem] {
        var items: [TranscriptItem] = []
        let lastMine = messages.last { $0.senderId == me && !$0.isSystemEvent }

        for (i, m) in messages.enumerated() {
            let prev = i > 0 ? messages[i - 1] : nil
            let next = i + 1 < messages.count ? messages[i + 1] : nil

            if prev == nil || m.timestamp.timeIntervalSince(prev!.timestamp) > 3600 {
                items.append(.init(id: "sep-\(m.id)", kind: .separator(m.timestamp)))
            }
            if m.isSystemEvent {
                items.append(.init(id: m.id, kind: .event(m)))
                continue
            }
            let first = prev.map { !sameGroup($0, m) } ?? true
            let last = next.map { !sameGroup(m, $0) } ?? true
            items.append(.init(id: m.id, kind: .message(m, BubblePosition(isFirst: first, isLast: last))))

            if m.id == lastMine?.id || (m.senderId == me && m.status == .failed) {
                items.append(.init(id: "status-\(m.id)", kind: .status(m.status)))
            }
        }
        return items
    }

    private static func sameGroup(_ a: Message, _ b: Message) -> Bool {
        !a.isSystemEvent && !b.isSystemEvent && a.senderId == b.senderId && b.timestamp.timeIntervalSince(a.timestamp) < 300
    }
}

struct BubblePosition: Equatable {
    let isFirst: Bool
    let isLast: Bool
}

/// Eine Nachricht mit Blase, Symbolen und ggf. Ablaufzeit.
struct MessageRow: View {
    let message: Message
    let position: BubblePosition
    let mine: Bool
    let deadline: Date?
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if mine { Spacer(minLength: 48) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                bubble
                    .onTapGesture(perform: onTap)
                if let deadline {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Label(Format.remaining(deadline.timeIntervalSince(context.date)), systemImage: "timer")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel("Verschwindet bald")
                } else if mine && message.isPasswordProtected {
                    Label(message.passwordUnlocked ? "Entsperrt" : "Mit Passwort geschützt", systemImage: message.passwordUnlocked ? "lock.open" : "lock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if message.burnAfterRead || (message.oneTime && mine) {
                    Label(message.oneTime ? "Einmal ansehen" : "Nach dem Ansehen", systemImage: message.oneTime ? "eye" : "flame")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if mine && message.status == .failed {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
                    .onTapGesture(perform: onTap)
                    .accessibilityLabel("Nicht zugestellt. Tippen für Optionen.")
            }
            if !mine { Spacer(minLength: 48) }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        Group {
            if message.isPasswordProtected && !message.passwordUnlocked && !mine {
                special(symbol: "lock.fill", title: "Geschützte Nachricht", subtitle: "Tippen zum Entsperren")
            } else if message.oneTime && !mine {
                special(symbol: "eye.fill", title: "Einmal ansehen", subtitle: "Tippen zum Öffnen")
            } else if message.oneTime && mine {
                special(symbol: "eye", title: "Einmalige Nachricht", subtitle: "Du behältst keine Kopie")
            } else {
                Text(message.text ?? "")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .foregroundStyle(mine ? .white : .primary)
        .background(mine ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color(.systemGray5)), in: shape)
        .opacity(message.status == .sending ? 0.7 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(tapHint == nil ? [] : .isButton)
        .accessibilityHint(tapHint.map { Text($0) } ?? Text(""))
    }

    /// Was ein Tippen auf die Blase tut — `nil`, wenn nichts.
    private var tapHint: LocalizedStringKey? {
        if mine && message.status == .failed { return "Optionen zum erneuten Senden" }
        if !mine && message.isPasswordProtected && !message.passwordUnlocked { return "Mit Passwort entsperren" }
        if !mine && message.oneTime { return "Öffnet die Nachricht. Danach ist sie weg." }
        return nil
    }

    private func special(symbol: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).opacity(0.8)
            }
        }
    }

    /// Auf der Absenderseite werden die Ecken spitz, wo die Blase an die
    /// nächste derselben Gruppe anschließt.
    private var shape: UnevenRoundedRectangle {
        let big: CGFloat = 18, small: CGFloat = 6
        let joinTop = !position.isFirst, joinBottom = !position.isLast
        return UnevenRoundedRectangle(
            topLeadingRadius: !mine && joinTop ? small : big,
            bottomLeadingRadius: !mine && joinBottom ? small : big,
            bottomTrailingRadius: mine && joinBottom ? small : big,
            topTrailingRadius: mine && joinTop ? small : big,
            style: .continuous
        )
    }

    private var accessibility: String {
        let who = mine ? String(localized: "Du") : String(localized: "Kontakt")
        if message.isPasswordProtected && !message.passwordUnlocked { return "\(who): " + String(localized: "Geschützte Nachricht") }
        if message.oneTime { return "\(who): " + String(localized: "Einmal ansehen") }
        return "\(who): \(message.text ?? "")"
    }
}

/// Wie eine Nachricht gehen soll.
enum ComposeOption: Equatable {
    case chatRule
    case timer(TimeInterval)
    case afterRead
    case oneTime
    case password
}

/// Die Eingabeleiste: Optionen, Textfeld, Senden.
struct Composer: View {
    @Binding var draft: String
    @Binding var option: ComposeOption
    var focused: FocusState<Bool>.Binding
    let chatTimer: TimeInterval?
    let chatAfterRead: Bool
    let askPassword: () -> Void
    let send: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if let chip {
                HStack {
                    Label(chip, systemImage: chipSymbol)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.tint.opacity(0.12), in: Capsule())
                        .foregroundStyle(.tint)
                    if option != .chatRule {
                        Button { option = .chatRule } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .accessibilityLabel("Option entfernen")
                    }
                    Spacer()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Menu {
                        ForEach(Timers.perMessage, id: \.self) { s in
                            Button(Format.duration(s)) { option = .timer(s) }
                        }
                    } label: { Label("Löschfrist", systemImage: "timer") }
                    Button { option = .afterRead } label: { Label("Nach dem Ansehen löschen", systemImage: "flame") }
                    Button { option = .oneTime } label: { Label("Einmal ansehen", systemImage: "eye") }
                    Button(action: askPassword) { Label("Mit Passwort schützen", systemImage: "lock") }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(Color(.systemGray5), in: Circle())
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Nachrichtenoptionen")

                HStack(alignment: .bottom, spacing: 4) {
                    TextField("Nachricht", text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .focused(focused)
                        .padding(.leading, 12)
                        .padding(.vertical, 7)
                        .accessibilityIdentifier("composer.field")
                    if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: send) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                        }
                        .padding(.trailing, 3)
                        .padding(.bottom, 3)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Senden")
                        .accessibilityIdentifier("composer.send")
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(.systemGray4)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .animation(.snappy(duration: 0.2), value: draft.isEmpty)
        .animation(.snappy(duration: 0.2), value: option)
        .sensoryFeedback(.selection, trigger: option)
    }

    private var chip: String? {
        switch option {
        case .chatRule:
            if chatAfterRead { return String(localized: "Chat: nach dem Lesen löschen") }
            return chatTimer.map { String(localized: "Chat: löschen nach \(Format.duration($0))") }
        case .timer(let s): return String(localized: "Löschen nach \(Format.duration(s))")
        case .afterRead: return String(localized: "Nach dem Ansehen löschen")
        case .oneTime: return String(localized: "Einmal ansehen")
        case .password: return String(localized: "Mit Passwort geschützt")
        }
    }

    private var chipSymbol: String {
        switch option {
        case .chatRule, .timer: "timer"
        case .afterRead: "flame"
        case .oneTime: "eye"
        case .password: "lock.fill"
        }
    }
}

/// Texte der Systemhinweise im Verlauf.
enum SystemEventText {
    /// Ganze Sätze je Fall — zusammengesetzte Bruchstücke ließen sich nicht
    /// in jede Sprache übersetzen.
    static func text(_ kind: SystemEventKind, mine: Bool, timer: TimeInterval?, name: String = "") -> String {
        let who = name.isEmpty ? String(localized: "Dein Kontakt") : name
        switch kind {
        case .screenshot:
            return mine ? String(localized: "Du hast ein Bildschirmfoto gemacht.") : String(localized: "\(who) hat ein Bildschirmfoto gemacht.")
        case .screenRecording:
            return mine ? String(localized: "Du hast eine Bildschirmaufnahme gestartet.") : String(localized: "\(who) hat eine Bildschirmaufnahme gestartet.")
        case .accountDeleted:
            return String(localized: "Dieses Konto wurde gelöscht.")
        case .selfDestructAfterRead:
            return mine ? String(localized: "Du hast festgelegt, dass Nachrichten nach dem Lesen gelöscht werden.")
                : String(localized: "\(who) hat festgelegt, dass Nachrichten nach dem Lesen gelöscht werden.")
        case .selfDestructChanged:
            if let timer {
                let d = Format.duration(timer)
                return mine ? String(localized: "Du hast die Löschfrist auf \(d) gesetzt.") : String(localized: "\(who) hat die Löschfrist auf \(d) gesetzt.")
            }
            return mine ? String(localized: "Du hast die Löschfrist ausgeschaltet.") : String(localized: "\(who) hat die Löschfrist ausgeschaltet.")
        }
    }
}
