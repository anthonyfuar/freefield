import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let screenshot = NSImage(contentsOfFile: arguments[1]),
      let icon = NSImage(contentsOfFile: "Assets/AppIcon.icns") else {
    FileHandle.standardError.write(Data("usage: swift scripts/assets/make-social-preview.swift <screenshot.png> <out.png> (run from the repo root)\n".utf8))
    exit(1)
}

let size = NSSize(width: 1280, height: 640)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let background = NSGradient(colors: [NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 1),
                                     NSColor(srgbRed: 0.05, green: 0.10, blue: 0.07, alpha: 1)])!
background.draw(in: NSRect(origin: .zero, size: size), angle: -30)
let glow = NSGradient(colors: [NSColor(srgbRed: 0.79, green: 0.96, blue: 0.24, alpha: 0.16), .clear])!
glow.draw(fromCenter: NSPoint(x: 1050, y: 600), radius: 0, toCenter: NSPoint(x: 1050, y: 600), radius: 620, options: [])

icon.draw(in: NSRect(x: 56, y: 440, width: 128, height: 128))
func line(_ string: String, _ font: NSFont, _ color: NSColor, at point: NSPoint, kern: CGFloat = 0) {
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern]).draw(at: point)
}
line("Freefield", .systemFont(ofSize: 64, weight: .bold), .white, at: NSPoint(x: 60, y: 350), kern: -1.2)
line("No plans. No credits. No limits.", .systemFont(ofSize: 28, weight: .semibold),
     NSColor(srgbRed: 0.85, green: 0.98, blue: 0.29, alpha: 1), at: NSPoint(x: 64, y: 302))
let style = NSMutableParagraphStyle()
style.lineSpacing = 5
NSAttributedString(string: "50+ AI tools for images, video and ads on your Mac. Bring your own API key and pay only for what you make.",
                   attributes: [.font: NSFont.systemFont(ofSize: 21, weight: .regular), .foregroundColor: NSColor(white: 0.78, alpha: 1),
                                .paragraphStyle: style])
    .draw(in: NSRect(x: 64, y: 196, width: 520, height: 80))
let facts = ["50+ tools", "Your own key", "Pay per use"]
var x: CGFloat = 64
for fact in facts {
    let font = NSFont.systemFont(ofSize: 17, weight: .semibold)
    let width = (fact as NSString).size(withAttributes: [.font: font]).width + 32
    let pill = NSBezierPath(roundedRect: NSRect(x: x, y: 76, width: width, height: 38), xRadius: 19, yRadius: 19)
    NSColor(white: 1, alpha: 0.08).setFill()
    pill.fill()
    NSColor(white: 1, alpha: 0.14).setStroke()
    pill.lineWidth = 1
    pill.stroke()
    (fact as NSString).draw(at: NSPoint(x: x + 16, y: 85), withAttributes: [.font: font, .foregroundColor: NSColor(white: 0.92, alpha: 1)])
    x += width + 12
}

let frame = NSRect(x: 640, y: 70, width: 760, height: 760 * screenshot.size.height / screenshot.size.width)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.6)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -16)
shadow.set()
let window = NSBezierPath(roundedRect: frame, xRadius: 18, yRadius: 18)
NSColor.black.setFill()
window.fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
window.addClip()
screenshot.draw(in: frame)
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
print("Wrote \(arguments[2])")
