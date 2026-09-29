import SwiftUI

/// Die Tarnung: sieht aus und rechnet wie der Rechner von iOS.
///
/// Geheimcode + "=" öffnet Krypta, Löschcode + "=" löscht alles.
/// Nichts in der Oberfläche deutet darauf hin.
struct CalculatorView: View {
    @Environment(AppModel.self) private var app
    @State private var calc = CalculatorModel()
    @State private var checking = false
    @State private var showsHistory = false

    // Maße vom Rechner in iOS 26, auf einem 393 pt breiten iPhone abgemessen.
    private let margin: CGFloat = 16
    private let columnSpacing: CGFloat = 10
    private let rowSpacing: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            let key = (geo.size.width - margin * 2 - columnSpacing * 3) / 4
            VStack(spacing: 0) {
                topBar
                    // Mit Dynamic Island sitzt die Leiste ein Stück im Statusbereich.
                    .padding(.top, geo.safeAreaInsets.top > 24 ? -7 : 6)
                Spacer(minLength: 0)
                screen
                    .padding(.bottom, 6)
                VStack(spacing: rowSpacing) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: columnSpacing) {
                            ForEach(row, id: \.self) { k in
                                button(k, size: key)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, margin)
            .padding(.bottom, 23)
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .sheet(isPresented: $showsHistory) {
            CalculatorHistory(calc: calc)
        }
    }

    // MARK: Oben

    private var topBar: some View {
        HStack {
            Button {
                showsHistory = true
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: 22, weight: .medium))
                    .modifier(RoundBarButton())
            }
            .accessibilityLabel(String(localized: "Verlauf"))

            Spacer()

            Menu {
                Picker(selection: .constant(0)) {
                    Text(String(localized: "Einfach")).tag(0)
                } label: {
                    EmptyView()
                }
            } label: {
                CalculatorGlyph()
                    .fill(style: FillStyle(eoFill: true))
                    .frame(width: 16, height: 23.3)
                    .modifier(RoundBarButton())
            }
            .accessibilityLabel(String(localized: "Rechnerart"))
        }
        .buttonStyle(CalculatorKeyStyle())
        .foregroundStyle(.white)
    }

    /// Oben klein die letzte Rechnung, darunter groß Eingabe oder Ergebnis.
    private var screen: some View {
        VStack(alignment: .trailing, spacing: 4.5) {
            Text(calc.expression.isEmpty ? " " : calc.expression)
                .font(.system(size: 28))
                .foregroundStyle(Color(white: 0.63))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(calc.display)
                .font(.system(size: 65))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .contentTransition(.numericText())
                .accessibilityIdentifier("calculator.display")
                .accessibilityLabel(calc.display)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: Tasten

    private enum Key: Hashable {
        case backspace, clear, sign, percent, op(CalculatorModel.Op), digit(Int), point, equals
    }

    private var rows: [[Key]] {
        [
            [.backspace, .clear, .percent, .op(.divide)],
            [.digit(7), .digit(8), .digit(9), .op(.multiply)],
            [.digit(4), .digit(5), .digit(6), .op(.subtract)],
            [.digit(1), .digit(2), .digit(3), .op(.add)],
            [.sign, .digit(0), .point, .equals],
        ]
    }

    @ViewBuilder
    private func button(_ key: Key, size: CGFloat) -> some View {
        Button {
            press(key)
        } label: {
            label(for: key)
                .frame(width: size, height: size)
                .background(background(for: key), in: Circle())
                .overlay(GlassEdge(height: size))
                .foregroundStyle(.white)
        }
        .buttonStyle(CalculatorKeyStyle())
        .accessibilityLabel(accessibility(for: key))
    }

    @ViewBuilder
    private func label(for key: Key) -> some View {
        switch key {
        case .backspace: Image(systemName: "delete.left").font(.system(size: 33))
        case .clear: Text(calc.clearLabel).font(.system(size: 35))
        case .sign: Image(systemName: "plus.forwardslash.minus").font(.system(size: 34))
        case .percent: Image(systemName: "percent").font(.system(size: 34))
        case .op(let op): Image(systemName: symbol(op)).font(.system(size: 34))
        case .equals: Image(systemName: "equal").font(.system(size: 34))
        case .digit(let d): Text("\(d)").font(.system(size: 35))
        case .point: Text(Locale.current.decimalSeparator ?? ",").font(.system(size: 35))
        }
    }

    private func symbol(_ op: CalculatorModel.Op) -> String {
        switch op {
        case .add: "plus"
        case .subtract: "minus"
        case .multiply: "multiply"
        case .divide: "divide"
        }
    }

    private func background(for key: Key) -> Color {
        switch key {
        case .backspace, .clear, .percent: Color(white: 0.38)
        case .op, .equals: Color(red: 1, green: 0.573, blue: 0)
        case .digit, .sign, .point: Color(white: 0.208)
        }
    }

    private func accessibility(for key: Key) -> String {
        switch key {
        case .backspace: String(localized: "Rücktaste")
        case .clear: calc.clearLabel == "AC" ? String(localized: "Alles löschen") : String(localized: "Löschen")
        case .sign: String(localized: "Vorzeichen")
        case .percent: String(localized: "Prozent")
        case .op(.add): String(localized: "Plus")
        case .op(.subtract): String(localized: "Minus")
        case .op(.multiply): String(localized: "Mal")
        case .op(.divide): String(localized: "Geteilt durch")
        case .equals: String(localized: "Ist gleich")
        case .point: String(localized: "Komma")
        case .digit(let d): "\(d)"
        }
    }

    // MARK: Aktionen

    private func press(_ key: Key) {
        switch key {
        case .backspace: calc.backspace()
        case .clear: calc.clear()
        case .sign: calc.toggleSign()
        case .percent: calc.percent()
        case .op(let op): calc.operation(op)
        case .digit(let d): calc.digit(d)
        case .point: calc.decimalPoint()
        case .equals: equals()
        }
    }

    /// Erst prüfen, dann rechnen. Die Prüfung ist Argon2id und dauert einen
    /// Wimpernschlag; gerechnet wird nur, wenn es keiner der Codes war —
    /// deshalb landet ein Code auch nie im Verlauf.
    private func equals() {
        guard !checking else { return }
        let digits = calc.codeDigits
        checking = true
        Task {
            let match = await AccessCodes.check(digits)
            checking = false
            switch match {
            case .secret:
                calc.allClear()
                await app.secretCodeEntered()
            case .delete:
                calc.allClear()
                await app.emergencyWipe()
            case .none:
                withAnimation(.snappy) { calc.equals() }
            }
        }
    }
}

/// Der Verlauf wie beim Rechner von iOS; ein Tipp holt das Ergebnis zurück.
private struct CalculatorHistory: View {
    let calc: CalculatorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(calc.history) { item in
                Button {
                    calc.recall(item)
                    dismiss()
                } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(item.expression)
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Text(item.result)
                            .font(.title)
                            .foregroundStyle(.primary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
            .listStyle(.plain)
            .overlay {
                if calc.history.isEmpty {
                    ContentUnavailableView(String(localized: "Kein Verlauf"), systemImage: "clock")
                }
            }
            .navigationTitle(String(localized: "Verlauf"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Löschen")) { calc.clearHistory() }
                        .disabled(calc.history.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Fertig")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Die Kanten der Tasten wie bei Liquid Glass: oben und unten ein feiner
/// heller Saum mit weichem Schein nach innen, an den Seiten fast nichts.
private struct GlassEdge: View {
    let height: CGFloat

    /// Helligkeit nach innen, in pt vom Rand (abgemessen am Original).
    private static let glow: [(CGFloat, Double)] = [
        (0, 0.12), (0.4, 0.09), (0.8, 0.055), (1.2, 0.04), (2, 0.028), (3, 0.016), (4.5, 0.005), (6, 0),
    ]

    private static let rim = LinearGradient(
        stops: [
            .init(color: .white.opacity(0.22), location: 0),
            .init(color: .white.opacity(0.03), location: 0.22),
            .init(color: .white.opacity(0.03), location: 0.78),
            .init(color: .white.opacity(0.22), location: 1),
        ],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        let top = Self.glow.map { Gradient.Stop(color: .white.opacity($0.1), location: $0.0 / height) }
        let bottom = Self.glow.reversed().map { Gradient.Stop(color: .white.opacity($0.1), location: 1 - $0.0 / height) }
        ZStack {
            Circle().fill(LinearGradient(stops: top + bottom, startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(Self.rim, lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// Die runden Knöpfe oben links und rechts.
private struct RoundBarButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: 44, height: 44)
            .background(Color(white: 0.13), in: Circle())
            .overlay(GlassEdge(height: 44))
            .contentShape(Circle())
    }
}

/// Das Rechner-Symbol oben rechts — bei Apple kein öffentliches SF Symbol,
/// deshalb nachgezeichnet: Gehäuse, Anzeige, drei mal drei Tasten.
private struct CalculatorGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let u = rect.width / 16
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x * u, y: rect.minY + y * u, width: w * u, height: h * u)
        }
        var path = Path(roundedRect: rect, cornerRadius: 3 * u)
        path.addRoundedRect(in: r(2.5, 2.5, 11, 4.7), cornerSize: CGSize(width: u, height: u))
        for row in 0..<3 {
            for column in 0..<3 {
                let x = 3.6 + 4.4 * CGFloat(column), y = 10.6 + 4.25 * CGFloat(row)
                path.addEllipse(in: r(x - 1.25, y - 1.25, 2.5, 2.5))
            }
        }
        return path
    }
}

/// Aufhellen beim Drücken, wie die Tasten von iOS, und ein leichtes Tippen.
///
/// Das Tippen kommt beim Herunterdrücken wie bei der Tastatur, nicht erst beim
/// Loslassen, und nur von der gedrückten Taste. (Weich mit 0,4 nach dem
/// Loslassen war kaum zu spüren; an der Anzeige als Auslöser tippten einst
/// alle 19 Tasten zugleich.)
private struct CalculatorKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.25 : 0)
            .animation(configuration.isPressed ? nil : .easeOut(duration: 0.35), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}
