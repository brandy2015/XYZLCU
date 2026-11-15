import Foundation

enum JSONSchemaValidator {
    static func validate(_ value: JSONValue, schema: JSONValue, root: JSONValue, path: String) throws {
        func fail() -> IdentityFailure { IdentityFailure(code: "INVALID_REQUEST", fields: [path]) }
        if let ref = schema["$ref"]?.string {
            guard ref.hasPrefix("#/") else { throw fail() }
            var target = root
            for component in ref.dropFirst(2).split(separator: "/") { guard let next = target[String(component)] else { throw fail() }; target = next }
            try validate(value, schema: target, root: root, path: path)
        }
        if let constant = schema["const"], value != constant { throw fail() }
        if let allowed = schema["enum"]?.array, !allowed.contains(value) { throw fail() }
        if let branches = schema["oneOf"]?.array {
            var matched = 0
            for branch in branches { if (try? validate(value, schema: branch, root: root, path: path)) != nil { matched += 1 } }
            guard matched == 1 else { throw fail() }
        }
        if let declared = schema["type"] {
            let names = declared.array?.compactMap(\.string) ?? [declared.string ?? ""]
            let actual: String
            switch value { case .object: actual = "object"; case .array: actual = "array"; case .string: actual = "string"; case .bool: actual = "boolean"; case .null: actual = "null"; case .number(let n): actual = n.rounded() == n ? "integer" : "number" }
            guard names.contains(actual) || (actual == "integer" && names.contains("number")) else { throw fail() }
        }
        if let object = value.object {
            for key in schema["required"]?.array?.compactMap(\.string) ?? [] { guard object[key] != nil else { throw IdentityFailure(code:"INVALID_REQUEST",fields:[path + "." + key]) } }
            let props = schema["properties"]?.object ?? [:]
            for (key, item) in object {
                if let child = props[key] { try validate(item, schema: child, root: root, path: path.isEmpty ? key : path + "." + key) }
                else if schema["additionalProperties"]?.bool == false { throw IdentityFailure(code:"INVALID_REQUEST",fields:[path + "." + key]) }
            }
        }
        if let array = value.array {
            if let n = schema["minItems"]?.number, Double(array.count) < n { throw fail() }
            if let n = schema["maxItems"]?.number, Double(array.count) > n { throw fail() }
            if schema["uniqueItems"]?.bool == true && Set(array.map(\.canonicalString)).count != array.count { throw fail() }
            if let child = schema["items"] { for (i, item) in array.enumerated() { try validate(item, schema: child, root: root, path: path + "[\(i)]") } }
        }
        if let s = value.string {
            if let n = schema["minLength"]?.number, Double(s.unicodeScalars.count) < n { throw fail() }
            if let n = schema["maxLength"]?.number, Double(s.unicodeScalars.count) > n { throw fail() }
            if let pattern = schema["pattern"]?.string, s.range(of: pattern, options:.regularExpression) == nil { throw fail() }
            if schema["format"]?.string == "uuid", UUID(uuidString:s) == nil { throw fail() }
            if schema["format"]?.string == "date-time", ISO8601DateFormatter().date(from: s) == nil { throw fail() }
        }
        if let n = value.number {
            guard n.isFinite else { throw fail() }
            if let limit = schema["minimum"]?.number, n < limit { throw fail() }
            if let limit = schema["maximum"]?.number, n > limit { throw fail() }
            if let limit = schema["exclusiveMinimum"]?.number, n <= limit { throw fail() }
        }
    }
}
