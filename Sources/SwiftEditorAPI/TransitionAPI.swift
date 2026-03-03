import Foundation
import CoreMediaPlus
import CommandBus
import EffectsEngine
import Observation

/// Thread-safe store for transition instances.
@Observable
public final class TransitionStore: @unchecked Sendable {
    private var transitions: [UUID: TransitionInstance] = [:]

    public init() {}

    /// Add a transition to the store.
    public func add(_ transition: TransitionInstance) {
        transitions[transition.id] = transition
    }

    /// Remove a transition by ID. Returns the removed instance if found.
    @discardableResult
    public func remove(id: UUID) -> TransitionInstance? {
        transitions.removeValue(forKey: id)
    }

    /// Get a transition by ID.
    public func transition(by id: UUID) -> TransitionInstance? {
        transitions[id]
    }

    /// Find a transition between two specific clips.
    public func transition(between clipAID: UUID, and clipBID: UUID) -> TransitionInstance? {
        transitions.values.first {
            ($0.clipAID == clipAID && $0.clipBID == clipBID) ||
            ($0.clipAID == clipBID && $0.clipBID == clipAID)
        }
    }

    /// All transitions in the store.
    public var all: [TransitionInstance] {
        Array(transitions.values)
    }

    /// All transition IDs.
    public var ids: Set<UUID> {
        Set(transitions.keys)
    }
}

/// Facade for transition operations.
/// Mutating operations go through CommandBus for undo support.
public final class TransitionAPI: @unchecked Sendable {
    private let dispatcher: CommandDispatcher
    public let store: TransitionStore

    public init(dispatcher: CommandDispatcher, store: TransitionStore) {
        self.dispatcher = dispatcher
        self.store = store
    }

    /// Add a transition between two adjacent clips.
    @discardableResult
    public func addTransition(clipAID: UUID, clipBID: UUID, type: String, duration: Rational) async throws -> CommandResult {
        let command = AddTransitionCommand(clipAID: clipAID, clipBID: clipBID, transitionType: type, duration: duration)
        return try await dispatcher.dispatch(command)
    }

    /// Remove a transition by ID.
    @discardableResult
    public func removeTransition(transitionID: UUID) async throws -> CommandResult {
        let command = RemoveTransitionCommand(transitionID: transitionID)
        return try await dispatcher.dispatch(command)
    }

    /// All transitions.
    public var transitions: [TransitionInstance] {
        store.all
    }

    /// Find a transition between two specific clips.
    public func transition(between clipAID: UUID, and clipBID: UUID) -> TransitionInstance? {
        store.transition(between: clipAID, and: clipBID)
    }
}
