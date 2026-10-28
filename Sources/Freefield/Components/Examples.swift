import FreefieldCore
import SwiftUI

enum Examples {
    struct ToolExample {
        var before: URL?
        var after: URL
        var extra: URL?
        var gallery: [URL] = []

        var aspect: CGFloat? { ImageCoding.pixelSize(at: after).map { $0.width / max($0.height, 1) } }
    }

    private static func url(_ name: String, in folder: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "heic", subdirectory: "Examples/\(folder)")
    }

    private static let appInputs: [String: String] = {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "json", subdirectory: "Examples/apps"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }()

    static func appResult(_ id: String) -> URL? { url(id, in: "apps") }

    static func appInput(_ id: String) -> URL? {
        appInputs[id].flatMap { url($0, in: "inputs") }
    }

    static func ad(_ id: String) -> ToolExample? {
        let gallery = (1...3).compactMap { url("\(id)-after\($0)", in: "ads") }
        guard let after = url("\(id)-after", in: "ads") ?? gallery.first else { return nil }
        return ToolExample(before: url("\(id)-before", in: "ads"), after: after, extra: url("\(id)-extra", in: "ads"), gallery: gallery)
    }

    static func extraLabel(for tool: Tool) -> String? {
        switch tool {
        case .faceSwap: L("Face")
        case .characterSwap: L("Character")
        case .outfitSwap: L("Garment")
        case .product: L("Product")
        default: nil
        }
    }

    static func tool(_ tool: Tool) -> ToolExample? {
        let key = tool.rawValue
        let gallery = (1...3).compactMap { url("\(key)-after\($0)", in: "tools") }
        guard let after = url("\(key)-after", in: "tools") ?? gallery.first else { return nil }
        return ToolExample(before: url("\(key)-before", in: "tools"), after: after,
                           extra: url("\(key)-extra", in: "tools"), gallery: gallery)
    }
}

struct ToolExampleCard: View {
    let example: Examples.ToolExample
    var extraLabel: String?

    private var isComparison: Bool { example.gallery.isEmpty && example.before != nil }

    var body: some View {
        CaptionedPictureLayout(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    title(L("Real example"))
                    Spacer(minLength: 4)
                    hint
                }
                VStack(alignment: .leading, spacing: 2) {
                    title(L("Real example"))
                    hint
                }
            }
            ZStack(alignment: .bottomLeading) {
                Group {
                    if !example.gallery.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(example.gallery, id: \.self) { url in
                                ThumbnailImage(url: url, maxPixel: 600, contentMode: .fill)
                                    .clipShape(.rect(cornerRadius: Radius.thumb))
                            }
                        }
                    } else if let before = example.before {
                        BeforeAfterView(before: before, after: example.after)
                    } else {
                        ThumbnailImage(url: example.after, maxPixel: 1200, contentMode: .fit)
                    }
                }
                .clipShape(.rect(cornerRadius: Radius.tile))
                if let extra = example.extra ?? (example.gallery.isEmpty ? nil : example.before) {
                    VStack(spacing: 3) {
                        ThumbnailImage(url: extra, maxPixel: 200, contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(.rect(cornerRadius: Radius.tile))
                            .overlay(RoundedRectangle(cornerRadius: Radius.tile).strokeBorder(.white, lineWidth: 2))
                            .shadow(radius: 4)
                        if let extraLabel {
                            Text(extraLabel)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .glassEffect(in: .capsule)
                        }
                    }
                    .padding(10)
                    .help(L("Second input used in this example"))
                }
            }
        }
    }

    private func title(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.seal")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var hint: some View {
        if isComparison {
            Text(L("Drag to compare"))
                .fineTextStyle()
                .lineLimit(1)
        }
    }
}

private struct CaptionedPictureLayout: Layout {
    var spacing: CGFloat = 8

    private func sizes(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (caption: CGSize, picture: CGSize) {
        guard subviews.count == 2 else { return (.zero, .zero) }
        let caption = subviews[0], picture = subviews[1]
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 360
        func captionHeight(_ width: CGFloat) -> CGFloat {
            caption.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        func pictureSize(under captionHeight: CGFloat) -> CGSize {
            let height = proposal.height.flatMap { $0.isFinite ? max(0, $0 - captionHeight - spacing) : nil }
            return picture.sizeThatFits(ProposedViewSize(width: width, height: height))
        }
        var height = captionHeight(width)
        var fitted = pictureSize(under: height)
        let narrow = captionHeight(fitted.width)
        if narrow > height {
            height = narrow
            fitted = pictureSize(under: height)
            height = captionHeight(fitted.width)
        }
        return (CGSize(width: fitted.width, height: height), fitted)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (caption, picture) = sizes(proposal, subviews)
        return CGSize(width: picture.width, height: caption.height + spacing + picture.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let (caption, picture) = sizes(proposal, subviews)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(caption))
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + caption.height + spacing), anchor: .topLeading,
                          proposal: ProposedViewSize(picture))
    }
}

struct QuickStyleExample: View {
    let item: AppItem

    var body: some View {
        if let after = Examples.appResult(item.id) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L("Real example made with this style"), systemImage: "checkmark.seal")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Group {
                        if let before = Examples.appInput(item.id) {
                            if Self.sameShape(before, after) {
                                BeforeAfterView(before: before, after: after)
                            } else {
                                HStack(spacing: 10) {
                                    labeled(before, L("Before"))
                                    Image(systemName: "arrow.right").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                                    labeled(after, L("After"))
                                }
                            }
                        } else {
                            ThumbnailImage(url: after, maxPixel: 1200, contentMode: .fit).clipShape(.rect(cornerRadius: Radius.tile))
                        }
                    }
                    .frame(maxHeight: 300)
                }
                .frame(maxWidth: 560, alignment: .leading)
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("How it works")).font(.headline)
                    step(1, item.slots.count == 1 ? L("Add %@.", item.slots[0].label.lowercased())
                         : L("Add %@.", item.slots.map { $0.label.lowercased() }.joined(separator: L(" and "))))
                    if !item.options.isEmpty { step(2, L("Pick a variant (%@…).", item.options.prefix(3).map(L).joined(separator: ", "))) }
                    step(item.options.isEmpty ? 2 : 3, L("Press Generate. Freefield writes the description and keeps your subject recognizable."))
                }
                .frame(maxWidth: 300, alignment: .leading)
                .padding(.top, 24)
            }
        }
    }

    private func labeled(_ url: URL, _ title: String) -> some View {
        LabeledExampleImage(url: url, title: title)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        ExampleStep(number: number, text: text)
    }

    static func sameShape(_ a: URL, _ b: URL) -> Bool {
        guard let first = ImageCoding.pixelSize(at: a), let second = ImageCoding.pixelSize(at: b) else { return false }
        let ratioA = first.width / max(first.height, 1), ratioB = second.width / max(second.height, 1)
        return abs(ratioA - ratioB) / ratioB < 0.04
    }
}

struct LabeledExampleImage: View {
    let url: URL
    let title: String

    var body: some View {
        ThumbnailImage(url: url, maxPixel: 900, contentMode: .fit)
            .clipShape(.rect(cornerRadius: Radius.tile))
            .overlay(alignment: .bottomLeading) {
                Text(title).font(.callout.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                    .glassEffect(in: .capsule).padding(8)
            }
    }
}

struct ExampleStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.08), in: .circle)
            Text(text).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
