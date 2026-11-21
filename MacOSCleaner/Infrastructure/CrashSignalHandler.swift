import Darwin
import Foundation

enum CrashSignalHandler {
    static let defaultSignals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS]

    static func install(signals: [Int32] = defaultSignals, installExceptionHandler: Bool = true) {
        if installExceptionHandler {
            NSSetUncaughtExceptionHandler { exception in
                let message = "Uncaught NSException: \(exception.name.rawValue): \(exception.reason ?? "")\n"
                message.withCString { ptr in
                    _ = Darwin.write(STDERR_FILENO, ptr, Darwin.strlen(ptr))
                }
                Darwin.abort()
            }
        }

        for sig in signals {
            var action = sigaction()
            sigemptyset(&action.sa_mask)
            action.sa_flags = SA_RESETHAND | SA_NODEFER
            action.__sigaction_u.__sa_handler = { receivedSignal in
                CrashSignalHandler.writeSignalBanner(for: receivedSignal)
                Darwin.signal(receivedSignal, SIG_DFL)
                Darwin.raise(receivedSignal)
            }
            sigaction(sig, &action, nil)
        }
    }

    private static func writeSignalBanner(for sig: Int32) {
        switch sig {
        case SIGABRT:
            writeStatic("MacOSCleaner fatal signal: SIGABRT\n")
        case SIGSEGV:
            writeStatic("MacOSCleaner fatal signal: SIGSEGV\n")
        case SIGBUS:
            writeStatic("MacOSCleaner fatal signal: SIGBUS\n")
        default:
            writeStatic("MacOSCleaner fatal signal\n")
        }
    }

    private static func writeStatic(_ message: StaticString) {
        message.withUTF8Buffer { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = Darwin.write(STDERR_FILENO, base, buffer.count)
        }
    }
}
