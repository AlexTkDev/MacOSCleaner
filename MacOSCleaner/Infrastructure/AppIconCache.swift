import AppKit
import CoreGraphics
import Foundation

/// Bounded, memory-capped cache of downsampled app/file icons.
/// Rasterizes icons off the main actor at target pixel dimensions (64px or 128px)
/// into concrete CGImage-backed NSImages so SwiftUI never triggers synchronous
/// IconServices XPC / 1024px TIFF expansion on the main thread.
public final class AppIconCache: @unchecked Sendable {
    public static let shared = AppIconCache()

    private actor RenderGate {
        private var available: Int
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(limit: Int) {
            self.available = max(1, limit)
        }

        func acquire() async {
            if available > 0 {
                available -= 1
                return
            }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func release() {
            if !waiters.isEmpty {
                let next = waiters.removeFirst()
                next.resume()
            } else {
                available += 1
            }
        }
    }

    private let cache: NSCache<NSString, NSImage>
    private let renderGate: RenderGate
    private let customRenderer: (@Sendable (String, Int) -> NSImage?)?

    public init(
        countLimit: Int = 512,
        totalCostLimit: Int = 32 * 1024 * 1024,
        maxConcurrentRenders: Int = 4,
        iconRenderer: (@Sendable (String, Int) -> NSImage?)? = nil
    ) {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
        self.cache = cache
        self.renderGate = RenderGate(limit: maxConcurrentRenders)
        self.customRenderer = iconRenderer
    }

    public func cachedIcon(forPath path: String, pixelSize: Int = 64) -> NSImage? {
        let key = Self.cacheKey(path: path, pixelSize: pixelSize) as NSString
        return cache.object(forKey: key)
    }

    public func clear() {
        cache.removeAllObjects()
    }

    public func icon(forPath path: String, pixelSize: Int = 64) async -> NSImage? {
        let normalizedPath = NormalizedPath.string(URL(fileURLWithPath: path).standardizedFileURL.path)
        let targetPixels = max(16, min(pixelSize, 256))
        let key = Self.cacheKey(path: normalizedPath, pixelSize: targetPixels) as NSString

        if let hit = cache.object(forKey: key) {
            return hit
        }

        guard FileManager.default.fileExists(atPath: normalizedPath) else {
            return nil
        }

        await renderGate.acquire()
        if let hit = cache.object(forKey: key) {
            await renderGate.release()
            return hit
        }
        if Task.isCancelled {
            await renderGate.release()
            return nil
        }

        let customRenderer = self.customRenderer
        let rendered: NSImage? = await Task.detached(priority: .utility) {
            guard !Task.isCancelled else { return nil }
            let raw: NSImage? = if let customRenderer {
                customRenderer(normalizedPath, targetPixels)
            } else {
                NSWorkspace.shared.icon(forFile: normalizedPath)
            }
            guard let raw else { return nil }
            return Self.downsample(raw, targetPixelSize: targetPixels)
        }.value

        await renderGate.release()

        guard let rendered else { return nil }
        let cost = Self.estimatedByteCost(of: rendered, fallbackPixelSize: targetPixels)
        cache.setObject(rendered, forKey: key, cost: cost)
        return rendered
    }

    static func cacheKey(path: String, pixelSize: Int) -> String {
        let std = NormalizedPath.lowercaseKey(path)
        return "\(std)#\(pixelSize)"
    }

    static func downsample(_ image: NSImage, targetPixelSize: Int) -> NSImage? {
        var proposedRect = CGRect(x: 0, y: 0, width: targetPixelSize, height: targetPixelSize)
        guard let cg = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        let finalCG: CGImage
        if cg.width <= targetPixelSize && cg.height <= targetPixelSize {
            finalCG = cg
        } else {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Host.rawValue
            guard let ctx = CGContext(
                data: nil,
                width: targetPixelSize,
                height: targetPixelSize,
                bitsPerComponent: 8,
                bytesPerRow: targetPixelSize * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return nil
            }
            ctx.interpolationQuality = CGInterpolationQuality.high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: targetPixelSize, height: targetPixelSize))
            guard let scaled = ctx.makeImage() else {
                return nil
            }
            finalCG = scaled
        }

        let points = CGFloat(targetPixelSize) / 2.0
        return NSImage(cgImage: finalCG, size: NSSize(width: points, height: points))
    }

    private static func estimatedByteCost(of image: NSImage, fallbackPixelSize: Int) -> Int {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return rep.pixelsWide * rep.pixelsHigh * 4
        }
        return fallbackPixelSize * fallbackPixelSize * 4
    }
}
