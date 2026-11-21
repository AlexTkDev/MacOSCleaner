import AppKit
import SwiftUI

struct CachedFileIconView<Placeholder: View>: View {
    let path: String?
    let size: CGFloat
    let cornerRadius: CGFloat
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?

    init(
        path: String?,
        size: CGFloat,
        cornerRadius: CGFloat = 0,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.path = path
        self.size = size
        self.cornerRadius = cornerRadius
        self.placeholder = placeholder
        let pixelSize = Self.targetPixelSize(for: size)
        if let path {
            _image = State(initialValue: AppIconCache.shared.cachedIcon(forPath: path, pixelSize: pixelSize))
        } else {
            _image = State(initialValue: nil)
        }
    }

    var body: some View {
        let pixelSize = Self.targetPixelSize(for: size)
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                placeholder()
                    .frame(width: size, height: size)
            }
        }
        .task(id: "\(path ?? "")#\(pixelSize)") {
            guard let path else {
                image = nil
                return
            }
            if let cached = AppIconCache.shared.cachedIcon(forPath: path, pixelSize: pixelSize) {
                image = cached
                return
            }
            image = nil
            let loaded = await AppIconCache.shared.icon(forPath: path, pixelSize: pixelSize)
            if !Task.isCancelled {
                image = loaded
            }
        }
    }

    private static func targetPixelSize(for pointSize: CGFloat) -> Int {
        pointSize <= 36 ? 64 : 128
    }
}
