import XCTest
@testable import MacOSCleaner

final class UninstallerServiceTests: XCTestCase {
    var service: UninstallerService!
    
    override func setUp() async throws {
        service = UninstallerService()
    }
    
    func testCreateSearchPatternsXcode() async {
        let patterns = await service.createSearchPatterns(bundleID: "com.apple.dt.Xcode", appName: "Xcode")
        let set = Set(patterns)
        
        XCTAssertTrue(set.contains("com.apple.dt.Xcode"))
        XCTAssertTrue(set.contains("apple.dt.Xcode"))
        XCTAssertTrue(set.contains("dt.Xcode"))
        XCTAssertTrue(set.contains("Xcode"))
        XCTAssertTrue(set.contains("Simulator"))
        XCTAssertTrue(set.contains("Instruments"))
    }
    
    func testCreateSearchPatternsAndroidStudio() async {
        let patterns = await service.createSearchPatterns(bundleID: "com.google.android.studio", appName: "Android Studio")
        let set = Set(patterns)
        
        XCTAssertTrue(set.contains("com.google.android.studio"))
        XCTAssertTrue(set.contains("google.android.studio"))
        XCTAssertTrue(set.contains("android.studio"))
        XCTAssertTrue(set.contains("studio"))
        XCTAssertTrue(set.contains("AndroidStudio"))
        XCTAssertTrue(set.contains("Android"))
        XCTAssertTrue(set.contains("Studio"))
        XCTAssertTrue(set.contains("gradle"))
        XCTAssertTrue(set.contains("emulator"))
    }
    
    func testCreateSearchPatternsFlutter() async {
        let patterns = await service.createSearchPatterns(bundleID: "com.apple.mobileinstallation", appName: "Runner")
        let set = Set(patterns)
        
        // Wait, appName is Runner, but maybe we should use a better name.
        // If we search for Runner, we should find related stuff.
        XCTAssertTrue(set.contains("Runner"))
    }
    
    func testCreateSearchPatternsMacOSCleaner() async {
        let patterns = await service.createSearchPatterns(bundleID: "input.MacOSCleaner", appName: "MacOSCleaner")
        let set = Set(patterns)
        
        XCTAssertTrue(set.contains("input.MacOSCleaner"))
        XCTAssertTrue(set.contains("MacOSCleaner"))
        XCTAssertTrue(set.contains("macoscleaner"))
    }
    
    func testSystemSearchPaths() async {
        let paths = await service.getSystemSearchPaths()
        XCTAssertFalse(paths.isEmpty)
        XCTAssertTrue(paths.contains { $0.contains("/var/folders/") })
    }
}
