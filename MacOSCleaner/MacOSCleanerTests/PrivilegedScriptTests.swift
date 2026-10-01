import XCTest
@testable import MacOSCleaner

final class PrivilegedScriptTests: XCTestCase {
    func testAppleScriptRoundTripPreservesShellMetacharacters() throws {
        let samples = [
            "plain",
            "a'b",
            "q\"w",
            "a\\b",
            "a$b",
            "a`c",
            "a b",
            "юникод",
            "~$doc.docx",
        ]
        for sample in samples {
            let command = "printf %s \(ShellQuoting.shellQuoted(sample))"
            let source = try PrivilegedTaskRunner.appleScriptSource(command: command, administrator: false)
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            XCTAssertNil(error, "\(sample): \(String(describing: error))")
            XCTAssertEqual(result?.stringValue, sample, sample)
        }
    }

    func testNewlineInCommandIsRejected() {
        XCTAssertThrowsError(try PrivilegedTaskRunner.escapedForAppleScriptString("printf %s 'a\nb'")) { error in
            guard case PrivilegedTaskRunner.PrivilegedError.invalidCommand = error else {
                XCTFail("Expected invalidCommand, got \(error)")
                return
            }
        }
    }
}
