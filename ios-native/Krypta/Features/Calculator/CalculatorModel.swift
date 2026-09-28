import Foundation
import Observation

/// Ein Rechner wie der von iOS: Punkt vor Strich, Rücktaste, AC/C, ±, %,
/// und der ganze Ausdruck steht beim Tippen in der Anzeige.
///
/// Er ist Tarnung und muss deshalb *echt* rechnen — wer ihn ausprobiert,
/// darf nichts merken.
@Observable
final class CalculatorModel {
    enum Op: CaseIterable {
        case add, subtract, multiply, divide

        var symbol: String {
            switch self {
            case .add: "+"
            case .subtract: "−"
            case .multiply: "×"
            case .divide: "÷"
            }
        }
    }

    /// Eine fertige Zahl im Ausdruck. `raw` ist, was getippt wurde
    /// ("2.50"), damit die Anzeige es so zeigt und die Rücktaste es
    /// zurückholen kann; bei Ergebnissen fehlt es.
    private struct Number {
        var value: Decimal
        var raw: String?
        var percent = false
    }

    private enum Token { case number(Number), op(Op) }

    struct HistoryEntry: Identifiable {
        let id = UUID()
        let expression: String
        let result: String
        fileprivate let value: Decimal
    }

    /// Endet auf einen Operator, auf eine Prozentzahl oder ist nach "="
    /// genau das Ergebnis. Die Zahl, die gerade getippt wird, steht in `entry`.
    private var tokens: [Token] = []
    private var entry = ""
    private var showingResult = false
    /// Die Rechnung über dem Ergebnis, klein und grau — nur nach "=".
    private(set) var expression = ""
    private(set) var isError = false
    /// Nur im Speicher: mit der Tarnung verschwindet auch der Verlauf.
    private(set) var history: [HistoryEntry] = []

    /// Die große Zeile: beim Tippen der Ausdruck, nach "=" das Ergebnis.
    var display: String {
        if isError { return String(localized: "Fehler") }
        let text = tokens.map(render).joined() + (entry.isEmpty ? "" : format(entry: entry))
        return text.isEmpty ? "0" : text
    }

    /// "AC" solange nichts getippt wurde, sonst "C".
    var clearLabel: String { entry.isEmpty && !isError ? "AC" : "C" }

    /// Die Ziffern der zuletzt getippten Zahl — damit prüft der Rechner auf
    /// die Codes, so wie früher die Ziffern in der Anzeige.
    var codeDigits: String {
        if !entry.isEmpty { return entry.filter(\.isNumber) }
        if case .number(let n)? = tokens.last { return render(n).filter(\.isNumber) }
        return ""
    }

    private static let maxDigits = 9

    private var separator: String { Locale.current.decimalSeparator ?? "," }

    // MARK: Eingaben

    func digit(_ d: Int) {
        startOverIfNeeded()
        guard !endsWithPercent, entry.filter(\.isNumber).count < Self.maxDigits else { return }
        switch entry {
        case "0": entry = "\(d)"
        case "-0": entry = "-\(d)"
        default: entry += "\(d)"
        }
    }

    func decimalPoint() {
        startOverIfNeeded()
        guard !endsWithPercent, !entry.contains(".") else { return }
        entry = (entry.isEmpty ? "0" : entry) + "."
    }

    func operation(_ op: Op) {
        guard !isError else { return }
        continueFromResult()
        commitEntry()
        switch tokens.last {
        case .op?: tokens.removeLast()
        case nil: tokens.append(.number(Number(value: 0)))
        case .number?: break
        }
        tokens.append(.op(op))
    }

    func equals() {
        guard !isError, !showingResult else { return }
        commitEntry()
        if case .op? = tokens.last { tokens.removeLast() }
        guard !tokens.isEmpty else { return }
        let text = tokens.map(render).joined()
        let isCalculation = tokens.count > 1 || endsWithPercent
        guard let result = Self.evaluate(tokens), !result.isNaN else {
            tokens = []
            expression = text
            isError = true
            return
        }
        tokens = [.number(Number(value: result))]
        showingResult = true
        if isCalculation {
            expression = text
            history.insert(HistoryEntry(expression: text, result: format(result), value: result), at: 0)
        }
    }

    func toggleSign() {
        guard !isError else { return }
        if showingResult, case .number(var n)? = tokens.first {
            n.value = -n.value
            tokens = [.number(n)]
            expression = ""
        } else if !entry.isEmpty {
            entry = entry.hasPrefix("-") ? String(entry.dropFirst()) : "-" + entry
        } else if case .number(var n)? = tokens.last {
            n.value = -n.value
            n.raw = n.raw.map { $0.hasPrefix("-") ? String($0.dropFirst()) : "-" + $0 }
            tokens[tokens.count - 1] = .number(n)
        } else {
            entry = "-0"
        }
    }

    /// Wie bei iOS: "200+10%" ist 220, sonst heißt 10% einfach 0,1.
    func percent() {
        guard !isError else { return }
        if showingResult, case .number(var n)? = tokens.first {
            showingResult = false
            expression = ""
            n.percent = true
            tokens = [.number(n)]
        } else if !entry.isEmpty {
            tokens.append(.number(Number(value: Decimal(string: entry) ?? 0, raw: entry, percent: true)))
            entry = ""
        }
    }

    func backspace() {
        if isError { allClear(); return }
        guard !showingResult else { return }
        if !entry.isEmpty {
            entry.removeLast()
            if entry == "-" { entry = "" }
            return
        }
        switch tokens.popLast() {
        case .op?:
            // Die Zahl davor wird wieder zur Eingabe.
            if case .number(let n)? = tokens.last, !n.percent {
                tokens.removeLast()
                entry = n.raw ?? plain(n.value)
            }
        case .number(let n)?:
            entry = n.raw ?? plain(n.value)
        case nil:
            break
        }
    }

    func clear() {
        if entry.isEmpty || isError {
            allClear()
        } else {
            entry = ""
        }
    }

    func allClear() {
        tokens = []
        entry = ""
        showingResult = false
        isError = false
        expression = ""
    }

    /// Holt ein Ergebnis aus dem Verlauf zurück, zum Weiterrechnen.
    func recall(_ item: HistoryEntry) {
        allClear()
        tokens = [.number(Number(value: item.value))]
        showingResult = true
        expression = item.expression
    }

    func clearHistory() { history = [] }

    // MARK: Zustand

    private var endsWithPercent: Bool {
        if case .number(let n)? = tokens.last, n.percent { return true }
        return false
    }

    /// Eine neue Ziffer nach "=" oder einem Fehler beginnt eine neue Rechnung.
    private func startOverIfNeeded() {
        if isError || showingResult { allClear() }
    }

    /// Ein Operator nach "=" rechnet mit dem Ergebnis weiter.
    private func continueFromResult() {
        guard showingResult else { return }
        showingResult = false
        expression = ""
    }

    private func commitEntry() {
        guard !entry.isEmpty else { return }
        tokens.append(.number(Number(value: Decimal(string: entry) ?? 0, raw: entry)))
        entry = ""
    }

    // MARK: Rechnen

    private static func evaluate(_ tokens: [Token]) -> Decimal? {
        var values: [Decimal] = []
        var ops: [Op] = []
        for token in tokens {
            switch token {
            case .op(let op):
                ops.append(op)
            case .number(let n):
                var value = n.value
                if n.percent {
                    // a ± b% ist b Prozent von a; sonst nur geteilt durch 100.
                    if let op = ops.last, op == .add || op == .subtract,
                       let base = combine(values, Array(ops.dropLast())) {
                        value = base * value / 100
                    } else {
                        value /= 100
                    }
                }
                values.append(value)
            }
        }
        return combine(values, ops)
    }

    /// Punkt vor Strich. `ops[i]` steht zwischen `values[i]` und `values[i+1]`.
    private static func combine(_ values: [Decimal], _ ops: [Op]) -> Decimal? {
        guard var terms = values.first.map({ [$0] }) else { return nil }
        var signs: [Op] = []
        for (op, value) in zip(ops, values.dropFirst()) {
            switch op {
            case .multiply:
                terms.append(terms.removeLast() * value)
            case .divide:
                guard value != 0 else { return nil }
                terms.append(terms.removeLast() / value)
            case .add, .subtract:
                terms.append(value)
                signs.append(op)
            }
        }
        var result = terms[0]
        for (op, value) in zip(signs, terms.dropFirst()) {
            result = op == .add ? result + value : result - value
        }
        return result
    }

    // MARK: Anzeige

    private func render(_ token: Token) -> String {
        switch token {
        case .op(let op): op.symbol
        case .number(let n): render(n)
        }
    }

    private func render(_ n: Number) -> String {
        (n.raw.map(format(entry:)) ?? format(n.value)) + (n.percent ? "%" : "")
    }

    private func format(entry: String) -> String {
        let negative = entry.hasPrefix("-")
        let body = negative ? String(entry.dropFirst()) : entry
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        let integer = Decimal(string: String(parts.first ?? "0")) ?? 0
        var text = grouped(integer)
        if parts.count > 1 { text += separator + parts[1] }
        return (negative ? "-" : "") + text
    }

    private func grouped(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: value as NSDecimalNumber) ?? "0"
    }

    private func format(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumSignificantDigits = Self.maxDigits
        f.usesSignificantDigits = true
        let magnitude = abs((value as NSDecimalNumber).doubleValue)
        if magnitude != 0 && (magnitude >= 1e9 || magnitude < 1e-8) {
            f.numberStyle = .scientific
            f.exponentSymbol = "e"
            f.maximumSignificantDigits = 6
        }
        return f.string(from: value as NSDecimalNumber) ?? "0"
    }

    /// Eine Zahl so, wie man sie tippen würde ("-0.25"), zum Weiterbearbeiten.
    private func plain(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.usesSignificantDigits = true
        f.maximumSignificantDigits = Self.maxDigits
        return f.string(from: value as NSDecimalNumber) ?? "0"
    }
}
