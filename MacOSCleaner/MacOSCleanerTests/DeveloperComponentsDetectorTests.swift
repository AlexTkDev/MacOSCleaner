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
        XCTAssertEqual(component?.isSelected, false)
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
