import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import FreefieldCore
import ImageIO
import UniformTypeIdentifiers

struct VideoGradeLook: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    var isPalette = false
}

nonisolated struct VideoGradePlan: Sendable {
    var settings: GradeSettings
    var cube: Data?
    var strength: Double
    var grain: Double

    static let cubeSize = 24
}

enum VideoGradeLooks {
    static let defaultLook = "cinematic"
    static let strengths: [String: Double] = ["Subtle": 0.4, "Balanced": 0.7, "Strong": 1]

    static let palettes: [VideoGradeLook] = [
        VideoGradeLook(id: "naturalistic-clean", name: L("Naturalistic clean"), detail: L("true colors, a little more depth"), isPalette: true),
        VideoGradeLook(id: "bleached-warm", name: L("Bleached warm"), detail: L("sunny, washed-out warmth"), isPalette: true),
        VideoGradeLook(id: "hyper-neon", name: L("Hyper neon"), detail: L("electric pinks and blues"), isPalette: true),
        VideoGradeLook(id: "teal-orange-epic", name: L("Teal and orange"), detail: L("blockbuster blue shadows, warm skin"), isPalette: true),
        VideoGradeLook(id: "sodium-decay", name: L("Sodium streetlight"), detail: L("orange night light, gritty"), isPalette: true),
        VideoGradeLook(id: "cold-steel", name: L("Cold steel"), detail: L("cool, hard and muted"), isPalette: true),
        VideoGradeLook(id: "bleach-bypass", name: L("Silver film"), detail: L("low color, strong contrast"), isPalette: true),
        VideoGradeLook(id: "classic-bw", name: L("Classic black and white"), detail: L("clean, deep grays"), isPalette: true),
        VideoGradeLook(id: "film-colors", name: L("Film colors"), detail: L("soft film stock with gentle grain"), isPalette: true),
        VideoGradeLook(id: "black-gloss", name: L("Black gloss"), detail: L("deep blacks, shiny lights"), isPalette: true),
        VideoGradeLook(id: "candy-pink", name: L("Candy pink"), detail: L("sweet pink tones"), isPalette: true),
        VideoGradeLook(id: "lime-jam", name: L("Lime jam"), detail: L("fresh yellow-green tones"), isPalette: true),
        VideoGradeLook(id: "nostalgic-blue", name: L("Nostalgic blue"), detail: L("faded, with blue shadows"), isPalette: true),
    ]

    static let photoLooks: [VideoGradeLook] = GradeLook.all.filter { $0.id != "none" }
        .map { VideoGradeLook(id: $0.id, name: $0.name, detail: $0.detail) }

    static let all: [VideoGradeLook] = photoLooks + palettes

    static func look(_ id: String) -> VideoGradeLook? { all.first { $0.id == id } }

    static func plan(look id: String, strength label: String) -> VideoGradePlan {
        var settings = GradeSettings()
        if let photo = GradeLook.all.first(where: { $0.id == id }) {
            photo.apply(to: &settings)
        } else {
            settings = paletteSettings(id)
        }
        let grain = settings.grain
        settings.grain = 0
        return VideoGradePlan(settings: settings, cube: paletteCube(id), strength: strengths[label] ?? 1, grain: grain)
    }

    private static func paletteSettings(_ id: String) -> GradeSettings {
        var s = GradeSettings(look: id)
        switch id {
        case "naturalistic-clean": s.contrast = 0.08; s.saturation = 0.05; s.shadows = 0.1
        case "bleached-warm": s.temperature = 0.2; s.contrast = -0.05
        case "hyper-neon": s.saturation = 0.45; s.contrast = 0.2; s.bloom = 0.2
        case "teal-orange-epic": s.contrast = 0.18; s.vignette = 0.25
        case "sodium-decay": s.contrast = 0.15; s.saturation = -0.1; s.grain = 0.25; s.vignette = 0.2
        case "cold-steel": s.contrast = 0.15; s.temperature = -0.3; s.saturation = -0.1
        case "bleach-bypass": s.contrast = 0.3; s.sharpness = 0.2
        case "classic-bw": s.contrast = 0.15
        case "film-colors": s.grain = 0.2; s.halation = 0.1
        case "black-gloss": s.contrast = 0.2; s.saturation = -0.15; s.bloom = 0.15
        case "candy-pink": s.saturation = 0.1; s.contrast = -0.05; s.bloom = 0.1
        case "lime-jam": s.saturation = 0.15; s.contrast = 0.05
        case "nostalgic-blue": s.contrast = -0.1; s.grain = 0.15
        default: break
        }
        return s
    }

    private static func luma(_ r: Float, _ g: Float, _ b: Float) -> Float { 0.3 * r + 0.59 * g + 0.11 * b }

    private static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

    private static func curve(_ x: Float) -> Float { x * x * (3 - 2 * x) }

    private static func transform(_ id: String) -> ((Float, Float, Float) -> (Float, Float, Float))? {
        switch id {
        case "bleached-warm":
            return { r, g, b in
                let l = luma(r, g, b)
                return (0.04 + mix(r, l, 0.35) * 0.96 + 0.03, 0.04 + mix(g, l, 0.35) * 0.95, 0.03 + mix(b, l, 0.35) * 0.88)
            }
        case "hyper-neon":
            return { r, g, b in
                let l = luma(r, g, b)
                let shadow = max(0, 1 - l * 2), highlight = max(0, l * 2 - 1)
                return (r + shadow * 0.08, g + highlight * 0.05 - shadow * 0.03, b + shadow * 0.16 + highlight * 0.06)
            }
        case "teal-orange-epic":
            return { r, g, b in
                let l = luma(r, g, b)
                let shadow = max(0, 1 - l * 2), highlight = max(0, l * 2 - 1)
                return (r - shadow * 0.1 + highlight * 0.1, g + shadow * 0.04 + highlight * 0.03, b + shadow * 0.12 - highlight * 0.1)
            }
        case "sodium-decay":
            return { r, g, b in
                let l = luma(r, g, b)
                let shadow = max(0, 1 - l * 2)
                return (r * 0.95 + 0.06, g * 0.84 + 0.04 + shadow * 0.02, b * 0.55)
            }
        case "cold-steel":
            return { r, g, b in
                let l = luma(r, g, b)
                return (mix(r, l, 0.4) - 0.03, mix(g, l, 0.4), mix(b, l, 0.4) + 0.06)
            }
        case "bleach-bypass":
            return { r, g, b in
                let l = luma(r, g, b)
                return (curve(mix(r, l, 0.45)), curve(mix(g, l, 0.45)), curve(mix(b, l, 0.45)))
            }
        case "classic-bw":
            return { r, g, b in
                let l = curve(luma(r, g, b))
                return (l, l, l)
            }
        case "film-colors":
            return { r, g, b in
                (0.04 + r * 0.93, 0.05 + g * 0.9, 0.06 + b * 0.85)
            }
        case "black-gloss":
            return { r, g, b in
                func crush(_ x: Float) -> Float { pow(max(0, (x - 0.06) / 0.94), 1.15) }
                return (crush(r), crush(g), crush(b))
            }
        case "candy-pink":
            return { r, g, b in
                let l = luma(r, g, b)
                return (r + 0.06 + l * 0.02, g - 0.02, b + 0.04)
            }
        case "lime-jam":
            return { r, g, b in
                let l = luma(r, g, b)
                let mid = 1 - abs(l * 2 - 1)
                return (r + mid * 0.02, g + mid * 0.06, b - mid * 0.06)
            }
        case "nostalgic-blue":
            return { r, g, b in
                let l = luma(r, g, b)
                let shadow = max(0, 1 - l * 2)
                return (0.06 + mix(r, l, 0.2) * 0.9, 0.06 + mix(g, l, 0.2) * 0.9, 0.08 + mix(b, l, 0.2) * 0.88 + shadow * 0.1)
            }
        default:
            return nil
        }
    }

    private static func paletteCube(_ id: String) -> Data? {
        guard let transform = transform(id) else { return nil }
        let size = VideoGradePlan.cubeSize
        var values = [Float](repeating: 0, count: size * size * size * 4)
        var offset = 0
        for blue in 0..<size {
            for green in 0..<size {
                for red in 0..<size {
                    let (r, g, b) = transform(Float(red) / Float(size - 1), Float(green) / Float(size - 1), Float(blue) / Float(size - 1))
                    values[offset] = min(max(r, 0), 1)
                    values[offset + 1] = min(max(g, 0), 1)
                    values[offset + 2] = min(max(b, 0), 1)
                    values[offset + 3] = 1
                    offset += 4
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

nonisolated enum VideoGrade {
    static func render(_ input: CIImage, plan: VideoGradePlan, seconds: Double) -> CIImage {
        let extent = input.extent
        var image = input
        if let cube = plan.cube {
            let filter = CIFilter.colorCubeWithColorSpace()
            filter.inputImage = image
            filter.cubeDimension = Float(VideoGradePlan.cubeSize)
            filter.cubeData = cube
            filter.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            image = filter.outputImage ?? image
        }
        image = GradeRenderer.render(image, plan.settings)
        if plan.grain > 0 { image = addGrain(image, amount: plan.grain, seconds: seconds) }
        if plan.strength < 1 {
            let blend = CIFilter.dissolveTransition()
            blend.inputImage = input
            blend.targetImage = image
            blend.time = Float(plan.strength)
            image = blend.outputImage ?? image
        }
        return image.cropped(to: extent)
    }

    private static func addGrain(_ image: CIImage, amount grain: Double, seconds: Double) -> CIImage {
        let extent = image.extent
        guard let noise = CIFilter.randomGenerator().outputImage else { return image }
        let frame = (seconds * 24).rounded()
        let shift = CGAffineTransform(translationX: CGFloat(frame.truncatingRemainder(dividingBy: 97) * 37),
                                      y: CGFloat(frame.truncatingRemainder(dividingBy: 89) * 53))
        let moved = noise.transformed(by: shift.scaledBy(x: 1.4, y: 1.4)).cropped(to: extent)
        let mono = CIFilter.colorMatrix()
        mono.inputImage = moved
        let amount = CGFloat(grain) * 0.22
        mono.rVector = CIVector(x: amount, y: 0, z: 0, w: 0)
        mono.gVector = CIVector(x: amount, y: 0, z: 0, w: 0)
        mono.bVector = CIVector(x: amount, y: 0, z: 0, w: 0)
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        mono.biasVector = CIVector(x: -amount / 2, y: -amount / 2, z: -amount / 2, w: 0)
        let blend = CIFilter.additionCompositing()
        blend.inputImage = mono.outputImage
        blend.backgroundImage = image
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    @concurrent
    static func apply(_ url: URL, plan: VideoGradePlan) async throws -> URL {
        try await VideoMedia.grade(url, timedFilter: { image, seconds in render(image, plan: plan, seconds: seconds) })
    }

    @concurrent
    static func previews(frame: Data, plans: [(id: String, plan: VideoGradePlan)], strength: String, folder: URL,
                         maxPixel: Int) async -> [String: URL] {
        guard let source = ImageCoding.cgImage(from: frame, maxPixel: maxPixel) else { return [:] }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        let input = CIImage(cgImage: source)
        var urls: [String: URL] = [:]
        for (look, plan) in plans {
            if Task.isCancelled { break }
            let target = folder.appendingPathComponent("\(look)-\(strength).jpg")
            if FileManager.default.fileExists(atPath: target.path) {
                urls[look] = target
                continue
            }
            let output = render(input, plan: plan, seconds: 0)
            guard let image = context.createCGImage(output, from: output.extent),
                  let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            if CGImageDestinationFinalize(destination) { urls[look] = target }
        }
        return urls
    }
}
