import Foundation

/// Append-only JSONL journal for command replay and audit trails.
/// Each line in the journal file is a JSON-encoded command envelope.
public actor CommandJournal {
    private let fileURL: URL
    private var fileHandle: FileHandle?

    /// Create a journal that writes to the specified file URL
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Append a command to the journal
    public func append(_ command: any Command) throws {
        let data = try CommandSerializer.encode(command)

        if fileHandle == nil {
            try openForWriting()
        }

        guard let handle = fileHandle else {
            throw CommandError.serializationFailed("Failed to open journal file for writing")
        }

        // Write the command data followed by a newline
        handle.seekToEndOfFile()
        handle.write(data)
        handle.write(Data([0x0A])) // newline
    }

    /// Replay all commands from the journal in order
    public func replay() throws -> [any Command] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let contents = try Data(contentsOf: fileURL)
        let lines = contents.split(separator: 0x0A)

        return try lines.compactMap { lineData in
            let data = Data(lineData)
            guard !data.isEmpty else { return nil }
            return try CommandSerializer.decode(from: data)
        }
    }

    /// Close the journal file handle
    public func close() {
        fileHandle?.closeFile()
        fileHandle = nil
    }

    // MARK: - Private

    private func openForWriting() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            let dir = fileURL.deletingLastPathComponent()
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            fm.createFile(atPath: fileURL.path, contents: nil)
        }
        fileHandle = try FileHandle(forWritingTo: fileURL)
    }
}
