import Foundation

/// Read-only snapshot of Apple Intelligence system assets and readable caches.
/// Never modifies or deletes system assets.
struct AppleIntelligenceStorageSnapshot: Sendable, Equatable {
    struct Component: Identifiable, Sendable, Equatable {
        let id: String
        let titleKey: String
        let path: String
        let sizeBytes: Int64
    }

    let components: [Component]
    let totalReadableBytes: Int64
    let isBaseModelAccessRestricted: Bool
    let baseModelReadableBytes: Int64?

    static let baseModelEstimateText = "~10–13 GB"
}

enum AppleIntelligenceStorageReader {
    struct ComponentSpec: Sendable {
        let id: String
        let titleKey: String
        let path: String
    }

    static func defaultComponents(home: String = NSHomeDirectory()) -> [ComponentSpec] {
        [
            ComponentSpec(
                id: "photos_magic_cleanup",
                titleKey: "settings_ai_comp_photos_cleanup",
                path: "/System/Library/AssetsV2/com_apple_MobileAsset_UAF_Photos_MagicCleanup"
            ),
            ComponentSpec(
                id: "photos_spatial_relive",
                titleKey: "settings_ai_comp_spatial_photos",
                path: "/System/Library/AssetsV2/com_apple_MobileAsset_UAF_Photos_SpatialPhotosRelive"
            ),
            ComponentSpec(
                id: "visual_intelligence_cache",
                titleKey: "settings_ai_comp_visual_intelligence",
                path: "\(home)/Library/Caches/com.apple.visualintelligenced"
            ),
        ]
    }

    static let defaultBaseModelPath = "/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_GenerativeModels"

    static func inspect(
        components: [ComponentSpec]? = nil,
        baseModelPath: String = defaultBaseModelPath,
        fileManager: FileManager = .default
    ) -> AppleIntelligenceStorageSnapshot {
        let specs = components ?? defaultComponents()
        var resolvedComponents: [AppleIntelligenceStorageSnapshot.Component] = []
        var totalReadable: Int64 = 0

        for spec in specs {
            guard fileManager.fileExists(atPath: spec.path),
                  isReadableDirectory(atPath: spec.path, fileManager: fileManager) else {
                continue
            }
            let url = URL(fileURLWithPath: spec.path)
            // Pass empty excludedPaths because default FileManager.shouldExclude skips /System.
            let size = fileManager.getPhysicalDirectorySize(url: url, excludedPaths: [])
            totalReadable += size
            resolvedComponents.append(.init(
                id: spec.id,
                titleKey: spec.titleKey,
                path: spec.path,
                sizeBytes: size
            ))
        }

        let (restricted, baseBytes) = probeBaseModelDirectory(atPath: baseModelPath, fileManager: fileManager)
        if let baseBytes {
            totalReadable += baseBytes
        }

        return AppleIntelligenceStorageSnapshot(
            components: resolvedComponents,
            totalReadableBytes: totalReadable,
            isBaseModelAccessRestricted: restricted,
            baseModelReadableBytes: baseBytes
        )
    }

    private static func isReadableDirectory(atPath path: String, fileManager: FileManager) -> Bool {
        do {
            _ = try fileManager.contentsOfDirectory(atPath: path)
            return true
        } catch {
            return false
        }
    }

    private static func probeBaseModelDirectory(atPath path: String, fileManager: FileManager) -> (restricted: Bool, bytes: Int64?) {
        guard fileManager.fileExists(atPath: path) else {
            return (true, nil)
        }
        do {
            _ = try fileManager.contentsOfDirectory(atPath: path)
            let size = fileManager.getPhysicalDirectorySize(url: URL(fileURLWithPath: path), excludedPaths: [])
            return (false, size)
        } catch {
            let ns = error as NSError
            let isPermissionError =
                (ns.domain == NSPOSIXErrorDomain && (ns.code == Int(EPERM) || ns.code == Int(EACCES)))
                || (ns.domain == NSCocoaErrorDomain && (ns.code == NSFileReadNoPermissionError || ns.code == NSFileReadUnknownError))
            return (isPermissionError || true, nil)
        }
    }
}
