import AppKit
import CoreGraphics

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func squircle(in rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let center = CGPoint(x: rect.midX, y: rect.midY)
    for step in 0...720 {
        let t = CGFloat(step) / 720 * 2 * .pi
        let cosT = cos(t), sinT = sin(t)
        let x = center.x + a * copysign(pow(abs(cosT), 2 / exponent), cosT)
        let y = center.y + b * copysign(pow(abs(sinT), 2 / exponent), sinT)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func sparkle(center: CGPoint, radius: CGFloat, waist: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let points = [CGPoint(x: center.x, y: center.y + radius), CGPoint(x: center.x + radius, y: center.y),
                  CGPoint(x: center.x, y: center.y - radius), CGPoint(x: center.x - radius, y: center.y)]
    path.move(to: points[0])
    for index in 0..<4 {
        let next = points[(index + 1) % 4]
        path.addQuadCurve(to: next, control: CGPoint(x: center.x + (points[index].x - center.x + next.x - center.x) * waist,
                                                    y: center.y + (points[index].y - center.y + next.y - center.y) * waist))
    }
    path.closeSubpath()
    return path
}

func line() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 182, y: 318))
    p.addCurve(to: CGPoint(x: 300, y: 430), control1: CGPoint(x: 205, y: 405), control2: CGPoint(x: 258, y: 445))
    p.addCurve(to: CGPoint(x: 430, y: 345), control1: CGPoint(x: 350, y: 412), control2: CGPoint(x: 378, y: 340))
    p.addCurve(to: CGPoint(x: 545, y: 430), control1: CGPoint(x: 482, y: 350), control2: CGPoint(x: 512, y: 392))
    p.addCurve(to: CGPoint(x: 655, y: 735), control1: CGPoint(x: 600, y: 492), control2: CGPoint(x: 708, y: 640))
    p.addCurve(to: CGPoint(x: 548, y: 655), control1: CGPoint(x: 615, y: 805), control2: CGPoint(x: 530, y: 735))
    p.addCurve(to: CGPoint(x: 660, y: 505), control1: CGPoint(x: 562, y: 572), control2: CGPoint(x: 605, y: 505))
    p.addCurve(to: CGPoint(x: 880, y: 860), control1: CGPoint(x: 760, y: 505), control2: CGPoint(x: 820, y: 700))
    p.addLine(to: CGPoint(x: 960, y: 1010))
    return p
}

func drawIcon(size: Int) -> CGImage {
    let scale = CGFloat(size) / 1024
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: scale, y: scale)
    context.interpolationQuality = .high
    let stroke: CGFloat = size <= 32 ? 92 : size <= 64 ? 82 : 72

    let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tile = squircle(in: tileRect)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    context.addPath(tile)
    context.setFillColor(color(0x0A120C))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    let night = CGGradient(colorsSpace: space, colors: [color(0x10131A), color(0x0C1A12)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(night, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [color(0xC9F53D, 0.30), color(0xC9F53D, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 900, y: 900), startRadius: 0,
                               endCenter: CGPoint(x: 900, y: 900), endRadius: 460, options: [])
    context.restoreGState()

    let path = line()
    context.saveGState()
    context.addPath(tile)
    context.clip()
    context.addPath(path)
    context.setLineWidth(stroke)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.replacePathWithStrokedPath()
    context.clip()
    let ink = CGGradient(colorsSpace: space, colors: [color(0x4DBA5A), color(0x9BE34A), color(0xD8FA4A)] as CFArray,
                         locations: [0, 0.55, 1])!
    context.drawLinearGradient(ink, start: CGPoint(x: 200, y: 380), end: CGPoint(x: 880, y: 840),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()

    if size > 32 {
        context.saveGState()
        context.addPath(tile)
        context.clip()
        context.setShadow(offset: .zero, blur: 30, color: color(0xEFFF9A, 0.8))
        context.addPath(sparkle(center: CGPoint(x: 345, y: 735), radius: 78, waist: 0.12))
        context.setFillColor(color(0xFBFFE6))
        context.fillPath()
        context.restoreGState()
    }

    context.saveGState()
    context.addPath(tile)
    context.setStrokeColor(color(0xFFFFFF, 0.14))
    context.setLineWidth(4)
    context.strokePath()
    context.restoreGState()

    return context.makeImage()!
}

func png(_ image: CGImage) -> Data {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--preview", arguments.count > 1 {
    try png(drawIcon(size: 1024)).write(to: URL(fileURLWithPath: arguments[1]))
    try png(drawIcon(size: 64)).write(to: URL(fileURLWithPath: arguments[1].replacingOccurrences(of: ".png", with: "-64.png")))
    try png(drawIcon(size: 32)).write(to: URL(fileURLWithPath: arguments[1].replacingOccurrences(of: ".png", with: "-32.png")))
    print("Wrote previews")
} else {
    let output = URL(fileURLWithPath: arguments.first ?? "AppIcon.iconset")
    try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let sizes: [(name: String, pixels: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    for entry in sizes {
        try png(drawIcon(size: entry.pixels)).write(to: output.appendingPathComponent("\(entry.name).png"))
    }
    print("Wrote \(output.path)")
}
