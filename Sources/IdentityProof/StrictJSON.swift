import Foundation
import CryptoKit

public struct IdentityFailure: Error {
    public let code: String
    public let fields: [String]
    public let message: String
    public init(code: String, fields: [String] = [], message: String = "Operation refused.") {
        self.code = code; self.fields = fields; self.message = message
    }
}

public enum JSONValue: Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null,.null): return true
        case (.bool(let a),.bool(let b)): return a == b
        case (.number(let a),.number(let b)): return a == b
        case (.string(let a),.string(let b)): return a.utf8.elementsEqual(b.utf8)
        case (.array(let a),.array(let b)): return a == b
        case (.object(let a),.object(let b)):
            guard a.count == b.count else { return false }
            return a.allSatisfy { key, value in
                guard let match = b.first(where: { $0.key.utf8.elementsEqual(key.utf8) }) else { return false }
                return value == match.value
            }
        default: return false
        }
    }
    public var object: [String: JSONValue]? { if case .object(let x) = self { return x }; return nil }
    public var array: [JSONValue]? { if case .array(let x) = self { return x }; return nil }
    public var string: String? { if case .string(let x) = self { return x }; return nil }
    public var number: Double? { if case .number(let x) = self { return x }; return nil }
    public var bool: Bool? { if case .bool(let x) = self { return x }; return nil }
    public subscript(_ key: String) -> JSONValue? { object?[key] }
    public init(any: Any) throws {
        if any is NSNull { self = .null }
        else if let x = any as? [String: Any] { self = .object(try x.mapValues { try JSONValue(any: $0) }) }
        else if let x = any as? [Any] { self = .array(try x.map { try JSONValue(any: $0) }) }
        else if let x = any as? String { self = .string(x) }
        else if let x = any as? NSNumber {
            if CFGetTypeID(x) == CFBooleanGetTypeID() { self = .bool(x.boolValue) }
            else { guard x.doubleValue.isFinite else { throw IdentityFailure(code: "INVALID_REQUEST") }; self = .number(x.doubleValue) }
        } else { throw IdentityFailure(code: "INVALID_REQUEST") }
    }
    public static func parse(_ data: Data, maximumBytes: Int = 262_144, maximumDepth: Int = 24) throws -> JSONValue {
        guard data.count <= maximumBytes else { throw IdentityFailure(code: "REQUEST_TOO_LARGE") }
        guard String(data: data, encoding: .utf8) != nil else { throw IdentityFailure(code: "INVALID_REQUEST") }
        var parser = StrictJSONParser(bytes: Array(data), maximumDepth: maximumDepth)
        let value = try parser.value(depth: 0); parser.whitespace()
        guard parser.offset == parser.bytes.count else { throw IdentityFailure(code: "INVALID_REQUEST") }
        return value
    }
    public func canonicalData() -> Data { Data(canonicalString.utf8) }
    public var canonicalString: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .string(let s):
            var out = "\""
            for c in s.unicodeScalars {
                switch c.value {
                case 34: out += "\\\""
                case 92: out += "\\\\"
                case 8: out += "\\b"
                case 9: out += "\\t"
                case 10: out += "\\n"
                case 12: out += "\\f"
                case 13: out += "\\r"
                case 0...31: out += String(format: "\\u%04x", c.value)
                default: out.unicodeScalars.append(c)
                }
            }; return out + "\""
        case .number(let n):
            precondition(n.isFinite)
            if n == 0 { return "0" }
            // JCS uses ECMAScript's shortest round-trip decimal. Swift's shortest
            // representation differs only in exponent/decimal placement here.
            let raw = String(n).lowercased(); let parts = raw.split(separator: "e")
            var mantissa = String(parts[0]); if mantissa.hasSuffix(".0") { mantissa.removeLast(2) }
            guard parts.count == 2, let exponent = Int(parts[1]) else { return mantissa }
            let negative = mantissa.hasPrefix("-"); if negative { mantissa.removeFirst() }
            let point = mantissa.firstIndex(of: ".").map { mantissa.distance(from: mantissa.startIndex, to: $0) } ?? mantissa.count
            let digits = mantissa.replacingOccurrences(of: ".", with: "")
            let decimal = point + exponent
            let sign = negative ? "-" : ""
            if exponent >= -6 && exponent < 21 {
                if decimal <= 0 { return sign + "0." + String(repeating: "0", count: -decimal) + digits }
                if decimal >= digits.count { return sign + digits + String(repeating: "0", count: decimal - digits.count) }
                let at = digits.index(digits.startIndex, offsetBy: decimal)
                return sign + digits[..<at] + "." + digits[at...]
            }
            return sign + mantissa + "e" + (exponent >= 0 ? "+" : "") + String(exponent)
        case .array(let a): return "[" + a.map(\.canonicalString).joined(separator: ",") + "]"
        case .object(let o):
            let keys = o.keys.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
            return "{" + keys.map { JSONValue.string($0).canonicalString + ":" + o[$0]!.canonicalString }.joined(separator: ",") + "}"
        }
    }
    public static func sha256(_ data: Data, domain: String = "") -> String {
        var bytes = Data(domain.utf8); bytes.append(data)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

private struct StrictJSONParser {
    let bytes: [UInt8]; let maximumDepth: Int; var offset = 0
    mutating func whitespace() { while offset < bytes.count && [9,10,13,32].contains(bytes[offset]) { offset += 1 } }
    mutating func value(depth: Int) throws -> JSONValue {
        guard depth <= maximumDepth else { throw IdentityFailure(code: "INVALID_REQUEST") }
        whitespace(); guard offset < bytes.count else { throw IdentityFailure(code: "INVALID_REQUEST") }
        switch bytes[offset] {
        case 123:
            offset += 1; whitespace(); var object: [String: JSONValue] = [:]
            if take(125) { return .object(object) }
            while true {
                whitespace(); let key = try string(); whitespace(); guard take(58) else { throw invalid() }
                guard object[key] == nil else { throw IdentityFailure(code: "DUPLICATE_JSON_KEY") }
                object[key] = try value(depth: depth + 1); whitespace()
                if take(125) { return .object(object) }; guard take(44) else { throw invalid() }
            }
        case 91:
            offset += 1; whitespace(); var array: [JSONValue] = []
            if take(93) { return .array(array) }
            while true { array.append(try value(depth: depth + 1)); whitespace(); if take(93) { return .array(array) }; guard take(44) else { throw invalid() } }
        case 34: return .string(try string())
        case 116: try literal("true"); return .bool(true)
        case 102: try literal("false"); return .bool(false)
        case 110: try literal("null"); return .null
        default:
            let start = offset
            while offset < bytes.count && ![9,10,13,32,44,93,125].contains(bytes[offset]) { offset += 1 }
            let raw = String(decoding: bytes[start..<offset], as: UTF8.self)
            guard raw.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
                  let number = Double(raw), number.isFinite else { throw invalid() }
            // Protocol integer-valued numeric fields are bounded below 2^53;
            // large counters must use the specified decimal string encoding.
            guard abs(number) <= 9_007_199_254_740_991 else { throw invalid() }
            return .number(number)
        }
    }
    mutating func take(_ b: UInt8) -> Bool { if offset < bytes.count && bytes[offset] == b { offset += 1; return true }; return false }
    func invalid() -> IdentityFailure { IdentityFailure(code: "INVALID_REQUEST") }
    mutating func literal(_ text: String) throws {
        let b = Array(text.utf8); guard offset + b.count <= bytes.count, Array(bytes[offset..<offset+b.count]) == b else { throw invalid() }; offset += b.count
    }
    mutating func string() throws -> String {
        let start = offset; guard take(34) else { throw invalid() }; var escaped = false
        while offset < bytes.count {
            let b = bytes[offset]; offset += 1
            if b < 32 { throw invalid() }
            if !escaped && b == 34 {
                let data = Data(bytes[start..<offset])
                guard let result = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String else { throw invalid() }
                // Foundation replaces unpaired UTF-16 surrogates; reject them
                // explicitly instead of allowing a changed digest input.
                let raw = Array(bytes[start..<offset]); var i = 1
                while i + 5 < raw.count {
                    if raw[i] == 92 {
                        if raw[i+1] == 117, let unit = UInt16(String(decoding: raw[i+2...i+5], as: UTF8.self), radix: 16) {
                            if unit >= 0xD800 && unit <= 0xDBFF {
                                guard i+11 < raw.count, raw[i+6] == 92, raw[i+7] == 117,
                                      let low = UInt16(String(decoding: raw[i+8...i+11], as: UTF8.self), radix:16), low >= 0xDC00 && low <= 0xDFFF else { throw invalid() }; i += 12; continue
                            }
                            if unit >= 0xDC00 && unit <= 0xDFFF { throw invalid() }; i += 6; continue
                        }; i += 2
                    } else { i += 1 }
                }
                return result
            }
            if !escaped && b == 92 { escaped = true } else { escaped = false }
        }; throw invalid()
    }
}

import CoreFoundation
