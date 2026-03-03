import Testing
import Foundation
@testable import CommandBus

// MARK: - Test Commands

struct IncrementCommand: Command {
    static let typeIdentifier = "test.increment"
    let amount: Int
    var undoDescription: String { "Increment by \(amount)" }
    var isMutating: Bool { true }
}

struct DecrementCommand: Command {
    static let typeIdentifier = "test.decrement"
    let amount: Int
    var undoDescription: String { "Decrement by \(amount)" }
    var isMutating: Bool { true }
}

struct ReadOnlyCommand: Command {
    static let typeIdentifier = "test.readonly"
    var undoDescription: String { "Read" }
    var isMutating: Bool { false }
}

// MARK: - Shared State Actor

actor Counter {
    var value: Int = 0

    func increment(by amount: Int) {
        value += amount
    }

    func decrement(by amount: Int) {
        value -= amount
    }
}

// MARK: - Test Handlers

final class IncrementHandler: CommandHandler {
    let counter: Counter

    init(counter: Counter) {
        self.counter = counter
    }

    func validate(_ command: IncrementCommand) throws {
        if command.amount < 0 {
            throw CommandError.validationFailed("Amount must be non-negative")
        }
    }

    func execute(_ command: IncrementCommand) async throws -> (any Command)? {
        await counter.increment(by: command.amount)
        return DecrementCommand(amount: command.amount)
    }
}

final class DecrementHandler: CommandHandler {
    let counter: Counter

    init(counter: Counter) {
        self.counter = counter
    }

    func validate(_ command: DecrementCommand) throws {}

    func execute(_ command: DecrementCommand) async throws -> (any Command)? {
        await counter.decrement(by: command.amount)
        return IncrementCommand(amount: command.amount)
    }
}

struct ReadOnlyHandler: CommandHandler {
    func validate(_ command: ReadOnlyCommand) throws {}
    func execute(_ command: ReadOnlyCommand) async throws -> (any Command)? { nil }
}

// MARK: - Test Middleware

actor MiddlewareTracker {
    var beforeCallCount = 0
    var afterCallCount = 0

    func recordBefore() { beforeCallCount += 1 }
    func recordAfter() { afterCallCount += 1 }
}

final class TrackingMiddleware: CommandMiddleware {
    let shouldProceed: Bool
    let tracker: MiddlewareTracker

    init(shouldProceed: Bool = true, tracker: MiddlewareTracker = MiddlewareTracker()) {
        self.shouldProceed = shouldProceed
        self.tracker = tracker
    }

    func beforeExecute(_ command: any Command) async -> Bool {
        await tracker.recordBefore()
        return shouldProceed
    }

    func afterExecute(_ command: any Command, result: CommandResult) async {
        await tracker.recordAfter()
    }
}

// MARK: - Tests

@Suite("CommandBus Tests")
struct CommandBusTests {

    @Test("Dispatch executes command via registered handler")
    func dispatchExecutesCommand() async throws {
        let counter = Counter()
        let dispatcher = CommandDispatcher()

        await dispatcher.register(IncrementHandler(counter: counter))
        await dispatcher.register(DecrementHandler(counter: counter))

        let result = try await dispatcher.dispatch(IncrementCommand(amount: 5))
        guard case .success = result else {
            Issue.record("Expected success result")
            return
        }

        let value = await counter.value
        #expect(value == 5)
    }

    @Test("Dispatch throws for unregistered command")
    func dispatchThrowsForUnregistered() async {
        let dispatcher = CommandDispatcher()

        do {
            _ = try await dispatcher.dispatch(IncrementCommand(amount: 1))
            Issue.record("Expected handlerNotFound error")
        } catch let error as CommandError {
            guard case .handlerNotFound = error else {
                Issue.record("Expected handlerNotFound, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Validation failure prevents execution")
    func validationFailurePreventsExecution() async {
        let counter = Counter()
        let dispatcher = CommandDispatcher()
        await dispatcher.register(IncrementHandler(counter: counter))

        do {
            _ = try await dispatcher.dispatch(IncrementCommand(amount: -1))
            Issue.record("Expected validation error")
        } catch let error as CommandError {
            guard case .validationFailed = error else {
                Issue.record("Expected validationFailed, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let value = await counter.value
        #expect(value == 0)
    }

    @Test("Undo reverses the last command")
    func undoReversesLastCommand() async throws {
        let counter = Counter()
        let dispatcher = CommandDispatcher()
        await dispatcher.register(IncrementHandler(counter: counter))
        await dispatcher.register(DecrementHandler(counter: counter))

        try await dispatcher.dispatch(IncrementCommand(amount: 10))
        var value = await counter.value
        #expect(value == 10)

        let didUndo = try await dispatcher.undo()
        #expect(didUndo)

        value = await counter.value
        #expect(value == 0)
    }

    @Test("Redo restores an undone command")
    func redoRestoresUndoneCommand() async throws {
        let counter = Counter()
        let dispatcher = CommandDispatcher()
        await dispatcher.register(IncrementHandler(counter: counter))
        await dispatcher.register(DecrementHandler(counter: counter))

        try await dispatcher.dispatch(IncrementCommand(amount: 7))
        _ = try await dispatcher.undo()
        let didRedo = try await dispatcher.redo()
        #expect(didRedo)

        let value = await counter.value
        #expect(value == 7)
    }

    @Test("Undo returns false when stack is empty")
    func undoReturnsFalseWhenEmpty() async throws {
        let dispatcher = CommandDispatcher()
        let didUndo = try await dispatcher.undo()
        #expect(!didUndo)
    }

    @Test("Redo returns false when stack is empty")
    func redoReturnsFalseWhenEmpty() async throws {
        let dispatcher = CommandDispatcher()
        let didRedo = try await dispatcher.redo()
        #expect(!didRedo)
    }

    @Test("New command clears redo stack")
    func newCommandClearsRedoStack() async throws {
        let counter = Counter()
        let dispatcher = CommandDispatcher()
        await dispatcher.register(IncrementHandler(counter: counter))
        await dispatcher.register(DecrementHandler(counter: counter))

        try await dispatcher.dispatch(IncrementCommand(amount: 5))
        _ = try await dispatcher.undo()
        #expect(await dispatcher.canRedo)

        // New command should clear redo
        try await dispatcher.dispatch(IncrementCommand(amount: 3))
        #expect(await !dispatcher.canRedo)
    }

    @Test("canUndo and canRedo report correctly")
    func canUndoCanRedo() async throws {
        let counter = Counter()
        let dispatcher = CommandDispatcher()
        await dispatcher.register(IncrementHandler(counter: counter))
        await dispatcher.register(DecrementHandler(counter: counter))

        #expect(await !dispatcher.canUndo)
        #expect(await !dispatcher.canRedo)

        try await dispatcher.dispatch(IncrementCommand(amount: 1))
        #expect(await dispatcher.canUndo)
        #expect(await !dispatcher.canRedo)

        _ = try await dispatcher.undo()
        #expect(await !dispatcher.canUndo)
        #expect(await dispatcher.canRedo)
    }

    @Test("undoDescription returns correct description")
    func undoDescriptionReturnsCorrectValue() async throws {
        let counter = Counter()
        let dispatcher = CommandDispatcher()
        await dispatcher.register(IncrementHandler(counter: counter))
        await dispatcher.register(DecrementHandler(counter: counter))

        #expect(await dispatcher.undoDescription == nil)

        try await dispatcher.dispatch(IncrementCommand(amount: 42))
        #expect(await dispatcher.undoDescription == "Increment by 42")
    }

    @Test("Max undo levels are enforced")
    func maxUndoLevelsEnforced() async throws {
        let counter = Counter()
        let dispatcher = CommandDispatcher(maxUndoLevels: 3)
        await dispatcher.register(IncrementHandler(counter: counter))
        await dispatcher.register(DecrementHandler(counter: counter))

        // Push 5 commands, only last 3 should be undoable
        for i in 1...5 {
            try await dispatcher.dispatch(IncrementCommand(amount: i))
        }

        // Sum = 1+2+3+4+5 = 15
        var value = await counter.value
        #expect(value == 15)

        // Undo 3 times (amounts 5, 4, 3)
        for _ in 0..<3 {
            let didUndo = try await dispatcher.undo()
            #expect(didUndo)
        }

        // Should not be able to undo any more
        let didUndo = try await dispatcher.undo()
        #expect(!didUndo)

        // Value should be 1+2 = 3
        value = await counter.value
        #expect(value == 3)
    }

    @Test("Middleware beforeExecute is called")
    func middlewareBeforeExecuteIsCalled() async throws {
        let counter = Counter()
        let dispatcher = CommandDispatcher()
        await dispatcher.register(IncrementHandler(counter: counter))

        let middleware = TrackingMiddleware(shouldProceed: true)
        await dispatcher.addMiddleware(middleware)

        try await dispatcher.dispatch(IncrementCommand(amount: 1))

        let beforeCount = await middleware.tracker.beforeCallCount
        let afterCount = await middleware.tracker.afterCallCount
        #expect(beforeCount == 1)
        #expect(afterCount == 1)
    }

    @Test("Middleware can abort command execution")
    func middlewareCanAbortExecution() async throws {
        let counter = Counter()
        let dispatcher = CommandDispatcher()
        await dispatcher.register(IncrementHandler(counter: counter))

        let middleware = TrackingMiddleware(shouldProceed: false)
        await dispatcher.addMiddleware(middleware)

        let result = try await dispatcher.dispatch(IncrementCommand(amount: 5))
        guard case .failure = result else {
            Issue.record("Expected failure result from aborted middleware")
            return
        }

        // Command should not have executed
        let value = await counter.value
        #expect(value == 0)
    }

    @Test("Multiple middleware run in order")
    func multipleMiddlewareRunInOrder() async throws {
        let counter = Counter()
        let dispatcher = CommandDispatcher()
        await dispatcher.register(IncrementHandler(counter: counter))

        let m1 = TrackingMiddleware(shouldProceed: true)
        let m2 = TrackingMiddleware(shouldProceed: true)
        await dispatcher.addMiddleware(m1)
        await dispatcher.addMiddleware(m2)

        try await dispatcher.dispatch(IncrementCommand(amount: 1))

        #expect(await m1.tracker.beforeCallCount == 1)
        #expect(await m2.tracker.beforeCallCount == 1)
        #expect(await m1.tracker.afterCallCount == 1)
        #expect(await m2.tracker.afterCallCount == 1)
    }

    @Test("Non-mutating commands do not push to undo stack")
    func nonMutatingCommandsSkipUndoStack() async throws {
        let dispatcher = CommandDispatcher()
        await dispatcher.register(ReadOnlyHandler())

        try await dispatcher.dispatch(ReadOnlyCommand())
        #expect(await !dispatcher.canUndo)
    }

    @Test("Serialization round-trip for a command")
    func serializationRoundTrip() throws {
        CommandRegistry.shared.register(IncrementCommand.self)

        let original = IncrementCommand(amount: 42)
        let data = try CommandSerializer.encode(original)
        let decoded = try CommandSerializer.decode(from: data)

        guard let result = decoded as? IncrementCommand else {
            Issue.record("Decoded command is not IncrementCommand")
            return
        }
        #expect(result.amount == 42)
        #expect(result.undoDescription == "Increment by 42")
    }

    @Test("Serialization fails for unregistered type")
    func serializationFailsForUnregisteredType() throws {
        struct UnknownCommand: Command {
            static let typeIdentifier = "test.unknown.xyz"
            var undoDescription: String { "Unknown" }
            var isMutating: Bool { false }
        }

        let data = try CommandSerializer.encode(UnknownCommand())

        do {
            _ = try CommandSerializer.decode(from: data)
            Issue.record("Expected serialization error")
        } catch let error as CommandError {
            guard case .serializationFailed = error else {
                Issue.record("Expected serializationFailed, got \(error)")
                return
            }
        }
    }

    @Test("CommandMacro serialization round-trip")
    func commandMacroSerializationRoundTrip() throws {
        CommandRegistry.shared.register(IncrementCommand.self)
        CommandRegistry.shared.register(DecrementCommand.self)
        CommandRegistry.shared.register(CommandMacro.self)

        let macro = CommandMacro(
            commands: [
                IncrementCommand(amount: 10),
                DecrementCommand(amount: 3),
            ],
            undoDescription: "Adjust counter"
        )

        let data = try CommandSerializer.encode(macro)
        let decoded = try CommandSerializer.decode(from: data)

        guard let result = decoded as? CommandMacro else {
            Issue.record("Decoded command is not CommandMacro")
            return
        }
        #expect(result.commands.count == 2)
        #expect(result.undoDescription == "Adjust counter")

        guard let first = result.commands[0] as? IncrementCommand else {
            Issue.record("First command is not IncrementCommand")
            return
        }
        #expect(first.amount == 10)

        guard let second = result.commands[1] as? DecrementCommand else {
            Issue.record("Second command is not DecrementCommand")
            return
        }
        #expect(second.amount == 3)
    }

    @Test("CommandRegistry registers and retrieves types")
    func commandRegistryWorks() {
        let registry = CommandRegistry()
        registry.register(IncrementCommand.self)

        let retrievedType = registry.commandType(for: "test.increment")
        #expect(retrievedType != nil)
        #expect(retrievedType is IncrementCommand.Type)

        let missing = registry.commandType(for: "nonexistent")
        #expect(missing == nil)
    }

    @Test("CommandJournal append and replay")
    func journalAppendAndReplay() async throws {
        CommandRegistry.shared.register(IncrementCommand.self)
        CommandRegistry.shared.register(DecrementCommand.self)

        let tmpDir = FileManager.default.temporaryDirectory
        let journalURL = tmpDir.appendingPathComponent("test_journal_\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: journalURL) }

        let journal = CommandJournal(fileURL: journalURL)

        try await journal.append(IncrementCommand(amount: 1))
        try await journal.append(IncrementCommand(amount: 2))
        try await journal.append(DecrementCommand(amount: 3))
        await journal.close()

        let commands = try await journal.replay()
        #expect(commands.count == 3)

        guard let first = commands[0] as? IncrementCommand else {
            Issue.record("First replayed command is not IncrementCommand")
            return
        }
        #expect(first.amount == 1)

        guard let third = commands[2] as? DecrementCommand else {
            Issue.record("Third replayed command is not DecrementCommand")
            return
        }
        #expect(third.amount == 3)
    }

    @Test("Multiple undo/redo cycles maintain consistency")
    func multipleUndoRedoCycles() async throws {
        let counter = Counter()
        let dispatcher = CommandDispatcher()
        await dispatcher.register(IncrementHandler(counter: counter))
        await dispatcher.register(DecrementHandler(counter: counter))

        try await dispatcher.dispatch(IncrementCommand(amount: 10))
        try await dispatcher.dispatch(IncrementCommand(amount: 20))

        // Value should be 30
        #expect(await counter.value == 30)

        // Undo once -> 10
        _ = try await dispatcher.undo()
        #expect(await counter.value == 10)

        // Redo -> 30
        _ = try await dispatcher.redo()
        #expect(await counter.value == 30)

        // Undo twice -> 0
        _ = try await dispatcher.undo()
        _ = try await dispatcher.undo()
        #expect(await counter.value == 0)

        // Redo twice -> 30
        _ = try await dispatcher.redo()
        _ = try await dispatcher.redo()
        #expect(await counter.value == 30)
    }
}
