import AppKit
import FreefieldCore
import SwiftUI

struct Stroke: Identifiable, Equatable {
    let id = UUID()
    var points: [CGPoint]
    var width: CGFloat
    var color: NSColor
    var isEraser = false
}

struct TextNote: Identifiable, Equatable {
    let id = UUID()
    var position: CGPoint
    var text: String
    var color: NSColor
}

func fittedRect(for size: CGSize, in container: CGSize) -> CGRect {
    guard size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: container) }
    let scale = min(container.width / size.width, container.height / size.height)
    let fitted = CGSize(width: size.width * scale, height: size.height * scale)
    return CGRect(x: (container.width - fitted.width) / 2, y: (container.height - fitted.height) / 2,
                  width: fitted.width, height: fitted.height)
}

struct DrawingCanvas: View {
    let imageData: Data
    @Binding var strokes: [Stroke]
    @Binding var notes: [TextNote]
    var brushWidth: CGFloat
    var color: NSColor
    var isEraser = false
    var maskMode = false
    var placingText = false
    var onPlaceText: (CGPoint) -> Void = { _ in }

    @State private var current: Stroke?
    @State private var hover: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let size = ImageCoding.pixelSize(of: imageData) ?? CGSize(width: 1, height: 1)
            let rect = fittedRect(for: size, in: proxy.size)
            ZStack(alignment: .topLeading) {
                DataImage(data: imageData, maxPixel: 2048)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)

                Canvas { context, _ in
                    context.translateBy(x: rect.minX, y: rect.minY)
                    var layer = context
                    if maskMode { layer.opacity = 0.55 }
                    layer.drawLayer { inner in
                        for stroke in strokes + (current.map { [$0] } ?? []) {
                            draw(stroke, in: &inner, size: rect.size)
                        }
                    }
                }
                .allowsHitTesting(false)

                ForEach(notes) { note in
                    Text(note.text)
                        .font(.system(size: max(12, rect.width * 0.028), weight: .bold))
                        .foregroundStyle(Color(nsColor: note.color))
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .position(x: rect.minX + note.position.x * rect.width, y: rect.minY + note.position.y * rect.height)
                }

                if let hover, !placingText {
                    let diameter = brushWidth * rect.width
                    Circle()
                        .strokeBorder(.white, lineWidth: 1)
                        .background(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 2))
                        .frame(width: diameter, height: diameter)
                        .position(hover)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(.rect)
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hover = rect.contains(point) ? point : nil
                case .ended: hover = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !placingText else { return }
                        let point = normalize(value.location, in: rect)
                        hover = value.location
                        if current == nil {
                            current = Stroke(points: [point], width: brushWidth, color: color, isEraser: isEraser)
                        } else {
                            current?.points.append(point)
                        }
                    }
                    .onEnded { value in
                        if placingText {
                            if rect.contains(value.location) { onPlaceText(normalize(value.location, in: rect)) }
                            return
                        }
                        if let current { strokes.append(current) }
                        current = nil
                    }
            )
        }
    }

    private func normalize(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: min(max((point.x - rect.minX) / rect.width, 0), 1),
                y: min(max((point.y - rect.minY) / rect.height, 0), 1))
    }

    private func draw(_ stroke: Stroke, in context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        let points = stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        guard let first = points.first else { return }
        path.move(to: first)
        if points.count == 1 {
            path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y + 0.1))
        }
        for point in points.dropFirst() { path.addLine(to: point) }
        let style = StrokeStyle(lineWidth: stroke.width * size.width, lineCap: .round, lineJoin: .round)
        if stroke.isEraser {
            context.blendMode = .clear
            context.stroke(path, with: .color(.black), style: style)
            context.blendMode = .normal
        } else {
            context.stroke(path, with: .color(Color(nsColor: stroke.color)), style: style)
        }
    }
}

enum CanvasRenderer {
    static func annotated(_ data: Data, strokes: [Stroke], notes: [TextNote], tint: NSColor? = nil, alpha: CGFloat = 1) -> Data? {
        guard let base = ImageCoding.cgImage(from: data, maxPixel: 2048) else { return nil }
        let width = base.width, height = base.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        if let overlay = strokeLayer(strokes, width: width, height: height, tint: tint) {
            context.setAlpha(alpha)
            context.draw(overlay, in: CGRect(x: 0, y: 0, width: width, height: height))
            context.setAlpha(1)
        }
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        for note in notes {
            let fontSize = CGFloat(width) * 0.028
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: note.color,
                .strokeColor: NSColor.black.withAlphaComponent(0.6),
                .strokeWidth: -3,
            ]
            let string = NSAttributedString(string: note.text, attributes: attributes)
            let textSize = string.size()
            let point = CGPoint(x: note.position.x * CGFloat(width) - textSize.width / 2,
                                y: (1 - note.position.y) * CGFloat(height) - textSize.height / 2)
            string.draw(at: point)
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return nil }
        return ImageCoding.encode(image, as: .png)
    }

    static func mask(for data: Data, strokes: [Stroke]) -> Data? {
        guard let base = ImageCoding.cgImage(from: data, maxPixel: 2048) else { return nil }
        let width = base.width, height = base.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let overlay = strokeLayer(strokes, width: width, height: height, tint: .white) else { return nil }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(overlay, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }
        return ImageCoding.encode(image, as: .png)
    }

    private static func strokeLayer(_ strokes: [Stroke], width: Int, height: Int, tint: NSColor?) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            let points = stroke.points.map { CGPoint(x: $0.x * CGFloat(width), y: (1 - $0.y) * CGFloat(height)) }
            guard let first = points.first else { continue }
            context.beginPath()
            context.move(to: first)
            if points.count == 1 { context.addLine(to: CGPoint(x: first.x + 0.5, y: first.y + 0.5)) }
            for point in points.dropFirst() { context.addLine(to: point) }
            context.setLineWidth(stroke.width * CGFloat(width))
            if stroke.isEraser {
                context.setBlendMode(.clear)
            } else {
                context.setBlendMode(.normal)
                context.setStrokeColor((tint ?? stroke.color).cgColor)
            }
            context.strokePath()
        }
        return context.makeImage()
    }
}

struct BeforeAfterView: View {
    let before: URL?
    let beforeData: Data?
    let after: URL

    private let aspect: CGFloat?
    @State private var split: CGFloat = 0.5
    @State private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(before: URL, after: URL) {
        self.before = before
        self.beforeData = nil
        self.after = after
        aspect = ImageCoding.pixelSize(at: after).map { $0.width / max($0.height, 1) }
    }

    init(beforeData: Data, after: URL) {
        self.before = nil
        self.beforeData = beforeData
        self.after = after
        aspect = ImageCoding.pixelSize(at: after).map { $0.width / max($0.height, 1) }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Checkerboard()
                    .mask { ThumbnailImage(url: after, maxPixel: 600, contentMode: .fit).frame(width: size.width, height: size.height) }
                    .opacity(0.5)
                ThumbnailImage(url: after, maxPixel: 600, contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                ThumbnailImage(url: after, maxPixel: 2400, contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                ZStack {
                    beforeImage(maxPixel: 600)
                    beforeImage(maxPixel: 2400)
                }
                .frame(width: size.width, height: size.height)
                .mask(alignment: .leading) {
                    Rectangle().frame(width: size.width * split)
                }
                Rectangle()
                    .fill(.white)
                    .frame(width: 2, height: size.height)
                    .shadow(radius: 3)
                    .position(x: size.width * split, y: size.height / 2)
                Image(systemName: "arrow.left.and.right")
                    .font(.caption.weight(.bold))
                    .padding(8)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .position(x: size.width * split, y: size.height / 2)
                HStack {
                    Text(L("Before")).font(.callout.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                        .glassEffect(in: .capsule)
                    Spacer()
                    Text(L("After")).font(.callout.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                        .glassEffect(in: .capsule)
                }
                .padding(10)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .contentShape(.rect)
            .pointerStyle(.columnResize)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let target = min(max(value.location.x / size.width, 0), 1)
                    if isDragging || hypot(value.translation.width, value.translation.height) >= 3 {
                        isDragging = true
                        split = target
                    } else {
                        withAnimation(reduceMotion ? nil : Motion.standard) { split = target }
                    }
                }
                .onEnded { _ in isDragging = false })
        }
        .aspectRatio(aspect, contentMode: .fit)
    }

    @ViewBuilder private func beforeImage(maxPixel: Int) -> some View {
        if let before {
            ThumbnailImage(url: before, maxPixel: maxPixel, contentMode: .fit)
        } else if let beforeData {
            DataImage(data: beforeData, maxPixel: maxPixel, contentMode: .fit)
        }
    }
}

struct Checkerboard: View {
    var square: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let columns = Int(size.width / square) + 1, rows = Int(size.height / square) + 1
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square)),
                                 with: .color(Color(white: 0.82)))
                }
            }
        }
    }
}
