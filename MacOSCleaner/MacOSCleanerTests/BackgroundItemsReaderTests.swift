import XCTest
@testable import MacOSCleaner

final class BackgroundItemsReaderTests: XCTestCase {
    func test_readLaunchAgents_returnsPlistFiles() async {
        let reader = BackgroundItemsReader()
        let urls = await reader.readLaunchAgents()
        XCTAssertFalse(urls.isEmpty)
        XCTAssertTrue(urls.allSatisfy { $0.pathExtension == "plist" })
    }

    func test_readLoginItemEntries_parsesAppsAndLoginItemsOnly() async {
        let mockRunner = MockCommandRunner()
        mockRunner.runHandler = { command, args in
            XCTAssertEqual(command, "/usr/bin/sfltool")
            XCTAssertEqual(args, ["dumpbtm"])
            let output = """
            ========================
            Records for UID 501:
            #1:
                             Name: Raycast
                   Developer Name: Raycast Technologies Inc
                  Team Identifier: SY64MV22J9
                             Type: app (0x2)
                      Disposition: [enabled, allowed, visible, notified]
                       Identifier: com.raycast.macos
                              URL: file:///Applications/Raycast.app/
                  Executable Path: /Applications/Raycast.app/Contents/MacOS/Raycast

            #2:
                             Name: SomeAgent
                             Type: agent (0x10)
                      Disposition: [enabled]
                       Identifier: com.example.agent
                              URL: file:///Users/test/Library/LaunchAgents/com.example.agent.plist

            #3:
                             Name: HelperLogin
                             Type: login item (0x4)
                      Disposition: [disabled, disallowed]
                       Identifier: com.example.HelperLogin
                              URL: file:///Applications/Example.app/Contents/Library/LoginItems/HelperLogin.app/
            """
            return CommandResult(stdout: output, stderr: "", exitCode: 0)
        }

        let reader = BackgroundItemsReader(commandRunner: mockRunner)
        let snapshot = await reader.readLoginItemEntries()
        XCTAssertEqual(snapshot.accessStatus, .available)
        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.items[0].name, "HelperLogin")
        XCTAssertFalse(snapshot.items[0].isEnabled)
        XCTAssertEqual(snapshot.items[1].name, "Raycast")
        XCTAssertTrue(snapshot.items[1].isEnabled)
        XCTAssertEqual(snapshot.items[1].teamID, "SY64MV22J9")
    }

    func test_readLoginItemEntries_handlesAuthorizationRequired() async {
        let mockRunner = MockCommandRunner()
        mockRunner.runHandler = { _, _ in
            CommandResult(
                stdout: "",
                stderr: "Error obtaining right system.privilege.admin: errAuthorizationInvalidRef (-60002)\nauthorization failed",
                exitCode: 1
            )
        }

        let reader = BackgroundItemsReader(commandRunner: mockRunner)
        let snapshot = await reader.readLoginItemEntries()
        XCTAssertEqual(snapshot.accessStatus, .authorizationRequired)
        XCTAssertTrue(snapshot.items.isEmpty)
    }
}
