import Foundation

/// Track type discriminator.
public enum TrackType: String, Codable, Sendable {
    case video
    case audio
    case subtitle
}

/// Which edge of a clip is being trimmed.
public enum TrimEdge: String, Codable, Sendable {
    case leading
    case trailing
}

/// Compositing blend modes.
public enum BlendMode: String, Codable, Sendable {
    case normal
    case add
    case multiply
    case screen
    case overlay
    case softLight
    case hardLight
    case difference
}

/// Type-safe parameter values for effects.
public enum ParameterValue: Codable, Sendable, Hashable {
    case float(Double)
    case int(Int)
    case bool(Bool)
    case string(String)
    case color(r: Double, g: Double, b: Double, a: Double)
    case point(x: Double, y: Double)
    case size(width: Double, height: Double)
}

/// Describes a parameter exposed by an effect.
public enum ParameterDescriptor: Codable, Sendable {
    case float(name: String, displayName: String, defaultValue: Double, min: Double, max: Double)
    case int(name: String, displayName: String, defaultValue: Int, min: Int, max: Int)
    case bool(name: String, displayName: String, defaultValue: Bool)
    case color(name: String, displayName: String, defaultR: Double, defaultG: Double, defaultB: Double, defaultA: Double)
    case point(name: String, displayName: String, defaultX: Double, defaultY: Double)
    case choice(name: String, displayName: String, options: [String], defaultIndex: Int)
}

/// Runtime parameter values for an effect instance.
public struct ParameterValues: Sendable {
    private var values: [String: ParameterValue]

    public init(_ values: [String: ParameterValue] = [:]) {
        self.values = values
    }

    public subscript(name: String) -> ParameterValue? {
        get { values[name] }
        set { values[name] = newValue }
    }

    public func floatValue(_ name: String, default defaultValue: Double = 0) -> Double {
        if case .float(let v) = values[name] { return v }
        return defaultValue
    }

    public func boolValue(_ name: String, default defaultValue: Bool = false) -> Bool {
        if case .bool(let v) = values[name] { return v }
        return defaultValue
    }

    public func intValue(_ name: String, default defaultValue: Int = 0) -> Int {
        if case .int(let v) = values[name] { return v }
        return defaultValue
    }

    /// All parameter names.
    public var allKeys: [String] {
        Array(values.keys).sorted()
    }
}

/// Selection state for the timeline.
public struct SelectionState: Sendable {
    public var selectedClipIDs: Set<UUID>
    public var selectedTrackIDs: Set<UUID>
    public var selectedRange: TimeRange?

    public init(
        selectedClipIDs: Set<UUID> = [],
        selectedTrackIDs: Set<UUID> = [],
        selectedRange: TimeRange? = nil
    ) {
        self.selectedClipIDs = selectedClipIDs
        self.selectedTrackIDs = selectedTrackIDs
        self.selectedRange = selectedRange
    }

    public static let empty = SelectionState()

    public var isEmpty: Bool {
        selectedClipIDs.isEmpty && selectedTrackIDs.isEmpty && selectedRange == nil
    }
}

/// Protocols for time-based types.
public protocol TimeRangeProviding {
    var timeRange: TimeRange { get }
}

public protocol TimePositionable: TimeRangeProviding {
    var startTime: Rational { get set }
    var duration: Rational { get }
}

/// Log level for plugin logging.
public enum LogLevel: Sendable {
    case debug, info, warning, error
}

/// Status of an asset in the media manager.
public enum AssetStatus: String, Codable, Sendable {
    case importing
    case ready
    case offline
    case error
}

/// Proxy generation presets.
public enum ProxyPreset: String, Codable, Sendable {
    case halfResolution
    case quarterResolution
    case proresProxy
}
