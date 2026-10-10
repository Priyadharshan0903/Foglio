import Foundation

public enum JSON: Codable, Equatable {
    case object([String: JSON]), array([JSON]), string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let v = try? value.decode(Bool.self) { self = .bool(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode(Double.self) { self = .number(v) }
        else if let v = try? value.decode([String: JSON].self) { self = .object(v) }
        else { self = .array(try value.decode([JSON].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSON? { if case .object(let v) = self { return v[key] }; return nil }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var number: Double? { if case .number(let v) = self { return v }; return nil }
    public var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    public var object: [String: JSON]? { if case .object(let v) = self { return v }; return nil }
    public var array: [JSON]? { if case .array(let v) = self { return v }; return nil }
    public func data() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    public func text() throws -> String { String(decoding: try data(), as: UTF8.self) }
    public static func decode(_ data: Data) throws -> JSON { try JSONDecoder().decode(JSON.self, from: data) }
}

extension JSON: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(arrayLiteral elements: JSON...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSON)...) { self = .object(Dictionary(uniqueKeysWithValues: elements)) }
}

public struct ConnectorError: Error, LocalizedError {
    public let code: String
    public let message: String
    public init(_ code: String, _ message: String) { self.code = code; self.message = message }
    public var errorDescription: String? { message }
    public var json: JSON { ["error": .string(code), "message": .string(message)] }
}
