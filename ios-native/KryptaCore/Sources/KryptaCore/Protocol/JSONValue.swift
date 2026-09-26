import Foundation

/// Ein JSON-Wert mit den Typen, die Dart unterscheidet.
///
/// Wichtig ist der Unterschied zwischen Ganzzahl und Wahrheitswert: der
/// Empfänger in Dart prüft `innerPayload['_rq'] == 1` und
/// `innerPayload['_sdc'] == true`. Ein `true`, wo `1` erwartet wird, fällt
/// dort still durch. Deshalb kein `[String: Any]` im Protokoll.
public enum JSONValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public var stringValue: String? { if case .string(let s) = self { s } else { nil } }
    public var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var objectValue: [String: JSONValue]? { if case .object(let o) = self { o } else { nil } }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { a } else { nil } }

    /// Ganzzahl wie Darts `as int?`: nur echte Ganzzahlen. Firestore liefert
    /// Zahlen manchmal als Double mit ganzem Wert, die lassen wir gelten.
    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d) where d.rounded() == d && abs(d) < 9.0e15: return Int(d)
        default: return nil
        }
    }

    // MARK: Brücke zu Foundation (JSONSerialization, Firestore)

    /// Aus einem Foundation-Wert. `NSNumber` wird nach seinem inneren Typ
    /// unterschieden, damit ein `true` kein `1` wird.
    public init(any value: Any?) {
        switch value {
        case nil, is NSNull:
            self = .null
        case let s as String:
            self = .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else if CFNumberIsFloatType(n) {
                self = .double(n.doubleValue)
            } else {
                self = .int(n.intValue)
            }
        case let a as [Any]:
            self = .array(a.map { JSONValue(any: $0) })
        case let o as [String: Any]:
            self = .object(o.mapValues { JSONValue(any: $0) })
        default:
            self = .null
        }
    }

    public var anyValue: Any {
        switch self {
        case .string(let s): s
        case .int(let i): i
        case .double(let d): d
        case .bool(let b): b
        case .array(let a): a.map(\.anyValue)
        case .object(let o): o.mapValues(\.anyValue)
        case .null: NSNull()
        }
    }
}

public typealias JSONObject = [String: JSONValue]

public extension Dictionary where Key == String, Value == JSONValue {
    /// Kompakter JSON-Text, wie Darts `jsonEncode`.
    func jsonString() throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: mapValues(\.anyValue),
            options: [.withoutEscapingSlashes]
        )
        return String(decoding: data, as: UTF8.self)
    }

    static func parse(_ text: String) throws -> JSONObject {
        guard let obj = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw CryptoError.malformed("json")
        }
        return obj.mapValues { JSONValue(any: $0) }
    }

    var anyDictionary: [String: Any] { mapValues(\.anyValue) }

    init(any dict: [String: Any]) {
        self = dict.mapValues { JSONValue(any: $0) }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
