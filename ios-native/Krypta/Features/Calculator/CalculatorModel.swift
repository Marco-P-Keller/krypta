import Foundation
import Observation

/// Ein Rechner wie der von iOS: Punkt vor Strich, AC/C, ±, %.
///
/// Er ist Tarnung und muss deshalb *echt* rechnen — wer ihn ausprobiert,
/// darf nichts merken.
@Observable
final class CalculatorModel {
    enum Op: CaseIterable {
        case add, subtract, multiply, divide

        var precedence: Int { self == .add || self == .subtract ? 1 : 2 }

        func apply(_ a: Decimal, _ b: Decimal) -> Decimal? {
            switch self {
            case .add: a + b
            case .subtract: a - b
            case .multiply: a * b
            case .divide: b == 0 ? nil : a / b
            }
        }
    }

    private enum Token { case number(Decimal), op(Op) }

    private var tokens: [Token] = []
    private var entry = ""
    private var justEvaluated = false
    private(set) var display = "0"
    private(set) var isError = false
    /// Der Operator, der gerade gewählt ist (hell hinterlegt wie bei iOS).
    private(set) var activeOp: Op?

    /// "AC" solange nichts getippt wurde, sonst "C".
    var clearLabel: String { entry.isEmpty && !isError ? "AC" : "C" }

    /// Die Ziffern in der Anzeige — damit prüft der Rechner auf die Codes.
    var displayDigits: String { display.filter(\.isNumber) }

    private static let maxDigits = 9

    private var separator: String { Locale.current.decimalSeparator ?? "," }

    // MARK: Eingaben

    func digit(_ d: Int) {
        if isError { allClear() }
        if justEvaluated { tokens = []; justEvaluated = false }
        activeOp = nil
        guard entry.filter(\.isNumber).count < Self.maxDigits else { return }
        entry = entry == "0" ? "\(d)" : entry + "\(d)"
        if entry == "-0" { entry = "-\(d)" }
        display = format(entry: entry)
    }

    func decimalPoint() {
        if isError { allClear() }
        if justEvaluated { tokens = []; justEvaluated = false }
        activeOp = nil
        if entry.isEmpty { entry = "0" }
        guard !entry.contains(".") else { return }
        entry += "."
        display = format(entry: entry)
    }

    func operation(_ op: Op) {
        guard !isError else { return }
        justEvaluated = false
        if !entry.isEmpty {
            tokens.append(.number(Decimal(string: entry) ?? 0))
            entry = ""
        } else if tokens.isEmpty {
            tokens.append(.number(currentValue))
        }
        if case .op? = tokens.last { tokens.removeLast() }
        reduce(minPrecedence: op.precedence)
        tokens.append(.op(op))
        activeOp = op
    }

    func equals() {
        guard !isError else { return }
        if !entry.isEmpty {
            tokens.append(.number(Decimal(string: entry) ?? 0))
            entry = ""
        }
        if case .op? = tokens.last { tokens.removeLast() }
        reduce(minPrecedence: 0)
        activeOp = nil
        justEvaluated = true
    }

    func toggleSign() {
        guard !isError else { return }
        if entry.isEmpty {
            let value = -currentValue
            entry = "\(value)"
            if justEvaluated { tokens = []; justEvaluated = false }
        } else {
            entry = entry.hasPrefix("-") ? String(entry.dropFirst()) : "-" + entry
        }
        display = format(entry: entry)
    }

    func percent() {
        guard !isError else { return }
        let value = (entry.isEmpty ? currentValue : Decimal(string: entry) ?? 0) / 100
        if justEvaluated { tokens = []; justEvaluated = false }
        entry = "\(value)"
        display = format(value)
    }

    func clear() {
        if entry.isEmpty && !isError {
            allClear()
        } else {
            entry = ""
            isError = false
            display = "0"
        }
    }

    func allClear() {
        tokens = []
        entry = ""
        justEvaluated = false
        isError = false
        activeOp = nil
        display = "0"
    }

    // MARK: Rechnen

    private var currentValue: Decimal {
        if case .number(let n)? = tokens.last { return n }
        if tokens.count >= 2, case .number(let n) = tokens[tokens.count - 2] { return n }
        return 0
    }

    /// Fasst von hinten alle Operatoren mit mindestens dieser Stufe zusammen.
    private func reduce(minPrecedence: Int) {
        while tokens.count >= 3,
              case .number(let b) = tokens[tokens.count - 1],
              case .op(let op) = tokens[tokens.count - 2],
              case .number(let a) = tokens[tokens.count - 3],
              op.precedence >= minPrecedence {
            tokens.removeLast(3)
            guard let result = op.apply(a, b) else {
                tokens = []
                isError = true
                display = String(localized: "Fehler")
                return
            }
            tokens.append(.number(result))
        }
        display = format(currentValue)
    }

    // MARK: Anzeige

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
}
