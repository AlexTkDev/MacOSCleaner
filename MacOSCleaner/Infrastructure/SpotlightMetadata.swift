import CoreServices
import Foundation

/// Safe wrapper over Spotlight `MDItem*` APIs.
/// When Spotlight indexing is disabled (`mdutil -a -i off`), `MDItemCreate` returns `nil`;
/// passing `nil` to `MDItemCopyAttribute` crashes with a memory error.
public enum SpotlightMetadata {
    private struct Provider: Sendable {
        let isIndexingAvailable: @Sendable (String) -> Bool
        let lastUsedDate: @Sendable (URL) -> Date?
    }

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var overrideProvider: Provider?
    }

    private static let state = State()

    private static let productionProvider = Provider(
        isIndexingAvailable: { path in
            let probePath = FileManager.default.fileExists(atPath: path) ? path : "/Applications"
            if MDItemCreate(nil, probePath as CFString) != nil {
                return true
            }
            return MDItemCreate(nil, "/System/Applications" as CFString) != nil
        },
        lastUsedDate: { url in
            guard let mdItem = MDItemCreate(nil, url.path as CFString) else {
                return nil
            }
            return MDItemCopyAttribute(mdItem, kMDItemLastUsedDate) as? Date
        }
    )

    private static var activeProvider: Provider {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.overrideProvider ?? productionProvider
    }

    public static func isIndexingAvailable(at path: String = NSHomeDirectory()) -> Bool {
        activeProvider.isIndexingAvailable(path)
    }

    /// Returns Spotlight's `kMDItemLastUsedDate` when available, falling back to filesystem
    /// `contentAccessDate` when Spotlight is disabled or unindexed, or `nil` if unknown.
    public static func lastUsedDate(for url: URL) -> Date? {
        if let spotlightDate = activeProvider.lastUsedDate(url) {
            return spotlightDate
        }
        return (try? url.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate
    }

    /// Test seam — overrides Spotlight probes to simulate `mdutil -a -i off` or synthetic dates.
    static func setOverrideForTesting(
        isIndexingAvailable: (@Sendable (String) -> Bool)? = nil,
        lastUsedDate: (@Sendable (URL) -> Date?)? = nil
    ) {
        state.lock.lock()
        defer { state.lock.unlock() }
        if isIndexingAvailable == nil && lastUsedDate == nil {
            state.overrideProvider = nil
        } else {
            let base = productionProvider
            state.overrideProvider = Provider(
                isIndexingAvailable: isIndexingAvailable ?? base.isIndexingAvailable,
                lastUsedDate: lastUsedDate ?? base.lastUsedDate
            )
        }
    }

    static func resetForTesting() {
        setOverrideForTesting()
    }
}
