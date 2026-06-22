import Foundation
import OSLog

private extension Logger {
    static let retry = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "RetryPolicy")
}

/// Errors that are considered transient and eligible for retry.
public enum TransientError: Error {
    case timeout
    case connectionLost
    case temporaryFailure
    case resourceBusy

    public init?(from error: Error) {
        switch error {
        case CommandRunnerError.timeout:
            self = .timeout
        case let nsError as NSError:
            switch nsError.code {
            case NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost:
                self = .connectionLost
            case Int(EBUSY), Int(ETIMEDOUT):
                self = .resourceBusy
            default:
                return nil
            }
        case is CancellationError:
            return nil
        default:
            return nil
        }
    }
}

/// Configuration for retry behavior with exponential backoff.
public struct RetryPolicy: Sendable {
    /// Maximum number of retry attempts.
    public var maxRetries: Int
    /// Base delay between retries (doubles each attempt).
    public var baseDelay: Duration
    /// Maximum delay cap.
    public var maxDelay: Duration

    public init(maxRetries: Int = 3, baseDelay: Duration = .seconds(1), maxDelay: Duration = .seconds(30)) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public static let `default` = RetryPolicy()

    /// Calculate delay for a given attempt (0-indexed).
    public func delay(forAttempt attempt: Int) -> Duration {
        let microseconds = baseDelay.components.seconds * Int64(pow(2.0, Double(attempt)))
        let capped = min(microseconds, maxDelay.components.seconds)
        return .seconds(capped)
    }
}

/// Wraps an async operation with retry logic for transient errors.
public func withRetry<T: Sendable>(
    policy: RetryPolicy = .default,
    operation: @Sendable () async throws -> T
) async throws -> T {
    var lastError: Error?

    for attempt in 0...policy.maxRetries {
        do {
            return try await operation()
        } catch {
            if let transient = TransientError(from: error) {
                lastError = error
                if attempt < policy.maxRetries {
                    let delay = policy.delay(forAttempt: attempt)
                    Logger.retry.warning("Retry \(attempt + 1)/\(policy.maxRetries) after \(String(describing: transient)): waiting \(delay.components.seconds)s")
                    try await Task.sleep(for: delay)
                }
            } else {
                throw error
            }
        }
    }

    throw lastError ?? CancellationError()
}
