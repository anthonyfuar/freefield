import AppKit
import FreefieldCore
import ImageIO
import SwiftUI

enum Thumbnails {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 600
        return cache
    }()

    static func cached(_ url: URL, maxPixel: Int) -> NSImage? {
        cache.object(forKey: key(url, maxPixel))
    }

    static func load(_ url: URL, maxPixel: Int) async -> NSImage? {
        if let hit = cached(url, maxPixel: maxPixel) { return hit }
        guard let image = await image(from: decode(url, maxPixel: maxPixel), fallback: { try? Data(contentsOf: url) }) else {
            return nil
        }
        cache.setObject(image, forKey: key(url, maxPixel))
        return image
    }

    static func load(_ data: Data, maxPixel: Int) async -> NSImage? {
        await image(from: decode(data, maxPixel: maxPixel), fallback: { data })
    }

    static func cached(_ data: Data, maxPixel: Int) async -> (key: NSString, image: NSImage?) {
        let key = "\(await fingerprint(data))#\(data.count)#\(maxPixel)" as NSString
        return (key, dataCache.object(forKey: key))
    }

    static func store(_ image: NSImage, forKey key: NSString) {
        dataCache.setObject(image, forKey: key)
    }

    private static let dataCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 120
        return cache
    }()

    @concurrent
    nonisolated private static func fingerprint(_ data: Data) async -> Int {
        var hasher = Hasher()
        data.withUnsafeBytes { hasher.combine(bytes: $0) }
        return hasher.finalize()
    }

    private static func image(from cgImage: CGImage?, fallback: () -> Data?) -> NSImage? {
        if let cgImage {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        return fallback().flatMap(NSImage.init(data:))
    }

    @concurrent
    nonisolated private static func decode(_ url: URL, maxPixel: Int) async -> CGImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return ImageCoding.cgImage(from: data, maxPixel: maxPixel)
    }

    @concurrent
    nonisolated private static func decode(_ data: Data, maxPixel: Int) async -> CGImage? {
        ImageCoding.cgImage(from: data, maxPixel: maxPixel)
    }

    private static func key(_ url: URL, _ maxPixel: Int) -> NSString {
        "\(url.path)#\(maxPixel)" as NSString
    }

    static func aspect(of url: URL) -> CGFloat? {
        if let known = aspects[url] { return known }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat, width > 0, height > 0 else { return nil }
        let turned = (properties[kCGImagePropertyOrientation] as? Int).map { (5...8).contains($0) } ?? false
        let aspect = turned ? height / width : width / height
        aspects[url] = aspect
        return aspect
    }

    private static var aspects: [URL: CGFloat] = [:]
}

struct ThumbnailImage: View {
    let url: URL
    var maxPixel = 640
    var contentMode: ContentMode = .fill
    var focus: UnitPoint = .center
    var placeholderAspect: CGFloat?

    @State private var image: NSImage?
    @State private var isSlow = false

    var body: some View {
        Group {
            if contentMode == .fill, focus != .center, let image {
                FocusedFill(aspect: image.size.height > 0 ? image.size.width / image.size.height : 1, focus: focus) {
                    Image(nsImage: image).resizable().interpolation(.high)
                }
            } else if contentMode == .fill {
                Color.clear.overlay { content }.clipped()
            } else {
                content
            }
        }
        .task(id: "\(url.path)#\(maxPixel)") {
            if let cached = Thumbnails.cached(url, maxPixel: maxPixel) {
                image = cached
                return
            }
            let spinner = Task {
                try? await Task.sleep(for: .milliseconds(300))
                if !Task.isCancelled { withAnimation(Motion.fade) { isSlow = true } }
            }
            let loaded = await Thumbnails.load(url, maxPixel: maxPixel)
            spinner.cancel()
            withAnimation(Motion.fade) {
                image = loaded
                isSlow = false
            }
        }
    }

    private var content: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if contentMode == .fit, let placeholderAspect {
                placeholder.aspectRatio(placeholderAspect, contentMode: .fit)
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary.opacity(0.5))
            .overlay {
                if isSlow {
                    ProgressView().controlSize(.small).transition(.opacity)
                }
            }
    }
}

struct DataImage: View {
    let data: Data
    var maxPixel = 800
    var contentMode: ContentMode = .fit
    var focus: UnitPoint = .center

    @State private var image: NSImage?

    var body: some View {
        Group {
            if contentMode == .fill, focus != .center, let image {
                FocusedFill(aspect: image.size.height > 0 ? image.size.width / image.size.height : 1, focus: focus) {
                    Image(nsImage: image).resizable().interpolation(.high)
                }
            } else if contentMode == .fill {
                Color.clear.overlay { content }.clipped()
            } else {
                content
            }
        }
        .task(id: data.hashValue) {
            let (key, cached) = await Thumbnails.cached(data, maxPixel: maxPixel)
            if let cached {
                image = cached
                return
            }
            guard let loaded = await Thumbnails.load(data, maxPixel: maxPixel) else {
                image = nil
                return
            }
            Thumbnails.store(loaded, forKey: key)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.fade) { image = loaded }
        }
    }

    private var content: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Rectangle().fill(.quaternary.opacity(0.4))
            }
        }
    }
}

struct FocusedFill<Content: View>: View {
    let aspect: Double
    var focus: UnitPoint = .center
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let rect = Self.rect(container: proxy.size, aspect: aspect, focus: focus)
            content()
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
        .clipped()
    }

    static func rect(container: CGSize, aspect: Double, focus: UnitPoint) -> CGRect {
        guard container.width > 0, container.height > 0, aspect > 0 else { return CGRect(origin: .zero, size: container) }
        let scale = max(container.width / aspect, container.height)
        let size = CGSize(width: aspect * scale, height: scale)
        let x = min(0, max(container.width - size.width, container.width / 2 - focus.x * size.width))
        let y = min(0, max(container.height - size.height, container.height / 2 - focus.y * size.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
