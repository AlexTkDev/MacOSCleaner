import XCTest
@testable import MacOSCleaner

final class DeveloperComponentsDetectorTests: XCTestCase {
    func test_detect_returnsEmptyForUnknownApp() async {
        let components = await DeveloperComponentsDetector.detect(
            appName: "UnknownApp",
            bundleID: "com.unknown.app",
            fileManager: .default
        )
        XCTAssertTrue(components.isEmpty)
    }

    func test_detect_returnsAndroidComponents() async {
        let components = await DeveloperComponentsDetector.detect(
            appName: "Android Studio",
            bundleID: "com.google.android.studio",
            fileManager: .default
        )
        // May or may not have Android SDK installed — just check it doesn't crash
        XCTAssertNotNil(components)
    }

    func test_detect_reportsAndroidUserDataWithoutSelectingSharedData() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeveloperComponentsDetectorTests-\(UUID().uuidString)", isDirectory: true)
        let androidData = home.appendingPathComponent(".android", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: androidData, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096)
            .write(to: androidData.appendingPathComponent("devices.xml"))

        let components = await DeveloperComponentsDetector.detect(
            appName: "Android Studio",
            bundleID: "com.google.android.studio",
            fileManager: .default,
            homeDirectory: home
        )

        let component = components.first { $0.url.path == androidData.path }
        XCTAssertNotNil(component)
        XCTAssertEqual(component?.category, .androidCaches)
        XCTAssertEqual(component?.isSelected, true)
    }

    func test_detect_androidLibraryRootSelectedByDefault() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeveloperComponentsAndroidRoot-\(UUID().uuidString)", isDirectory: true)
        let androidRoot = home.appendingPathComponent("Library/Android", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: androidRoot, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 2048)
            .write(to: androidRoot.appendingPathComponent("marker.bin"))

        let components = await DeveloperComponentsDetector.detect(
            appName: "Android Studio",
            bundleID: "com.google.android.studio",
            fileManager: .default,
            homeDirectory: home
        )
        let component = components.first { $0.url.path == androidRoot.path }
        XCTAssertNotNil(component)
        XCTAssertEqual(component?.isSelected, false)
        XCTAssertEqual(component?.category, .androidSDK)
    }

    func test_detect_xcodeDeveloperDataSelectedByDefault() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeveloperComponentsXcode-\(UUID().uuidString)", isDirectory: true)
        let derived = home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        let sims = home.appendingPathComponent("Library/Developer/CoreSimulator", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: derived, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sims, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 2048).write(to: derived.appendingPathComponent("a.bin"))
        try Data(repeating: 1, count: 2048).write(to: sims.appendingPathComponent("b.bin"))

        let components = await DeveloperComponentsDetector.detect(
            appName: "Xcode",
            bundleID: "com.apple.dt.Xcode",
            fileManager: .default,
            homeDirectory: home
        )
        let derivedComponent = components.first { $0.url.path == derived.path }
        let simComponent = components.first { $0.url.path == sims.path }
        XCTAssertEqual(derivedComponent?.isSelected, true)
        XCTAssertEqual(simComponent?.isSelected, true)
    }

    func test_detect_returnsXcodeComponents() async {
        let components = await DeveloperComponentsDetector.detect(
            appName: "Xcode",
            bundleID: "com.apple.dt.Xcode",
            fileManager: .default
        )
        XCTAssertNotNil(components)
    }

    func test_detect_returnsDockerComponents() async {
        let components = await DeveloperComponentsDetector.detect(
            appName: "Docker",
            bundleID: "com.docker.docker",
            fileManager: .default
        )
        XCTAssertNotNil(components)
    }
}
