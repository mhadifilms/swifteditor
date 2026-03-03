import Foundation

/// Composes multiple commands into a single atomic undo step.
/// When undone, all contained commands are undone in reverse order.
public struct CommandMacro: Command {
    public static let typeIdentifier = "builtin.macro"

    public let commands: [any Command]
    public let undoDescription: String
    public var isMutating: Bool { true }

    public init(commands: [any Command], undoDescription: String) {
        self.commands = commands
        self.undoDescription = undoDescription
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case commands
        case undoDescription
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.undoDescription = try container.decode(String.self, forKey: .undoDescription)

        let dataArray = try container.decode([Data].self, forKey: .commands)
        self.commands = try dataArray.map { data in
            try CommandSerializer.decode(from: data)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(undoDescription, forKey: .undoDescription)

        let dataArray = try commands.map { command in
            try CommandSerializer.encode(command)
        }
        try container.encode(dataArray, forKey: .commands)
    }
}
