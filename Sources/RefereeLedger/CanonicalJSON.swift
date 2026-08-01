import Foundation

/// Deterministic JSON encoding used for event payloads and integrity inputs.
public enum CanonicalJSON {
    public enum Error: Swift.Error, Equatable { case invalidJSON, unsupportedValue }

    public static func canonicalize(_ json: String) throws -> String {
        guard let data = json.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw Error.invalidJSON
        }
        return try render(value)
    }

    private static func render(_ value: Any) throws -> String {
        if let dictionary = value as? [String: Any] {
            let members = try dictionary.keys.sorted().map { key in
                try string(key) + ":" + render(dictionary[key]!)
            }.joined(separator: ",")
            return "{" + members + "}"
        }
        if let array = value as? [Any] {
            return "[" + (try array.map(render)).joined(separator: ",") + "]"
        }
        if let value = value as? String { return try string(value) }
        if let value = value as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return value.boolValue ? "true" : "false" }
            guard value.doubleValue.isFinite else { throw Error.unsupportedValue }
            // JSONSerialization supplies locale-independent NSNumber instances.
            return value.stringValue
        }
        if value is NSNull { return "null" }
        throw Error.unsupportedValue
    }

    private static func string(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value])
        let encoded = String(decoding: data, as: UTF8.self)
        return String(encoded.dropFirst().dropLast())
    }
}
