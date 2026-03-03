import Foundation

/// Envelope for serializing commands with their type identifier
private struct CommandEnvelope: Codable {
    let typeIdentifier: String
    let payload: Data
}

/// Serialization utilities for commands
public enum CommandSerializer {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Encode a command to JSON data, including its type identifier
    public static func encode(_ command: any Command) throws -> Data {
        let payload = try encoder.encode(command)
        let envelope = CommandEnvelope(
            typeIdentifier: type(of: command).typeIdentifier,
            payload: payload
        )
        return try encoder.encode(envelope)
    }

    /// Decode a command from JSON data using the CommandRegistry
    public static func decode(from data: Data) throws -> any Command {
        let envelope = try decoder.decode(CommandEnvelope.self, from: data)
        guard let commandType = CommandRegistry.shared.commandType(for: envelope.typeIdentifier) else {
            throw CommandError.serializationFailed(
                "Unknown command type: \(envelope.typeIdentifier)"
            )
        }
        return try decoder.decode(commandType, from: envelope.payload)
    }
}
