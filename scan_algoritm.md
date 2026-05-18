# Scan Algorithm (UninstallerService.swift)

The scan algorithm runs in 3 stages to identify residual application files:

1. **Spotlight (mdfind):** Queries system index by bundleID or application name. Filters out paths not contained within Library, tmp, or var/folders.
2. **Receipts (pkgutil):** Searches for files installed via .pkg/.mpkg packages linked to the bundleID.
3. **Manual Depth Search:** Iterates through a list of system paths (~/Library/..., /Library/..., /tmp, etc.).
    * **Broad Search:** Compares file/folder names against a set of generated patterns (createSearchPatterns: bundleID, application name, name segments, TeamID for binaries).
    * **Recursion:** Performs recursive search 2-3 levels deep for "vendor" folders (Application Support, Caches, Logs, etc.).

## Additional Details:
* **createSearchPatterns:** Generates keyword set for searching based on app name and bundleID.
* **TeamID:** Verifies developer signature for binaries in LaunchAgents/Daemons via `codesign`.
* **Safety:** Every found item passes through `safetyManager.validate(url:)` before being added to results to prevent deletion of system files.
