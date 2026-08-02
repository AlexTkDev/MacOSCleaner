import Foundation

/// Single entry point for filesystem path normalization across Uninstaller / Cleanup.
/// Collapses `//`, trims awkward home joins, and returns path-stable file URLs
/// (directory vs file URL forms of the same path compare equal).
public enum NormalizedPath {
    /// Collapse duplicate `/` while keeping a single leading slash for absolute paths.
    public static func string(_ path: String) -> String {
        guard path.contains("//") else { return path }
        let isAbsolute = path.hasPrefix("/")
        var collapsed = path
        while collapsed.contains("//") {
            collapsed = collapsed.replacingOccurrences(of: "//", with: "/")
        }
        if isAbsolute, !collapsed.hasPrefix("/") {
            collapsed = "/" + collapsed
        }
        return collapsed
    }

    /// Join two path segments without producing `//` (handles trailing/leading slashes).
    public static func join(_ base: String, _ relative: String) -> String {
        let b = base.hasSuffix("/") ? String(base.dropLast()) : base
        let r = relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        if b.isEmpty { return string("/" + r) }
        if r.isEmpty { return string(b) }
        return string("\(b)/\(r)")
    }

    /// `home` + relative path under the user home directory.
    public static func joinHome(_ home: String, _ relative: String) -> String {
        join(home, relative)
    }

    /// Path identity key — same filesystem path always yields the same string
    /// regardless of trailing slash / `isDirectory` URL form.
    public static func key(_ url: URL) -> String {
        string(url.standardizedFileURL.path)
    }

    /// Path-stable file URL (`isDirectory: false`) so `…/foo` and `…/foo/` hash equal.
    public static func canonicalize(_ url: URL) -> URL {
        Self.url(url.path, isDirectory: false)
    }

    /// Normalized file URL from a path string.
    public static func url(_ path: String, isDirectory: Bool = false) -> URL {
        URL(fileURLWithPath: string(path), isDirectory: isDirectory).standardizedFileURL
    }

    /// Re-normalize an existing URL to a path-stable form (drops directory hint).
    public static func url(_ url: URL) -> URL {
        canonicalize(url)
    }

    /// Normalize every URL in a set, collapsing slash-variants of the same path.
    public static func urls(_ urls: Set<URL>) -> Set<URL> {
        var byKey: [String: URL] = [:]
        for url in urls {
            let canonical = canonicalize(url)
            byKey[key(canonical)] = canonical
        }
        return Set(byKey.values)
    }

    /// Order-preserving unique by path key (file/dir/`//` variants collapse).
    public static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let canonical = canonicalize(url)
            guard seen.insert(key(canonical)).inserted else { continue }
            result.append(canonical)
        }
        return result
    }

    /// Display string for UI (always collapsed, standardized).
    public static func displayString(_ url: URL) -> String {
        key(url)
    }
}
