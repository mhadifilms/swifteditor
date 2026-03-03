import Foundation
import Network
import CoreMediaPlus
import CommandBus
import TimelineKit

/// Configuration for the network API server.
public struct NetworkServerConfiguration: Sendable {
    public var port: UInt16
    public var host: String
    public var maxConnections: Int

    public init(port: UInt16 = 8080, host: String = "127.0.0.1", maxConnections: Int = 10) {
        self.port = port
        self.host = host
        self.maxConnections = maxConnections
    }
}

/// Lightweight HTTP server wrapping SwiftEditorAPI for remote control.
/// Uses Network.framework (NWListener) — no external dependencies.
public final class NetworkServer: @unchecked Sendable {
    private let configuration: NetworkServerConfiguration
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.swifteditor.networkserver")

    // Weak references to engine components
    private let dispatcher: CommandDispatcher
    private let timelineProvider: @Sendable () -> TimelineModel?
    private let transportStateProvider: @Sendable () -> NetworkTransportState

    public private(set) var isRunning = false

    public init(
        configuration: NetworkServerConfiguration = NetworkServerConfiguration(),
        dispatcher: CommandDispatcher,
        timelineProvider: @escaping @Sendable () -> TimelineModel?,
        transportStateProvider: @escaping @Sendable () -> NetworkTransportState
    ) {
        self.configuration = configuration
        self.dispatcher = dispatcher
        self.timelineProvider = timelineProvider
        self.transportStateProvider = transportStateProvider
    }

    // MARK: - Server Lifecycle

    public func start() throws {
        guard !isRunning else { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: configuration.port)!)
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isRunning = true
            case .failed, .cancelled:
                self?.isRunning = false
            default:
                break
            }
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener?.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection)
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }

            if let request = self.parseHTTPRequest(data) {
                Task {
                    let response = await self.routeRequest(request)
                    self.sendResponse(response, on: connection)
                }
            } else {
                let response = HTTPResponse(status: 400, body: #"{"error":"Bad Request"}"#)
                self.sendResponse(response, on: connection)
            }
        }
    }

    // MARK: - Routing

    private func routeRequest(_ request: HTTPRequest) async -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            return HTTPResponse(status: 200, body: #"{"status":"ok"}"#)

        case ("GET", "/timeline"):
            return getTimeline()

        case ("GET", "/transport"):
            return getTransport()

        case ("POST", "/commands"):
            return await postCommand(body: request.body)

        case ("POST", "/script"):
            return await postScript(body: request.body)

        default:
            return HTTPResponse(status: 404, body: #"{"error":"Not Found"}"#)
        }
    }

    // MARK: - Endpoints

    private func getTimeline() -> HTTPResponse {
        guard let timeline = timelineProvider() else {
            return HTTPResponse(status: 503, body: #"{"error":"Timeline not available"}"#)
        }

        var videoTracks: [[String: Any]] = []
        for track in timeline.videoTracks {
            let clips = timeline.clipsOnTrack(track.id).map { clip -> [String: Any] in
                [
                    "id": clip.id.uuidString,
                    "startTime": clip.startTime.seconds,
                    "duration": clip.duration.seconds,
                    "sourceAssetID": clip.sourceAssetID.uuidString,
                    "isEnabled": clip.isEnabled,
                    "speed": clip.speed,
                ]
            }
            videoTracks.append([
                "id": track.id.uuidString,
                "clips": clips,
            ])
        }

        var audioTracks: [[String: Any]] = []
        for track in timeline.audioTracks {
            let clips = timeline.clipsOnTrack(track.id).map { clip -> [String: Any] in
                [
                    "id": clip.id.uuidString,
                    "startTime": clip.startTime.seconds,
                    "duration": clip.duration.seconds,
                ]
            }
            audioTracks.append([
                "id": track.id.uuidString,
                "clips": clips,
            ])
        }

        let response: [String: Any] = [
            "duration": timeline.duration.seconds,
            "videoTracks": videoTracks,
            "audioTracks": audioTracks,
        ]

        return jsonResponse(response)
    }

    private func getTransport() -> HTTPResponse {
        let state = transportStateProvider()
        let response: [String: Any] = [
            "currentTime": state.currentTime,
            "isPlaying": state.isPlaying,
        ]
        return jsonResponse(response)
    }

    private func postCommand(body: Data?) async -> HTTPResponse {
        guard let body, !body.isEmpty else {
            return HTTPResponse(status: 400, body: #"{"error":"Empty body"}"#)
        }

        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let type = json["type"] as? String else {
            return HTTPResponse(status: 400, body: #"{"error":"Invalid JSON, expected {\"type\":\"...\", ...}"}"#)
        }

        // Deserialize and dispatch via CommandSerializer
        do {
            let command = try CommandSerializer.decode(from: body)
            let result = try await dispatcher.dispatch(command)
            switch result {
            case .success:
                return jsonResponse(["success": true, "type": type])
            case .successWithValue:
                return jsonResponse(["success": true, "type": type, "hasValue": true])
            case .failure(let error):
                return HTTPResponse(status: 422, body: #"{"error":"\#(error)"}"#)
            }
        } catch {
            return HTTPResponse(status: 422, body: #"{"error":"\#(error)"}"#)
        }
    }

    private func postScript(body: Data?) async -> HTTPResponse {
        guard let body, !body.isEmpty else {
            return HTTPResponse(status: 400, body: #"{"error":"Empty body"}"#)
        }

        guard let commands = try? JSONDecoder().decode([NetworkScriptEntry].self, from: body) else {
            return HTTPResponse(status: 400, body: #"{"error":"Expected JSON array of command objects"}"#)
        }

        var executed = 0
        var errors: [String] = []

        for entry in commands {
            do {
                try await dispatchScriptEntry(entry)
                executed += 1
            } catch {
                errors.append("\(entry.type): \(error)")
            }
        }

        let response: [String: Any] = [
            "executed": executed,
            "errors": errors,
            "total": commands.count,
        ]
        return jsonResponse(response)
    }

    private func dispatchScriptEntry(_ entry: NetworkScriptEntry) async throws {
        guard let timeline = timelineProvider() else {
            throw NetworkError.timelineNotAvailable
        }

        switch entry.type {
        case "addTrack":
            let type: TrackType = entry.trackType == "audio" ? .audio : .video
            timeline.requestTrackInsert(at: entry.index ?? 0, type: type)
        case "bladeAll":
            guard let time = entry.time else { throw NetworkError.missingField("time") }
            timeline.requestBladeAll(at: Rational(Int64(time), 1))
        case "undo":
            timeline.undoManager.undo()
        case "redo":
            timeline.undoManager.redo()
        default:
            throw NetworkError.unknownCommand(entry.type)
        }
    }

    // MARK: - HTTP Parsing

    private func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
        guard let string = String(data: data, encoding: .utf8) else { return nil }
        let lines = string.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])

        // Find body after empty line
        var body: Data?
        if let emptyLineIndex = lines.firstIndex(of: "") {
            let bodyString = lines[(emptyLineIndex + 1)...].joined(separator: "\r\n")
            if !bodyString.isEmpty {
                body = bodyString.data(using: .utf8)
            }
        }

        return HTTPRequest(method: method, path: path, body: body)
    }

    private func sendResponse(_ response: HTTPResponse, on connection: NWConnection) {
        let statusText: String
        switch response.status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 422: statusText = "Unprocessable Entity"
        case 503: statusText = "Service Unavailable"
        default: statusText = "Unknown"
        }

        let bodyData = response.body.data(using: .utf8) ?? Data()
        let header = """
        HTTP/1.1 \(response.status) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r

        """

        var responseData = header.data(using: .utf8) ?? Data()
        responseData.append(bodyData)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func jsonResponse(_ dict: [String: Any]) -> HTTPResponse {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return HTTPResponse(status: 200, body: string)
        }
        return HTTPResponse(status: 500, body: #"{"error":"JSON serialization failed"}"#)
    }
}

// MARK: - Types

struct HTTPRequest {
    let method: String
    let path: String
    let body: Data?
}

struct HTTPResponse {
    let status: Int
    let body: String
}

/// Transport state snapshot for the network API.
public struct NetworkTransportState: Sendable {
    public let currentTime: Double
    public let isPlaying: Bool

    public init(currentTime: Double, isPlaying: Bool) {
        self.currentTime = currentTime
        self.isPlaying = isPlaying
    }
}

struct NetworkScriptEntry: Codable {
    let type: String
    var trackType: String?
    var index: Int?
    var time: Int?
}

enum NetworkError: Error, CustomStringConvertible {
    case timelineNotAvailable
    case missingField(String)
    case unknownCommand(String)

    var description: String {
        switch self {
        case .timelineNotAvailable: return "Timeline not available"
        case .missingField(let f): return "Missing field: \(f)"
        case .unknownCommand(let c): return "Unknown command: \(c)"
        }
    }
}
