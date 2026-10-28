import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageCoding {
    public static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    public static func pixelSize(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    public static func cgImage(from data: Data, maxPixel: Int? = nil) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maxPixel {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixel
        } else if let size = pixelSize(of: data) {
            options[kCGImageSourceThumbnailMaxPixelSize] = Int(max(size.width, size.height))
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    public static func prepareForUpload(_ data: Data, maxPixel: Int = 2048, role: String? = nil) -> InputImage? {
        guard let size = pixelSize(of: data) else { return nil }
        let longest = Int(max(size.width, size.height))
        guard let image = cgImage(from: data, maxPixel: min(longest, maxPixel)) else { return nil }
        let hasAlpha = switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
        if hasAlpha, let png = encode(image, as: .png) {
            return InputImage(data: png, mimeType: "image/png", role: role)
        }
        guard let jpeg = encode(image, as: .jpeg, quality: 0.92) else { return nil }
        return InputImage(data: jpeg, mimeType: "image/jpeg", role: role)
    }

    public static func deferredUpload(_ data: Data, maxPixel: Int = 2048, role: String? = nil) -> InputImage? {
        guard pixelSize(of: data) != nil else { return nil }
        var image = InputImage(data: data, mimeType: "image/jpeg", role: role)
        image.uploadMaxPixel = maxPixel
        return image
    }

    @concurrent
    public static func preparedForUpload(_ images: [InputImage]) async -> [InputImage] {
        images.map { image in
            guard let maxPixel = image.uploadMaxPixel else { return image }
            return prepareForUpload(image.data, maxPixel: maxPixel, role: image.role) ?? image
        }
    }

    public static func encode(_ image: CGImage, as type: UTType, quality: Double = 0.95) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    public static func fileExtension(forMimeType mime: String) -> String {
        UTType(mimeType: mime)?.preferredFilenameExtension ?? "png"
    }

    public static func mimeType(forFileExtension ext: String) -> String {
        UTType(filenameExtension: ext)?.preferredMIMEType ?? "image/png"
    }
}
