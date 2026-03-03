import XCTest
import Foundation
@testable import CommandBus
@testable import CoreMediaPlus

// MARK: - Benchmark Commands

private struct BenchCommand: Command {
    static let typeIdentifier = "bench.increment"
    let value: Int
    var undoDescription: String { "Bench \(value)" }
    var isMutating: Bool { true }
}

private struct BenchUndoCommand: Command {
    static let typeIdentifier = "bench.decrement"
    let value: Int
    var undoDescription: String { "Undo bench \(value)" }
    var isMutating: Bool { true }
}

private actor BenchCounter {
    var total: Int = 0
    func add(_ n: Int) { total += n }
    func subtract(_ n: Int) { total -= n }
}

private final class BenchHandler: CommandHandler {
    let counter: BenchCounter

    init(counter: BenchCounter) {
        self.counter = counter
    }

    func validate(_ command: BenchCommand) throws {}

    func execute(_ command: BenchCommand) async throws -> (any Command)? {
        await counter.add(command.value)
        return BenchUndoCommand(value: command.value)
    }
}

private final class BenchUndoHandler: CommandHandler {
    let counter: BenchCounter

    init(counter: BenchCounter) {
        self.counter = counter
    }

    func validate(_ command: BenchUndoCommand) throws {}

    func execute(_ command: BenchUndoCommand) async throws -> (any Command)? {
        await counter.subtract(command.value)
        return BenchCommand(value: command.value)
    }
}

/// Performance benchmarks for the CommandBus dispatcher and serialization.
final class CommandBusBenchmarks: XCTestCase {

    // MARK: - Dispatch Benchmarks

    func testDispatch10000Commands() {
        let counter = BenchCounter()
        let dispatcher = CommandDispatcher()

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(options: options) {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await dispatcher.register(BenchHandler(counter: counter))
                await dispatcher.register(BenchUndoHandler(counter: counter))

                for i in 0..<10_000 {
                    try? await dispatcher.dispatch(BenchCommand(value: i))
                }
                semaphore.signal()
            }
            semaphore.wait()
        }
    }

    func testDispatch1000CommandsWithUndoRedo() {
        let counter = BenchCounter()
        let dispatcher = CommandDispatcher()

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(options: options) {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await dispatcher.register(BenchHandler(counter: counter))
                await dispatcher.register(BenchUndoHandler(counter: counter))

                // Dispatch 1000 commands
                for i in 0..<1000 {
                    try? await dispatcher.dispatch(BenchCommand(value: i))
                }

                // Undo all 1000
                for _ in 0..<1000 {
                    _ = try? await dispatcher.undo()
                }

                // Redo all 1000
                for _ in 0..<1000 {
                    _ = try? await dispatcher.redo()
                }

                semaphore.signal()
            }
            semaphore.wait()
        }
    }

    // MARK: - Serialization Benchmarks

    func testSerializationRoundTrip1000Commands() {
        CommandRegistry.shared.register(BenchCommand.self)

        let commands: [BenchCommand] = (0..<1000).map { BenchCommand(value: $0) }

        measure {
            for command in commands {
                let data = try! CommandSerializer.encode(command)
                let _ = try! CommandSerializer.decode(from: data)
            }
        }
    }

    func testSerializationEncode1000Commands() {
        CommandRegistry.shared.register(BenchCommand.self)

        let commands: [BenchCommand] = (0..<1000).map { BenchCommand(value: $0) }

        measure {
            for command in commands {
                let _ = try! CommandSerializer.encode(command)
            }
        }
    }

    func testSerializationDecode1000Commands() {
        CommandRegistry.shared.register(BenchCommand.self)

        // Pre-encode all commands
        let encodedData: [Data] = (0..<1000).map { i in
            try! CommandSerializer.encode(BenchCommand(value: i))
        }

        measure {
            for data in encodedData {
                let _ = try! CommandSerializer.decode(from: data)
            }
        }
    }

    func testCommandMacroSerialization() {
        CommandRegistry.shared.register(BenchCommand.self)
        CommandRegistry.shared.register(CommandMacro.self)

        // Create macros with 10 sub-commands each
        let macros: [CommandMacro] = (0..<100).map { i in
            CommandMacro(
                commands: (0..<10).map { j in BenchCommand(value: i * 10 + j) },
                undoDescription: "Macro \(i)"
            )
        }

        measure {
            for macro in macros {
                let data = try! CommandSerializer.encode(macro)
                let _ = try! CommandSerializer.decode(from: data)
            }
        }
    }

    // MARK: - Middleware Benchmarks

    func testDispatchWithMiddleware() {
        let counter = BenchCounter()
        let dispatcher = CommandDispatcher()

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(options: options) {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await dispatcher.register(BenchHandler(counter: counter))
                await dispatcher.register(BenchUndoHandler(counter: counter))

                // Add 3 middleware layers
                for _ in 0..<3 {
                    await dispatcher.addMiddleware(PassthroughMiddleware())
                }

                for i in 0..<5000 {
                    try? await dispatcher.dispatch(BenchCommand(value: i))
                }
                semaphore.signal()
            }
            semaphore.wait()
        }
    }

    // MARK: - Registry Benchmarks

    func testRegistryLookup10000Times() {
        let registry = CommandRegistry()
        registry.register(BenchCommand.self)

        measure {
            for _ in 0..<10_000 {
                let _ = registry.commandType(for: BenchCommand.typeIdentifier)
            }
        }
    }

    func testRegistryLookupMiss10000Times() {
        let registry = CommandRegistry()
        registry.register(BenchCommand.self)

        measure {
            for _ in 0..<10_000 {
                let _ = registry.commandType(for: "nonexistent.command.type")
            }
        }
    }
}

// MARK: - Helpers

private final class PassthroughMiddleware: CommandMiddleware {
    func beforeExecute(_ command: any Command) async -> Bool {
        true
    }

    func afterExecute(_ command: any Command, result: CommandResult) async {}
}
