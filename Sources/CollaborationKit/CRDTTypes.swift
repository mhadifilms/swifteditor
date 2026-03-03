// CollaborationKit — CRDT-based collaborative editing
import Foundation
import CoreMediaPlus

// MARK: - CRDTIdentifier

/// Unique identifier for each CRDT element, combining a site ID and a Lamport clock value.
/// Two concurrent inserts are totally ordered by (clock, siteID) to ensure deterministic merges.
public struct CRDTIdentifier: Sendable, Codable, Hashable, Comparable {
    public let siteID: UUID
    public let clock: UInt64

    public init(siteID: UUID, clock: UInt64) {
        self.siteID = siteID
        self.clock = clock
    }

    public static func < (lhs: CRDTIdentifier, rhs: CRDTIdentifier) -> Bool {
        if lhs.clock != rhs.clock { return lhs.clock < rhs.clock }
        return lhs.siteID.uuidString < rhs.siteID.uuidString
    }
}

// MARK: - LamportClock

/// Thread-safe Lamport logical clock for causal ordering of operations.
public actor LamportClock {
    public let siteID: UUID
    private var counter: UInt64

    public init(siteID: UUID = UUID(), initialValue: UInt64 = 0) {
        self.siteID = siteID
        self.counter = initialValue
    }

    /// Returns the current clock value without incrementing.
    public var value: UInt64 { counter }

    /// Increments the clock and returns a new identifier stamped with this site.
    public func tick() -> CRDTIdentifier {
        counter += 1
        return CRDTIdentifier(siteID: siteID, clock: counter)
    }

    /// Merges a remote clock value — sets local clock to max(local, remote) + 1.
    public func merge(remoteClock: UInt64) {
        counter = max(counter, remoteClock) + 1
    }
}

// MARK: - LWWRegister

/// Last-Writer-Wins Register — a simple CRDT where the value with the highest
/// timestamp wins. Ties are broken by CRDTIdentifier ordering.
public struct LWWRegister<T: Sendable & Codable & Equatable>: Sendable, Codable, Equatable
    where T: Hashable
{
    public private(set) var value: T
    public private(set) var timestamp: CRDTIdentifier

    public init(value: T, timestamp: CRDTIdentifier) {
        self.value = value
        self.timestamp = timestamp
    }

    /// Attempts to set a new value. Only succeeds if the new timestamp is
    /// strictly greater than the current one.
    @discardableResult
    public mutating func set(_ newValue: T, at newTimestamp: CRDTIdentifier) -> Bool {
        if newTimestamp > timestamp {
            value = newValue
            timestamp = newTimestamp
            return true
        }
        return false
    }

    /// Merges a remote register — keeps the value with the higher timestamp.
    public mutating func merge(with remote: LWWRegister<T>) {
        if remote.timestamp > timestamp {
            value = remote.value
            timestamp = remote.timestamp
        }
    }
}

// MARK: - PropertyValue

/// A dynamically-typed property value used in clip property operations.
public enum PropertyValue: Sendable, Codable, Hashable {
    case double(Double)
    case string(String)
    case bool(Bool)
    case rational(Rational)

    private enum CodingKeys: String, CodingKey {
        case type, payload
    }

    private enum ValueType: String, Codable {
        case double, string, bool, rational
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)
        switch type {
        case .double:
            self = .double(try container.decode(Double.self, forKey: .payload))
        case .string:
            self = .string(try container.decode(String.self, forKey: .payload))
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .payload))
        case .rational:
            self = .rational(try container.decode(Rational.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .double(let v):
            try container.encode(ValueType.double, forKey: .type)
            try container.encode(v, forKey: .payload)
        case .string(let v):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(v, forKey: .payload)
        case .bool(let v):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(v, forKey: .payload)
        case .rational(let v):
            try container.encode(ValueType.rational, forKey: .type)
            try container.encode(v, forKey: .payload)
        }
    }
}
