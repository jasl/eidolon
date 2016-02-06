extension Optional {
    var hasValue: Bool {
        switch self {
        case .None:
            return false
        case .Some(_):
            return true
        }
    }
}

extension String {
    func toUInt() -> UInt? {
        return UInt(self)
    }

    func toUIntWithDefault(defaultValue: UInt) -> UInt {
        return UInt(self) ?? defaultValue
    }
}

// Anything that can hold a value (strings, arrays, etc)
protocol Occupiable {
    var isEmpty: Bool { get }
    var isNotEmpty: Bool { get }
}

// Give a default implementation of isNotEmpty, so conformance only requires one implementation
extension Occupiable {
    var isNotEmpty: Bool {
        return !isEmpty
    }
}

extension String: Occupiable { }

// I can't think of a way to combine these collection types. Suggestions welcome.
extension Array: Occupiable { }
extension Dictionary: Occupiable { }
extension Set: Occupiable { }

// Extend the idea of occupiability to optionals. Specifically, optionals wrapping occupiable things.
extension Optional where Wrapped: Occupiable {
    var isNilOrEmpty: Bool {
        switch self {
        case .None:
            return true
        case .Some(let value):
            return value.isEmpty
        }
    }

    var isNotNilNotEmpty: Bool {
        return !isNilOrEmpty
    }
}

// TODO: PR this into Moya
import MoyaX

extension MoyaX.Error {
    var response: MoyaX.Response? {
        switch self {
        case .ImageMapping(let response): return response
        case .JSONMapping(let response): return response
        case .StringMapping(let response): return response
        case .StatusCode(let response): return response
        case .Data(let response): return response
        case .Underlying: return nil
        }
    }
}
