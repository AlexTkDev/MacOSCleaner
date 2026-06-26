import Foundation
import Observation

/// States of the cleanup lifecycle.
public enum CleanupState: Equatable, Sendable {
    case idle
    case scanning
    case preview
    case executing
    case completed
    case failed
    case cancelled
}

/// State machine for managing the cleanup process.
/// Ensures only valid state transitions.
@Observable
public final class CleanupStateMachine {
    public private(set) var state: CleanupState = .idle
    
    public init() {}
    
    /// Error for invalid state transitions.
    public enum StateError: Error, LocalizedError {
        case invalidTransition(from: CleanupState, to: CleanupState)
        
        public var errorDescription: String? {
            switch self {
            case .invalidTransition(let from, let to):
                return String(format: "error_invalid_transition_format".localized, "\(from)", "\(to)")
            }
        }
    }
    
    /// Transitions to a new state.
    /// - Parameter newState: The target state.
    /// - Throws: `StateError.invalidTransition` if the transition is invalid.
    public func transition(to newState: CleanupState) throws {
        guard isValidTransition(from: state, to: newState) else {
            throw StateError.invalidTransition(from: state, to: newState)
        }
        state = newState
    }
    
    /// Resets the state machine to the initial state.
    public func reset() {
        state = .idle
    }
    
    private func isValidTransition(from: CleanupState, to: CleanupState) -> Bool {
        // Error or cancellation can occur from active states
        if to == .failed || to == .cancelled {
            return from == .scanning || from == .executing || from == .preview
        }
        
        switch (from, to) {
        case (.idle, .scanning):
            return true
        case (.scanning, .preview):
            return true
        case (.preview, .executing):
            return true
        case (.executing, .completed):
            return true
        case (.preview, .scanning):
            return true
        case (.completed, .scanning):
            return true
        case (.failed, .scanning):
            return true
        case (.cancelled, .scanning):
            return true
        default:
            return false
        }
    }
}
