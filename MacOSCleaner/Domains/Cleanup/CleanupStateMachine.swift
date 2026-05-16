import Foundation
import Observation

/// Состояния жизненного цикла процесса очистки.
public enum CleanupState: Equatable, Sendable {
    case idle
    case scanning
    case preview
    case executing
    case completed
    case failed
    case cancelled
}

/// Машина состояний для управления процессом очистки.
/// Обеспечивает только валидные переходы между состояниями.
@Observable
public final class CleanupStateMachine {
    public private(set) var state: CleanupState = .idle
    
    public init() {}
    
    /// Ошибка при невалидном переходе.
    public enum StateError: Error, LocalizedError {
        case invalidTransition(from: CleanupState, to: CleanupState)
        
        public var errorDescription: String? {
            switch self {
            case .invalidTransition(let from, let to):
                return "Invalid transition from \(from) to \(to)"
            }
        }
    }
    
    /// Выполняет переход в новое состояние.
    /// - Parameter newState: Целевое состояние.
    /// - Throws: `StateError.invalidTransition` если переход невозможен.
    public func transition(to newState: CleanupState) throws {
        guard isValidTransition(from: state, to: newState) else {
            throw StateError.invalidTransition(from: state, to: newState)
        }
        state = newState
    }
    
    /// Сбрасывает машину состояний в начальное состояние.
    public func reset() {
        state = .idle
    }
    
    private func isValidTransition(from: CleanupState, to: CleanupState) -> Bool {
        // Сброс в idle возможен из любого состояния
        if to == .idle { return true }
        
        // Ошибка или отмена возможны из активных состояний
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
        default:
            return false
        }
    }
}
