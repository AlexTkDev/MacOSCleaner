# Scan Algorithm (UninstallerService.swift)

The scan algorithm runs in 4 stages to identify residual application files:

1. **Spotlight (mdfind):** Queries system index by bundleID or application name. Filters out paths not contained within Library, tmp, or var/folders.
2. **Receipts (pkgutil):** Searches for files installed via .pkg/.mpkg packages linked to the bundleID.
3. **Manual Depth Search:** Iterates through a list of system paths (~/Library/..., /Library/..., /tmp, etc.).
    * **Broad Search:** Compares file/folder names against a set of generated patterns (createSearchPatterns: bundleID, application name, name segments, TeamID for binaries).
    * **Recursion:** Performs recursive search 2-3 levels deep for "vendor" folders (Application Support, Caches, Logs, etc.).
4. **Developer Build Products:** Special handling for Xcode/Flutter build artifacts.
    * If app is inside DerivedData, adds the project folder and dev caches as related files.
    * If app is in Flutter build dir, adds the build folder as related file.

## Additional Details:
* **createSearchPatterns:** Generates keyword set for searching based on app name and bundleID.
* **getExtraPatterns:** Adds patterns for developer artifacts (DerivedData, Build, Products, CocoaPods, SwiftPM, etc.).
* **TeamID:** Verifies developer signature for binaries in LaunchAgents/Daemons via `codesign`.
* **Safety:** Every found item passes through `safetyManager.validate(url:)` before being added to results to prevent deletion of system files.

## Developer Build Product Scanning:
* **scanDeveloperBuildProducts():** Scans for .app bundles in non-standard locations:
  * `~/Library/Developer/Xcode/DerivedData/*/Build/Products/{Debug,Release}/*.app`
  * Flutter project build directories (`build/ios/iphoneos/`, `build/macos/Build/Products/`)
* **Related Files:** For dev builds, related files include:
  * The entire DerivedData project folder
  * Xcode caches (CocoaPods, com.apple.dt.Xcode, org.swift.swiftpm)
  * Flutter project build directory
