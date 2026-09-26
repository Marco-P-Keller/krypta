import KryptaCore
import SwiftUI

/// Monogramm im Stil von Kontakte und Nachrichten.
///
/// Die Farbe hängt an der Kennung, nicht am Namen: ein Kontakt hat überall
/// dieselbe Farbe, auch nach dem Umbenennen.
struct Avatar: View {
    let id: String
    let name: String
    var size: CGFloat = 44

    var body: some View {
        Circle()
            .fill(Self.gradient(for: id))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
            .accessibilityHidden(true)
    }

    private var initials: String {
        let words = name.split(separator: " ").filter { !$0.isEmpty }
        // "User abc123" ist der Platzhaltername — dann die Kennung.
        if words.first == "User", words.count == 2 { return String(words[1].prefix(2)).uppercased() }
        return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private static let palette: [Color] = [.blue, .indigo, .purple, .pink, .red, .orange, .teal, .green, .mint, .cyan, .brown]

    static func color(for id: String) -> Color {
        let hash = Primitives.sha256(Data(id.utf8))
        return palette[Int(hash[hash.startIndex]) % palette.count]
    }

    static func gradient(for id: String) -> LinearGradient {
        let c = color(for: id)
        return LinearGradient(colors: [c.opacity(0.75), c], startPoint: .top, endPoint: .bottom)
    }
}

enum Format {
    /// Zeit in der Chatliste: heute Uhrzeit, gestern "Gestern", diese Woche
    /// Wochentag, sonst Datum — wie Nachrichten.
    static func listTime(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(date) { return String(localized: "Gestern") }
        if let days = cal.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }

    /// Trenner im Verlauf: "Heute 14:05", "Gestern 09:12", "Mo., 3. Sep. 18:40".
    static func separator(_ date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(date) { return String(localized: "Heute \(time)") }
        if cal.isDateInYesterday(date) { return String(localized: "Gestern \(time)") }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    /// Frist als Wort: "30 Sekunden", "1 Stunde", "1 Woche".
    static func duration(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.unitsStyle = .full
        f.maximumUnitCount = 1
        f.allowedUnits = [.second, .minute, .hour, .day, .weekOfMonth]
        return f.string(from: seconds) ?? ""
    }

    /// Restzeit kompakt: "4:59", "2 Std.", "3 T."
    static func remaining(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        if s < 3600 { return String(format: "%d:%02d", s / 60, s % 60) }
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 1
        f.allowedUnits = [.hour, .day, .weekOfMonth]
        return f.string(from: TimeInterval(s)) ?? ""
    }
}

/// Die Fristen, die man wählen kann — dieselben Stufen wie die Flutter-Fassung
/// (chat_screen.dart für einzelne Nachrichten, chat_settings_sheet.dart für den Chat).
enum Timers {
    static let perMessage: [TimeInterval] = [30, 300, 1800, 3600, 86_400, 604_800]
    static let chatRule: [TimeInterval] = [300, 1800, 3600, 86_400, 604_800]
}
