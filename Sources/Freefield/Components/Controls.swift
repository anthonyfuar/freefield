import AppKit
import FreefieldCore
import SwiftUI

extension Color {
    static let brand = Color(nsColor: NSColor(name: "FreefieldBrand") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.42, green: 0.80, blue: 0.33, alpha: 1)
            : NSColor(srgbRed: 0.20, green: 0.58, blue: 0.27, alpha: 1)
    })

    static let brandFill = Color(nsColor: NSColor(name: "FreefieldBrandFill") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.20, green: 0.62, blue: 0.30, alpha: 1)
            : NSColor(srgbRed: 0.20, green: 0.58, blue: 0.27, alpha: 1)
    })

    static var appAccent: Color { .accentColor }
}

enum Motion {
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static var press: Animation { .snappy(duration: 0.12) }
    static var select: Animation { reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.18) }
    static var standard: Animation { reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.25) }
    static var emphasized: Animation { reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.35) }
    static var fade: Animation { .easeOut(duration: 0.15) }

    static func transition(_ transition: AnyTransition) -> AnyTransition {
        reduceMotion ? .opacity : transition
    }
}

enum Radius {
    static let small: CGFloat = 4
    static let thumb: CGFloat = 8
    static let tile: CGFloat = 14
    static let card: CGFloat = 18
    static let panel: CGFloat = 24
}

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum IconScale {
    static let small: CGFloat = 13
    static let medium: CGFloat = 19
    static let large: CGFloat = 25
    static let hero: CGFloat = 30
    static let weight: Font.Weight = .medium
}

extension Image {
    func iconSymbol(_ size: CGFloat) -> some View {
        font(.system(size: size, weight: IconScale.weight)).symbolRenderingMode(.hierarchical)
    }
}

struct IconTile: View {
    enum Size {
        case small
        case medium
        case large

        var side: CGFloat {
            switch self {
            case .small: 28
            case .medium: 42
            case .large: 56
            }
        }

        var glyph: CGFloat {
            switch self {
            case .small: IconScale.small
            case .medium: IconScale.medium
            case .large: IconScale.large
            }
        }

        var radius: CGFloat {
            switch self {
            case .small: Radius.thumb
            case .medium: Radius.tile
            case .large: Radius.card
            }
        }
    }

    let symbol: String
    var size: Size = .medium

    var body: some View {
        Image(systemName: symbol)
            .iconSymbol(size.glyph)
            .foregroundStyle(Color.brand)
            .frame(width: size.side, height: size.side)
            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: size.radius))
            .overlay(RoundedRectangle(cornerRadius: size.radius).strokeBorder(Color.primary.opacity(0.08)))
            .accessibilityHidden(true)
    }
}

struct IconPlaceholder: View {
    let symbol: String
    var size: IconTile.Size = .large

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.04))
            .overlay { IconTile(symbol: symbol, size: size) }
    }
}

extension View {
    func displayTitleStyle() -> some View { font(.system(size: 32, weight: .bold)).tracking(-0.5) }
    func pageTitleStyle() -> some View { font(.largeTitle.bold()).tracking(-0.3) }
    func toolTitleStyle() -> some View { font(.title.bold()).tracking(-0.2) }
    func sectionTitleStyle() -> some View { font(.title3.weight(.semibold)) }
    func stepTitleStyle() -> some View { font(.title3.weight(.semibold)) }
    func groupTitleStyle() -> some View { font(.body.weight(.medium)).foregroundStyle(.secondary) }
    func helperTextStyle() -> some View { font(.callout).foregroundStyle(.secondary) }
    func fineTextStyle() -> some View { font(.subheadline).foregroundStyle(.secondary) }
}

enum FamilyStyle {
    static func color(_ family: String) -> Color {
        switch family {
        case "photo": .teal
        case "people": .orange
        case "video": .purple
        case "videoEdit": .pink
        case "productPhotos": .indigo
        case "ads": .red
        default: .brandFill
        }
    }

    static func tile(symbol: String, family: String, side: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: side * 0.48, weight: IconScale.weight))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.brand)
            .frame(width: side, height: side)
            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: side * 0.28))
            .overlay(RoundedRectangle(cornerRadius: side * 0.28).strokeBorder(Color.primary.opacity(0.08)))
            .accessibilityHidden(true)
    }
}

struct CardButtonStyle: ButtonStyle {
    var isCompact = false
    var shadow = true

    func makeBody(configuration: Configuration) -> some View {
        CardButtonBody(configuration: configuration, isCompact: isCompact, shadow: shadow)
    }

    private struct CardButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let isCompact: Bool
        let shadow: Bool
        @State private var isHovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let hovering = isHovering && isEnabled
            configuration.label
                .scaleEffect(configuration.isPressed ? (isCompact ? 0.97 : 0.985) : hovering && !reduceMotion ? 1.015 : 1)
                .shadow(color: .black.opacity(shadow ? (hovering ? 0.18 : 0.06) : 0), radius: hovering ? 12 : 4, y: hovering ? 6 : 2)
                .animation(configuration.isPressed ? Motion.press : Motion.select, value: configuration.isPressed)
                .animation(Motion.select, value: hovering)
                .onHover { isHovering = $0 }
        }
    }
}

struct ConfirmationCapsule: View {
    let text: String
    @Binding var isShown: Bool

    var body: some View {
        ZStack {
            if isShown {
                Label(text, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .symbolEffect(.bounce, value: isShown)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.asymmetric(insertion: Motion.transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom))),
                                            removal: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(1.8))
                        withAnimation(Motion.fade) { isShown = false }
                    }
            }
        }
        .animation(Motion.standard, value: isShown)
    }
}

struct ChipMenu<Content: View>: View {
    let systemImage: String
    let title: String
    var help: String = ""
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .controlSize(.regular)
        .fixedSize()
        .help(help)
    }
}

struct AspectGlyph: View {
    let ratio: AspectRatio
    var size: CGFloat = 14

    var body: some View {
        let value = ratio.ratio
        let width = value >= 1 ? size : size * value
        let height = value >= 1 ? size / value : size
        RoundedRectangle(cornerRadius: Radius.small)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: ratio == .auto ? [2, 2] : []))
            .frame(width: width, height: height)
            .frame(width: size, height: size)
    }
}

struct AspectRatioMenu: View {
    @Binding var selection: AspectRatio
    let available: [AspectRatio]
    var autoTitle = L("Shape: auto")

    var body: some View {
        ChipMenu(systemImage: "aspectratio", title: selection == .auto ? autoTitle : L("Shape: %@", selection.label),
                 help: L("Image aspect ratio")) {
            Picker(L("Aspect Ratio"), selection: $selection) {
                ForEach(available) { ratio in
                    Label {
                        Text("\(ratio.label)  ·  \(ratio.usage)")
                    } icon: {
                        Image(nsImage: AspectGlyphRenderer.image(for: ratio))
                    }
                    .tag(ratio)
                }
            }
            .pickerStyle(.inline)
        }
    }
}

enum AspectGlyphRenderer {
    static func image(for ratio: AspectRatio) -> NSImage {
        let size: CGFloat = 16
        let value = ratio.ratio
        let width = value >= 1 ? size - 2 : (size - 2) * value
        let height = value >= 1 ? (size - 2) / value : size - 2
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let rect = NSRect(x: (size - width) / 2, y: (size - height) / 2, width: width, height: height)
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.7, dy: 0.7), xRadius: 2, yRadius: 2)
            path.lineWidth = 1.4
            if ratio == .auto { path.setLineDash([2, 2], count: 2, phase: 0) }
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct ResolutionMenu: View {
    @Binding var selection: Resolution
    let available: [Resolution]

    var body: some View {
        ChipMenu(systemImage: "square.resize", title: L("Size: %@", selection.rawValue), help: L("Output resolution")) {
            Picker(L("Resolution"), selection: $selection) {
                ForEach(available) { resolution in
                    Text("\(resolution.rawValue)  ·  \(resolution.detail)").tag(resolution)
                }
            }
            .pickerStyle(.inline)
        }
    }
}

struct CountMenu: View {
    @Binding var count: Int
    var maximum = 4

    var body: some View {
        ChipMenu(systemImage: "square.grid.2x2", title: count == 1 ? L("1 image") : L("%ld images", count),
                 help: L("How many images to generate")) {
            Picker(L("Images"), selection: $count) {
                ForEach(1...maximum, id: \.self) { value in
                    Text(value == 1 ? L("1 image") : L("%ld images", value)).tag(value)
                }
            }
            .pickerStyle(.inline)
        }
    }
}

struct QualityMenu: View {
    @Binding var selection: String
    let available: [String]

    static func label(_ value: String) -> String {
        switch value {
        case "auto": L("Auto")
        case "low": L("Low")
        case "medium": L("Medium quality")
        case "high": L("High")
        case "xhigh": L("Very High")
        case "max": L("Maximum")
        default: value.capitalized
        }
    }

    var body: some View {
        ChipMenu(systemImage: "dial.medium", title: L("Quality: %@", Self.label(selection).localizedLowercase),
                 help: L("Quality (affects cost)")) {
            Picker(L("Quality"), selection: $selection) {
                ForEach(available, id: \.self) { Text(Self.label($0)).tag($0) }
            }
            .pickerStyle(.inline)
        }
    }
}

struct PromptField: View {
    @Binding var text: String
    var placeholder: String
    var minLines = 2
    var maxLines = 7
    var focusOnAppear = true
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .lineLimit(minLines...maxLines)
            .focused($focused)
            .onKeyPress(.return, phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                onSubmit()
                return .handled
            }
            .onAppear { if focusOnAppear { focused = true } }
            .boxedField(isFocused: focused) { focused = true }
    }
}

struct InputBox: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .focused($isFocused)
            .boxedField(isFocused: isFocused) { isFocused = true }
    }
}

extension View {
    func inputBox() -> some View { modifier(InputBox()) }

    func boxedField(isFocused: Bool, focus: @escaping () -> Void) -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isFocused ? Color.appAccent : Color.primary.opacity(0.28), lineWidth: isFocused ? 1.5 : 1)
            }
            .contentShape(.rect)
            .onTapGesture(perform: focus)
            .animation(Motion.select, value: isFocused)
    }
}

struct GenerateButton: View {
    var title = L("Generate")
    let isEnabled: Bool
    var disabledReason: String?
    var estimatedCost: Double?
    var costLabel: String?
    var isWorking = false
    var size: ControlSize = .large
    let action: () -> Void

    private var price: String? { estimatedCost.map(Self.format) ?? costLabel }

    var body: some View {
        Button(action: action) {
            label(isReady: true)
                .prominentLabel()
        }
        .buttonStyle(.glassProminent)
        .tint(.brandFill)
        .controlSize(size)
        .disabled(!isEnabled)
        .keyboardShortcut(.return, modifiers: .command)
        .opacity(isEnabled ? 1 : 0)
        .accessibilityHidden(!isEnabled)
        .help(isEnabled ? L("Generate (⌘↩)") : "")
        .overlay {
            if !isEnabled {
                label(isReady: false)
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassEffect(.regular, in: .capsule)
                    .contentShape(.capsule)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityValue(L("Not ready yet"))
                    .help(disabledReason ?? "")
                    .transition(.opacity)
            }
        }
        .animation(Motion.standard, value: estimatedCost)
        .animation(Motion.fade, value: isEnabled)
    }

    private func label(isReady: Bool) -> some View {
        HStack(spacing: 8) {
            if isWorking {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "sparkles")
            }
            Text(title).font(size == .extraLarge ? .title3.weight(.semibold) : .body.weight(.semibold))
            if let price {
                Text(price)
                    .contentTransition(.numericText())
                    .font(.subheadline.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isReady ? Color.white.opacity(0.18) : Color.primary.opacity(0.08), in: .capsule)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 22)
        .fixedSize(horizontal: true, vertical: false)
    }

    static func format(_ cost: Double) -> String {
        "≈\u{00A0}" + (cost < 0.01 ? "<" + AppModel.money(0.01, decimals: 2) : AppModel.money(cost, decimals: 2))
    }
}

struct PanelSection<Content: View>: View {
    let title: String
    var systemImage: String?
    var trailing: AnyView?
    var step: Int?
    var isDone = false
    var isOptional = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let step {
                    StepBadge(number: step, isDone: isDone)
                } else if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(.secondary)
                }
                if step == nil {
                    Text(title).groupTitleStyle()
                } else {
                    Text(title).stepTitleStyle()
                }
                if isOptional { OptionalTag() }
                Spacer()
                trailing
            }
            content()
        }
    }
}

struct StepBadge: View {
    let number: Int
    var isDone = false

    var body: some View {
        ZStack {
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .transition(Motion.transition(.scale(scale: 0.5).combined(with: .opacity)))
            } else {
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 24, height: 24)
        .background(Color.brandFill, in: .circle)
        .animation(Motion.select, value: isDone)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isDone ? L("Step %ld, done", number) : L("Step %ld", number))
    }
}

struct OptionalTag: View {
    var body: some View {
        Text(L("Optional"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.08), in: .capsule)
            .fixedSize()
    }
}

struct ExtrasHeader: View {
    var topPadding: CGFloat = Spacing.xxl

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Divider().opacity(0.5)
            Text(L("Extras (optional)"))
                .groupTitleStyle()
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, topPadding)
        .padding(.bottom, Spacing.m)
    }
}

struct PricePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.08), in: .capsule)
            .fixedSize()
    }
}

struct OptionTile: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var picture: OptionPicture?
    let isSelected: Bool
    var isMultiSelect = false
    var compact = false
    let action: () -> Void

    private var parts: (title: String, subtitle: String?) {
        if subtitle == nil, title.hasSuffix(")"), let open = title.range(of: " (") {
            let detail = title[open.upperBound..<title.index(before: title.endIndex)]
            return (Self.capitalized(String(title[..<open.lowerBound])), Self.capitalized(String(detail)))
        }
        return (Self.capitalized(title), subtitle)
    }

    static func capitalized(_ text: String) -> String {
        guard let first = text.first, first.isLowercase else { return text }
        return first.uppercased() + text.dropFirst()
    }

    var body: some View {
        if let picture {
            Button(action: action) { pictureCard(picture) }
                .buttonStyle(CardButtonStyle(isCompact: compact, shadow: false))
                .animation(Motion.select, value: isSelected)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            plainTile
        }
    }

    private func pictureCard(_ picture: OptionPicture) -> some View {
        let parts = parts
        return VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(picture.aspect, contentMode: .fit)
                .overlay { pictureContent(picture) }
                .clipped()
                .overlay(alignment: .topTrailing) { pictureMark }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(parts.title)
                    .font(compact ? .callout.weight(.semibold) : .body.weight(.semibold))
                    .lineLimit(2)
                if let detail = parts.subtitle {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.top, compact ? 6 : 8)
            .padding(.bottom, compact ? 7 : 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isSelected ? Color.appAccent.opacity(0.14) : Color.primary.opacity(0.05))
        .clipShape(.rect(cornerRadius: Radius.tile))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.tile)
                .strokeBorder(isSelected ? Color.appAccent : .primary.opacity(0.08), lineWidth: isSelected ? 2.5 : 1)
        }
        .contentShape(.rect(cornerRadius: Radius.tile))
    }

    @ViewBuilder private func pictureContent(_ picture: OptionPicture) -> some View {
        if let url = picture.url {
            ThumbnailImage(url: url, maxPixel: 360, contentMode: .fill)
        } else {
            IconPlaceholder(symbol: systemImage ?? "circle.dashed", size: compact ? .small : .medium)
        }
    }

    @ViewBuilder private var pictureMark: some View {
        if isSelected || isMultiSelect {
            ZStack {
                Circle().fill(isSelected ? Color.appAccent : .black.opacity(0.28))
                Circle().strokeBorder(.white, lineWidth: 1.5)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: compact ? 8 : 10, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: compact ? 16 : 20, height: compact ? 16 : 20)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .padding(compact ? 5 : 7)
            .transition(Motion.transition(.scale(scale: 0.8).combined(with: .opacity)))
        }
    }

    private var plainTile: some View {
        let parts = parts
        return Button(action: action) {
            Group {
                if compact {
                    HStack(spacing: 6) {
                        if let systemImage {
                            Image(systemName: systemImage)
                                .font(.callout.weight(IconScale.weight))
                                .symbolRenderingMode(.hierarchical)
                        }
                        Text(parts.title).font(.callout.weight(.medium)).lineLimit(1)
                        if isSelected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(isSelected ? Color.appAccent.opacity(0.16) : Color.primary.opacity(0.05), in: .capsule)
                    .overlay {
                        Capsule().strokeBorder(isSelected ? Color.appAccent : .primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
                    }
                    .contentShape(.capsule)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        if let systemImage {
                            Image(systemName: systemImage)
                                .iconSymbol(IconScale.medium)
                                .foregroundStyle(isSelected ? Color.appAccent : Color.secondary)
                                .frame(height: 24)
                        }
                        Text(parts.title).font(.body.weight(.semibold)).lineLimit(2)
                        if let detail = parts.subtitle {
                            Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: systemImage == nil ? 36 : 84, alignment: .topLeading)
                    .padding(12)
                    .background(isSelected ? Color.appAccent.opacity(0.14) : Color.primary.opacity(0.05), in: .rect(cornerRadius: Radius.tile))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.tile)
                            .strokeBorder(isSelected ? Color.appAccent : .primary.opacity(0.08), lineWidth: isSelected ? 2.5 : 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected || isMultiSelect {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.body)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(isSelected ? Color.white : Color.secondary, isSelected ? Color.appAccent : Color.clear)
                                .padding(7)
                                .transition(Motion.transition(.scale(scale: 0.8).combined(with: .opacity)))
                        }
                    }
                    .contentShape(.rect(cornerRadius: Radius.tile))
                }
            }
        }
        .buttonStyle(PressableStyle())
        .animation(Motion.select, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

struct ChoiceChips: View {
    let values: [String]
    var label: (String) -> String = { L($0) }
    var symbol: (String) -> String? = { _ in nil }
    var pictures: [String: OptionPicture]?
    let isSelected: (String) -> Bool
    let onSelect: (String) -> Void

    var body: some View {
        if let pictures {
            OptionGrid(minimum: 120) {
                ForEach(values, id: \.self) { value in
                    OptionTile(title: label(value), systemImage: symbol(value), picture: pictures[value],
                               isSelected: isSelected(value), compact: true) {
                        onSelect(value)
                    }
                }
            }
        } else {
            FlowLayout(spacing: 6) {
                ForEach(values, id: \.self) { value in
                    OptionTile(title: label(value), systemImage: symbol(value), isSelected: isSelected(value), compact: true) {
                        onSelect(value)
                    }
                }
            }
        }
    }
}

struct OptionGrid: Layout {
    var columns: Int?
    var minimum: CGFloat = 160
    var spacing: CGFloat = 10
    var stretchesLastRow = false

    struct Row { var range: Range<Int>; var height: CGFloat; var column: CGFloat }

    struct Cache {
        var width: CGFloat = -1
        var column: CGFloat = 0
        var rows: [Row] = []
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }

    static func columnCount(width: CGFloat, columns: Int?, minimum: CGFloat, spacing: CGFloat = 10) -> Int {
        if let columns { return max(1, columns) }
        return max(1, Int((width + spacing) / (minimum + spacing)))
    }

    private func layout(width: CGFloat, subviews: Subviews, cache: inout Cache) -> (column: CGFloat, rows: [Row]) {
        if cache.width == width { return (cache.column, cache.rows) }
        let count = Self.columnCount(width: width, columns: columns, minimum: minimum, spacing: spacing)
        let column = max(0, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
        let proposal = ProposedViewSize(width: column, height: nil)
        var rows: [Row] = []
        var start = 0
        while start < subviews.count {
            let end = min(start + count, subviews.count)
            let items = end - start
            let rowColumn = stretchesLastRow && items < count
                ? max(0, (width - spacing * CGFloat(items - 1)) / CGFloat(items)) : column
            let rowProposal = rowColumn == column ? proposal : ProposedViewSize(width: rowColumn, height: nil)
            let height = subviews[start..<end].map { $0.sizeThatFits(rowProposal).height }.max() ?? 0
            rows.append(Row(range: start..<end, height: height, column: rowColumn))
            start = end
        }
        cache = Cache(width: width, column: column, rows: rows)
        return (column, rows)
    }

    private func resolvedWidth(_ proposal: ProposedViewSize) -> CGFloat {
        if let width = proposal.width, width.isFinite { return width }
        let count = CGFloat(columns ?? 2)
        return minimum * count + spacing * (count - 1)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = resolvedWidth(proposal)
        let rows = layout(width: width, subviews: subviews, cache: &cache).rows
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let rows = layout(width: bounds.width, subviews: subviews, cache: &cache).rows
        var y = bounds.minY
        for row in rows {
            for (offset, index) in row.range.enumerated() {
                subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(offset) * (row.column + spacing), y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: row.column, height: row.height))
            }
            y += row.height + spacing
        }
    }
}

struct ExpandableOptionGrid<Card: View>: View {
    let values: [String]
    var columns: Int?
    var minimum: CGFloat = 160
    var rows = 2
    var selection: String?
    @ViewBuilder var card: (String) -> Card

    @State private var isExpanded = false
    @State private var width: CGFloat = 0

    var body: some View {
        let perRow = width > 0 ? OptionGrid.columnCount(width: width, columns: columns, minimum: minimum) : 4
        let limit = perRow * rows
        let isLong = values.count > limit + 2
        let selectedIndex = selection.flatMap { values.firstIndex(of: $0) } ?? 0
        let showsAll = !isLong || isExpanded || selectedIndex >= limit
        VStack(alignment: .leading, spacing: 8) {
            OptionGrid(columns: columns, minimum: minimum) {
                ForEach(showsAll ? values : Array(values.prefix(limit)), id: \.self) { card($0) }
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            if isLong, selectedIndex < limit {
                Button {
                    withAnimation(Motion.standard) { isExpanded.toggle() }
                } label: {
                    Label(isExpanded ? L("Show fewer") : L("See all (%ld)", values.count),
                          systemImage: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.callout)
                }
                .buttonStyle(.glass)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var centered = false
    var lineSpacing: CGFloat?

    struct Cache {
        var sizes: [CGSize]
        var width: CGFloat = -1
        var fitted: [CGSize] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let sizes = sizes(width: proposal.width ?? .infinity, subviews: subviews, cache: &cache)
        let rows = rows(width: proposal.width ?? .infinity, sizes: sizes)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + (lineSpacing ?? spacing) * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let sizes = sizes(width: bounds.width, subviews: subviews, cache: &cache)
        var y = bounds.minY
        for row in rows(width: bounds.width, sizes: sizes) {
            var x = bounds.minX + (centered ? max(0, (bounds.width - row.width) / 2) : 0)
            for index in row.indices {
                let size = sizes[index]
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + (lineSpacing ?? spacing)
        }
    }

    private func sizes(width: CGFloat, subviews: Subviews, cache: inout Cache) -> [CGSize] {
        guard width.isFinite, width > 0 else { return cache.sizes }
        if cache.width == width { return cache.fitted }
        let fitted = cache.sizes.indices.map { index in
            let size = cache.sizes[index]
            guard size.width > width else { return size }
            let capped = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            return CGSize(width: min(capped.width, width), height: capped.height)
        }
        cache.width = width
        cache.fitted = fitted
        return fitted
    }

    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(width: CGFloat, sizes: [CGSize]) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, size) in sizes.enumerated() {
            var row = rows[rows.count - 1]
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                rows.append(Row())
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

struct DisabledReasonLabel: View {
    let reason: String?

    static func nextStep(_ what: String) -> String { L("Next step: %@", what) }

    var body: some View {
        if let reason, !reason.isEmpty {
            Label {
                Text(reason)
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .contentTransition(.opacity)
            } icon: {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(Color.brand)
            }
            .font(.callout)
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
            .animation(Motion.fade, value: reason)
            .transition(.opacity)
        }
    }
}

struct PageHeader: View {
    let title: String
    let detail: String
    var isLanding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if isLanding {
                    Text(title).displayTitleStyle()
                } else {
                    Text(title).pageTitleStyle()
                }
            }
            .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: PageLayout.textWidth, alignment: .leading)
        }
    }
}

enum PageLayout {
    static let maxWidth: CGFloat = 1200
    static let textWidth: CGFloat = 640
}

extension View {
    func pageContainer() -> some View {
        padding(24)
            .frame(maxWidth: PageLayout.maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
    }

    func prominentLabel() -> some View { modifier(ProminentLabel()) }
}

private struct ProminentLabel: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        if isEnabled {
            content.foregroundStyle(.white)
        } else {
            content
        }
    }
}

extension View {
    func pinnedActionBar<Bar: View>(maxWidth: CGFloat = .infinity, @ViewBuilder _ bar: () -> Bar) -> some View {
        safeAreaBar(edge: .bottom) {
            bar()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: maxWidth)
                .glassEffect(.regular, in: .rect(cornerRadius: Radius.panel))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }
}

struct ExtraInstructionField: View {
    static let maxWidth: CGFloat = 720

    @Binding var text: String
    var placeholder: String
    var title = L("Your instructions (optional)")
    var caption: String?
    var limit: Int?
    var asStep = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            instructionLabel
                .fixedSize(horizontal: false, vertical: true)
            PromptField(text: $text, placeholder: placeholder, minLines: 2, maxLines: 5, focusOnAppear: false)
                .characterLimit($text, limit ?? 2000)
            if let caption {
                Text(caption).helperTextStyle()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
    }

    @ViewBuilder private var instructionLabel: some View {
        let label = Label(title, systemImage: "text.bubble").labelStyle(TitleOnlyWhen(asStep))
        if asStep {
            label.stepTitleStyle()
        } else {
            label.groupTitleStyle()
        }
    }
}

private struct TitleOnlyWhen: LabelStyle {
    let titleOnly: Bool
    init(_ titleOnly: Bool) { self.titleOnly = titleOnly }

    func makeBody(configuration: Configuration) -> some View {
        if titleOnly {
            configuration.title
        } else {
            Label(configuration)
        }
    }
}

struct OptionalSection<Content: View>: View {
    let title: String
    var systemImage: String?
    var summary: String?
    var isFilled: Bool
    @ViewBuilder var content: () -> Content

    @AppStorage private var isOpen: Bool

    init(_ title: String, systemImage: String? = nil, summary: String? = nil, isFilled: Bool = false, storageKey: String,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.summary = summary
        self.isFilled = isFilled
        self.content = content
        _isOpen = AppStorage(wrappedValue: false, "section.\(storageKey)")
    }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { isOpen }, set: { open in
            withAnimation(Motion.standard) { isOpen = open }
        })) {
            VStack(alignment: .leading, spacing: 16) { content() }
                .padding(.top, 12)
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { titleLabel; summaryText }
                VStack(alignment: .leading, spacing: 2) { titleLabel; summaryText }
            }
        }
        .onAppear { if isFilled { isOpen = true } }
        .onChange(of: isFilled) { _, filled in if filled { isOpen = true } }
    }

    private var titleLabel: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(.secondary)
            }
            Text(title)
                .groupTitleStyle()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var summaryText: some View {
        if !isOpen, let summary, !summary.isEmpty {
            Text(summary)
                .fineTextStyle()
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CollapsibleExample<Content: View>: View {
    let id: String
    var hasResults: Bool
    var hasExample: Bool
    @ViewBuilder var content: () -> Content

    @AppStorage private var override: Int

    init(id: String, hasResults: Bool, hasExample: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.id = id
        self.hasResults = hasResults
        self.hasExample = hasExample
        self.content = content
        _override = AppStorage(wrappedValue: 0, "example.\(id)")
    }

    private var isOpen: Bool { override == 0 ? !hasResults : override == 1 }

    var body: some View {
        if isOpen {
            VStack(alignment: .leading, spacing: 6) {
                content()
                Button(hasExample ? L("Hide example") : L("Hide instructions"), systemImage: "chevron.up") {
                    withAnimation(Motion.standard) { override = 2 }
                }
                .buttonStyle(.borderless)
                .fineTextStyle()
            }
        } else {
            Button {
                withAnimation(Motion.standard) { override = 1 }
            } label: {
                Label(hasExample ? L("See example") : L("See instructions"), systemImage: hasExample ? "play.rectangle" : "list.number")
                    .font(.callout)
            }
            .buttonStyle(.glass)
        }
    }
}

struct RelatedToolHint: View {
    struct Link {
        let title: String
        let action: () -> Void
    }

    var prompt = L("Did you mean…")
    let links: [Link]

    var body: some View {
        let shown = Array(links.prefix(2))
        if !shown.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "arrow.turn.down.right")
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(line(shown))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .environment(\.openURL, OpenURLAction { url in
                if let index = Int(url.host() ?? ""), shown.indices.contains(index) { shown[index].action() }
                return .handled
            })
            .transition(.opacity)
        }
    }

    private func line(_ links: [Link]) -> AttributedString {
        var line = AttributedString(prompt + " ")
        for (index, link) in links.enumerated() {
            if index > 0 { line += AttributedString(" · ") }
            var name = AttributedString(link.title)
            name.link = URL(string: "freefield-hint://\(index)")
            line += name
        }
        return line
    }
}

struct MoreOptionsChip<Content: View>: View {
    var summary: String?
    var help = L("Size, quality and AI model")
    @ViewBuilder var content: () -> Content

    @Environment(AppModel.self) private var app
    @State private var isPresented = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            chip(showsSummary: true)
            chip(showsSummary: false)
        }
        .help(help)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 14) { content() }
                .padding(16)
                .frame(width: 380, alignment: .leading)
                .environment(app)
        }
    }

    private func chip(showsSummary: Bool) -> some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                Text(L("More options"))
                if showsSummary, let summary, !summary.isEmpty {
                    Text(summary).fineTextStyle()
                }
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .buttonStyle(.glass)
        .fixedSize()
    }
}
