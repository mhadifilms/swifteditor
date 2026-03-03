import Foundation
import CoreMediaPlus
import CommandBus
import EffectsEngine

// MARK: - Transition Handlers

/// Handler for AddTransitionCommand — creates a TransitionInstance and stores it.
public final class AddTransitionHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = AddTransitionCommand
    private let store: TransitionStore

    public init(store: TransitionStore) {
        self.store = store
    }

    public func validate(_ command: AddTransitionCommand) throws {
        // Ensure no duplicate transition between the same clips
        if store.transition(between: command.clipAID, and: command.clipBID) != nil {
            throw CommandError.validationFailed("A transition already exists between these clips")
        }
    }

    public func execute(_ command: AddTransitionCommand) async throws -> (any Command)? {
        let transitionType = parseTransitionType(command.transitionType)
        let transition = TransitionInstance(
            type: transitionType,
            duration: command.duration,
            clipAID: command.clipAID,
            clipBID: command.clipBID
        )
        store.add(transition)
        return RemoveTransitionCommand(transitionID: transition.id)
    }

    private func parseTransitionType(_ typeString: String) -> TransitionType {
        switch typeString.lowercased() {
        case "crossdissolve", "dissolve":
            return .crossDissolve
        case "diptoblack":
            return .dipToBlack
        case "diptowhite":
            return .dipToWhite
        case "wipeleft":
            return .wipe(direction: .left)
        case "wiperight":
            return .wipe(direction: .right)
        case "wipeup":
            return .wipe(direction: .up)
        case "wipedown":
            return .wipe(direction: .down)
        case "pushleft":
            return .push(direction: .left)
        case "pushright":
            return .push(direction: .right)
        case "pushup":
            return .push(direction: .up)
        case "pushdown":
            return .push(direction: .down)
        case "slideleft":
            return .slide(direction: .left)
        case "slideright":
            return .slide(direction: .right)
        case "slideup":
            return .slide(direction: .up)
        case "slidedown":
            return .slide(direction: .down)
        default:
            return .crossDissolve
        }
    }
}

/// Handler for RemoveTransitionCommand — removes a transition from the store.
public final class RemoveTransitionHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = RemoveTransitionCommand
    private let store: TransitionStore

    public init(store: TransitionStore) {
        self.store = store
    }

    public func validate(_ command: RemoveTransitionCommand) throws {
        guard store.transition(by: command.transitionID) != nil else {
            throw CommandError.validationFailed("Transition not found")
        }
    }

    public func execute(_ command: RemoveTransitionCommand) async throws -> (any Command)? {
        guard let removed = store.remove(id: command.transitionID) else {
            throw CommandError.executionFailed("Transition not found")
        }
        // Return inverse command to restore the transition
        let typeString = transitionTypeString(removed.type)
        return AddTransitionCommand(
            clipAID: removed.clipAID,
            clipBID: removed.clipBID,
            transitionType: typeString,
            duration: removed.duration
        )
    }

    private func transitionTypeString(_ type: TransitionType) -> String {
        switch type {
        case .crossDissolve: return "crossDissolve"
        case .dipToBlack: return "dipToBlack"
        case .dipToWhite: return "dipToWhite"
        case .wipe(let dir): return "wipe\(dir.rawValue.capitalized)"
        case .push(let dir): return "push\(dir.rawValue.capitalized)"
        case .slide(let dir): return "slide\(dir.rawValue.capitalized)"
        }
    }
}
