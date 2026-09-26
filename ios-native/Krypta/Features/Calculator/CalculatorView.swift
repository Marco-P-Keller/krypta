import SwiftUI

/// Die Tarnung: sieht aus und rechnet wie der Rechner von iOS.
///
/// Geheimcode + "=" öffnet Krypta, Löschcode + "=" löscht alles.
/// Nichts in der Oberfläche deutet darauf hin.
struct CalculatorView: View {
    @Environment(AppModel.self) private var app
    @State private var calc = CalculatorModel()
    @State private var checking = false
    /// Zählt Tastendrücke — jeder gibt genau ein leises Tippen.
    @State private var presses = 0

    private let spacing: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let key = (geo.size.width - spacing * 5) / 4
            VStack(spacing: spacing) {
                Spacer(minLength: 0)
                Text(calc.display)
                    .font(.system(size: 88, weight: .light))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, spacing + 8)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("calculator.display")
                    .accessibilityLabel(calc.display)

                ForEach(rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(row, id: \.self) { k in
                            button(k, size: key)
                        }
                    }
                }
            }
            .padding(.horizontal, spacing)
            .padding(.bottom, spacing)
        }
        .background(.black)
        // Einmal für den ganzen Rechner, weich und leise wie die Tastatur.
        // (Früher hing es an jeder Taste mit der Anzeige als Auslöser:
        // bei jeder Änderung tippten alle 19 zugleich.)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.4), trigger: presses)
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
    }

    // MARK: Tasten

    private enum Key: Hashable {
        case clear, sign, percent, op(CalculatorModel.Op), digit(Int), point, equals
    }

    private var rows: [[Key]] {
        [
            [.clear, .sign, .percent, .op(.divide)],
            [.digit(7), .digit(8), .digit(9), .op(.multiply)],
            [.digit(4), .digit(5), .digit(6), .op(.subtract)],
            [.digit(1), .digit(2), .digit(3), .op(.add)],
            [.digit(0), .point, .equals],
        ]
    }

    @ViewBuilder
    private func button(_ key: Key, size: CGFloat) -> some View {
        let wide = key == .digit(0)
        Button {
            press(key)
        } label: {
            label(for: key)
                .frame(width: wide ? size * 2 + spacing : size, height: size, alignment: wide ? .leading : .center)
                .padding(.leading, wide ? size * 0.38 : 0)
                .frame(width: wide ? size * 2 + spacing : size, alignment: .leading)
                .background(background(for: key), in: Capsule())
                .foregroundStyle(foreground(for: key))
        }
        .buttonStyle(CalculatorKeyStyle())
        .accessibilityLabel(accessibility(for: key))
    }

    @ViewBuilder
    private func label(for key: Key) -> some View {
        switch key {
        case .clear: Text(calc.clearLabel).font(.system(size: 32, weight: .medium))
        case .sign: Image(systemName: "plus.forwardslash.minus").font(.system(size: 30, weight: .medium))
        case .percent: Image(systemName: "percent").font(.system(size: 30, weight: .medium))
        case .op(let op): Image(systemName: symbol(op)).font(.system(size: 34, weight: .medium))
        case .equals: Image(systemName: "equal").font(.system(size: 34, weight: .medium))
        case .digit(let d): Text("\(d)").font(.system(size: 38, weight: .regular))
        case .point: Text(Locale.current.decimalSeparator ?? ",").font(.system(size: 38, weight: .regular))
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
        case .clear, .sign, .percent: Color(white: 0.65)
        case .op(let op): calc.activeOp == op ? .white : .orange
        case .equals: .orange
        case .digit, .point: Color(white: 0.2)
        }
    }

    private func foreground(for key: Key) -> Color {
        switch key {
        case .clear, .sign, .percent: .black
        case .op(let op): calc.activeOp == op ? .orange : .white
        default: .white
        }
    }

    private func accessibility(for key: Key) -> String {
        switch key {
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
        presses &+= 1
        switch key {
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
    /// Wimpernschlag; gerechnet wird nur, wenn es keiner der Codes war.
    private func equals() {
        guard !checking else { return }
        let digits = calc.displayDigits
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

/// Aufhellen beim Drücken, wie die Tasten von iOS.
private struct CalculatorKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.25 : 0)
            .animation(configuration.isPressed ? nil : .easeOut(duration: 0.35), value: configuration.isPressed)
    }
}
