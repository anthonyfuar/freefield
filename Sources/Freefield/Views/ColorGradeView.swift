import CoreImage
import CoreImage.CIFilterBuiltins
import FreefieldCore
import SwiftUI

struct GradeSettings: Equatable, Sendable {
    var look = "none"
    var temperature = 0.0
    var tint = 0.0
    var exposure = 0.0
    var contrast = 0.0
    var saturation = 0.0
    var highlights = 0.0
    var shadows = 0.0
    var sharpness = 0.0
    var grain = 0.0
    var vignette = 0.0
    var bloom = 0.0
    var halation = 0.0

    static let natural: GradeSettings = {
        var settings = GradeSettings()
        GradeLook.all.first { $0.id == "natural" }?.apply(to: &settings)
        return settings
    }()
}

struct GradeLook: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String

    static var photoLabel: String { L("Photo to color") }

    static let all: [GradeLook] = [
        GradeLook(id: "none", name: L("None"), detail: L("the photo as it is")),
        GradeLook(id: "natural", name: L("Natural"), detail: L("a touch more life")),
        GradeLook(id: "bw-film", name: L("B&W film"), detail: L("black and white, with grain")),
        GradeLook(id: "split-tone", name: L("Split tone"), detail: L("cool shadows, warm lights")),
        GradeLook(id: "soft-skin", name: L("Soft skin"), detail: L("warm and gentle")),
        GradeLook(id: "cinematic", name: L("Cinematic"), detail: L("movie colors, dark edges")),
        GradeLook(id: "16mm", name: L("16 mm film"), detail: L("grainy and warm")),
        GradeLook(id: "old-lens", name: L("Vintage lens"), detail: L("dark corners, warm glow")),
        GradeLook(id: "color-correct", name: L("Correction"), detail: L("balanced colors")),
        GradeLook(id: "bloom", name: L("Bloom"), detail: L("a soft glow in the lights")),
        GradeLook(id: "halation", name: L("Red glow"), detail: L("a reddish shine on bright lights")),
        GradeLook(id: "lens-haze", name: L("Haze"), detail: L("soft and hazy")),
        GradeLook(id: "film-grain", name: L("Grain"), detail: L("film texture")),
        GradeLook(id: "faded", name: L("Faded"), detail: L("soft, washed-out colors")),
    ]

    func apply(to settings: inout GradeSettings) {
        settings = GradeSettings(look: id)
        switch id {
        case "natural": settings.contrast = 0.1; settings.saturation = 0.08
        case "bw-film": settings.contrast = 0.25; settings.grain = 0.35
        case "split-tone": settings.contrast = 0.1
        case "soft-skin": settings.contrast = -0.1; settings.temperature = 0.15; settings.bloom = 0.15
        case "cinematic": settings.contrast = 0.2; settings.saturation = -0.1; settings.vignette = 0.35
        case "16mm": settings.grain = 0.6; settings.temperature = 0.2; settings.vignette = 0.3; settings.contrast = 0.1
        case "old-lens": settings.vignette = 0.6; settings.halation = 0.3; settings.temperature = 0.2
        case "color-correct": settings.contrast = 0.12; settings.saturation = 0.1; settings.shadows = 0.2; settings.highlights = -0.25
        case "bloom": settings.bloom = 0.6
        case "halation": settings.halation = 0.7
        case "lens-haze": settings.bloom = 0.35; settings.contrast = -0.25
        case "film-grain": settings.grain = 0.7
        case "faded": settings.contrast = -0.2; settings.saturation = -0.2
        default: break
        }
    }
}

enum GradeRenderer {
    nonisolated static func render(_ input: CIImage, _ settings: GradeSettings) -> CIImage {
        var image = input
        let extent = input.extent

        if settings.exposure != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = image
            filter.ev = Float(settings.exposure)
            image = filter.outputImage ?? image
        }
        if settings.temperature != 0 || settings.tint != 0 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = image
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: 6500 - settings.temperature * 2500, y: settings.tint * 60)
            image = filter.outputImage ?? image
        }
        if settings.highlights != 0 || settings.shadows != 0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = image
            filter.highlightAmount = Float(1 + min(settings.highlights, 0))
            filter.shadowAmount = Float(settings.shadows)
            image = filter.outputImage ?? image
        }
        if settings.contrast != 0 || settings.saturation != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = image
            filter.contrast = Float(1 + settings.contrast * 0.5)
            filter.saturation = Float(1 + settings.saturation)
            filter.brightness = 0
            image = filter.outputImage ?? image
        }
        if let cube = lookCube(settings.look) {
            let filter = CIFilter.colorCubeWithColorSpace()
            filter.inputImage = image
            filter.cubeDimension = Float(cube.dimension)
            filter.cubeData = cube.data
            filter.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            image = filter.outputImage ?? image
        }
        if settings.bloom > 0 {
            let filter = CIFilter.bloom()
            filter.inputImage = image
            filter.radius = Float(extent.width * 0.012)
            filter.intensity = Float(settings.bloom)
            image = (filter.outputImage ?? image).cropped(to: extent)
        }
        if settings.halation > 0 {
            let highlights = CIFilter.colorMatrix()
            highlights.inputImage = image
            highlights.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
            highlights.gVector = CIVector(x: 0.25, y: 0, z: 0, w: 0)
            highlights.bVector = CIVector(x: 0.05, y: 0, z: 0, w: 0)
            highlights.biasVector = CIVector(x: -0.55, y: -0.15, z: -0.05, w: 0)
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = highlights.outputImage
            blur.radius = Float(extent.width * 0.01)
            if let glow = blur.outputImage?.cropped(to: extent) {
                let blend = CIFilter.additionCompositing()
                let scaled = CIFilter.colorMatrix()
                scaled.inputImage = glow
                let amount = CGFloat(settings.halation) * 0.9
                scaled.rVector = CIVector(x: amount, y: 0, z: 0, w: 0)
                scaled.gVector = CIVector(x: 0, y: amount, z: 0, w: 0)
                scaled.bVector = CIVector(x: 0, y: 0, z: amount, w: 0)
                blend.inputImage = scaled.outputImage
                blend.backgroundImage = image
                image = blend.outputImage?.cropped(to: extent) ?? image
            }
        }
        if settings.sharpness > 0 {
            let filter = CIFilter.sharpenLuminance()
            filter.inputImage = image
            filter.sharpness = Float(settings.sharpness * 1.2)
            filter.radius = 1.6
            image = filter.outputImage ?? image
        }
        if settings.vignette > 0 {
            let filter = CIFilter.vignette()
            filter.inputImage = image
            filter.intensity = Float(settings.vignette * 1.6)
            filter.radius = Float(max(extent.width, extent.height) / 1.6)
            image = filter.outputImage ?? image
        }
        if settings.grain > 0 {
            let noise = CIFilter.randomGenerator().outputImage!
                .transformed(by: CGAffineTransform(scaleX: 1.4, y: 1.4))
                .cropped(to: extent)
            let mono = CIFilter.colorMatrix()
            mono.inputImage = noise
            let amount = CGFloat(settings.grain) * 0.22
            mono.rVector = CIVector(x: amount, y: 0, z: 0, w: 0)
            mono.gVector = CIVector(x: amount, y: 0, z: 0, w: 0)
            mono.bVector = CIVector(x: amount, y: 0, z: 0, w: 0)
            mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            mono.biasVector = CIVector(x: -amount / 2, y: -amount / 2, z: -amount / 2, w: 0)
            let blend = CIFilter.additionCompositing()
            blend.inputImage = mono.outputImage
            blend.backgroundImage = image
            image = blend.outputImage?.cropped(to: extent) ?? image
        }
        return image.cropped(to: extent)
    }

    nonisolated static func lookCube(_ look: String) -> (dimension: Int, data: Data)? {
        let transform: ((Float, Float, Float) -> (Float, Float, Float))?
        switch look {
        case "bw-film":
            transform = { r, g, b in
                let l = 0.3 * r + 0.59 * g + 0.11 * b
                let curved = l * l * (3 - 2 * l)
                return (curved, curved, curved)
            }
        case "split-tone", "cinematic":
            let strength: Float = look == "cinematic" ? 0.12 : 0.18
            transform = { r, g, b in
                let l = 0.3 * r + 0.59 * g + 0.11 * b
                let shadow = max(0, 1 - l * 2), highlight = max(0, l * 2 - 1)
                return (r - shadow * strength * 0.6 + highlight * strength,
                        g + shadow * strength * 0.2 + highlight * strength * 0.35,
                        b + shadow * strength - highlight * strength * 0.7)
            }
        case "16mm", "old-lens":
            transform = { r, g, b in
                (0.06 + r * 0.92, 0.04 + g * 0.9, 0.03 + b * 0.82)
            }
        case "faded", "lens-haze":
            transform = { r, g, b in
                (0.08 + r * 0.86, 0.08 + g * 0.86, 0.1 + b * 0.84)
            }
        case "soft-skin":
            transform = { r, g, b in
                (r * 0.97 + 0.03, g * 0.98 + 0.015, b * 0.96 + 0.02)
            }
        default:
            transform = nil
        }
        guard let transform else { return nil }
        let size = 24
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
        return (size, values.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    @concurrent
    nonisolated static func makeImage(_ data: Data, settings: GradeSettings, maxPixel: Int?) async -> CGImage? {
        guard let source = ImageCoding.cgImage(from: data, maxPixel: maxPixel) else { return nil }
        let output = render(CIImage(cgImage: source), settings)
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        return context.createCGImage(output, from: output.extent)
    }
}

struct ColorGradeView: View {
    @Environment(AppModel.self) private var app
    @State private var preview: CGImage?
    @State private var showOriginal = false
    @State private var isSaving = false
    @State private var showsSaved = false
    @State private var showControls = true
    @State private var canvasWidth: CGFloat = 0

    private var state: ComposerState { app.composer(for: .colorGrade) }

    var body: some View {
        @Bindable var state = state
        ZStack {
            if let source = state.source {
                DataImage(data: source, maxPixel: 1800)
                    .opacity(showOriginal || preview == nil ? 1 : 0)
                    .overlay {
                        if !showOriginal, let preview {
                            Image(decorative: preview, scale: 1)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        }
                    }
                    .clipShape(.rect(cornerRadius: Radius.tile))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                    .padding(24)
                    .overlay(alignment: .bottom) {
                        VStack(spacing: 8) {
                            ConfirmationCapsule(text: L("Saved to Library"), isShown: $showsSaved)
                            Button {
                            } label: {
                                Label(L("Hold to See Original"), systemImage: "eye")
                            }
                            .buttonStyle(.glass)
                            .fixedSize()
                            .onLongPressGesture(minimumDuration: 0, maximumDistance: 50, pressing: { showOriginal = $0 }, perform: {})
                        }
                        .padding(16)
                    }
            } else {
                ToolEmptyState(tool: .colorGrade, source: $state.source, title: GradeLook.photoLabel)
                    .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { canvasWidth = $0 }
        .navigationTitle(Tool.colorGrade.title)
        .canvasSubtitle(Tool.colorGrade.subtitle, canvasWidth: canvasWidth)
        .inspector(isPresented: $showControls) {
            controls
                .toolPanelWidth()
        }
        .toolbar {
            if state.source != nil {
                ToolbarItem {
                    Button(L("Change Photo"), systemImage: "photo.badge.arrow.down") {
                        if let data = ImageIntake.pick(multiple: false).first { state.source = data }
                    }
                }
            }
            ToolbarItem {
                Button(L("Controls"), systemImage: "sidebar.right") { showControls.toggle() }
                    .help(L("Show or hide controls (⌥⌘I)"))
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        .task(id: PreviewKey(data: state.source, settings: state.grade)) {
            guard let source = state.source else { preview = nil; return }
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            preview = await GradeRenderer.makeImage(source, settings: state.grade, maxPixel: 1600)
        }
        .onAppear {
            if let data = app.takeHandoff(for: .colorGrade) { state.source = data }
        }
    }

    private var controls: some View {
        @Bindable var state = state
        let settings = state.grade
        let hasPhoto = state.source != nil
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 28) {
                        PanelSection(title: GradeLook.photoLabel, step: 1, isDone: hasPhoto) {
                            InputRow(data: $state.source) {
                                EmptySourceRow { state.source = $0 }
                            }
                        }
                        PanelSection(title: L("Color styles"), step: 2, isDone: hasPhoto) {
                            let pictures = OptionImages.pictures(family: "grade", values: GradeLook.all.map(\.id))
                            OptionGrid(minimum: pictures == nil ? 88 : PanelLayout.pictureCardMinimum) {
                                ForEach(GradeLook.all) { look in
                                    OptionTile(title: look.name, subtitle: look.detail, systemImage: pictures == nil ? nil : "camera.filters",
                                               picture: pictures?[look.id], isSelected: settings.look == look.id) {
                                        look.apply(to: &state.grade)
                                    }
                                }
                            }
                            Text(L("Choosing a style also resets the sliders below."))
                                .helperTextStyle()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ExtrasHeader()
                    OptionalSection(L("Fine-tune"), systemImage: "dial.medium", summary: fineTuneSummary(settings),
                                    storageKey: "tool.colorGrade.finetune") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Light & Color")).groupTitleStyle()
                            slider(L("Exposure"), $state.grade.exposure, -2...2)
                            slider(L("Temperature"), $state.grade.temperature, -1...1)
                            slider(L("Tint"), $state.grade.tint, -1...1)
                            slider(L("Contrast"), $state.grade.contrast, -1...1)
                            slider(L("Saturation"), $state.grade.saturation, -1...1)
                            slider(L("Recover highlights"), Binding(get: { -state.grade.highlights }, set: { state.grade.highlights = -$0 }), 0...1)
                            slider(L("Lift shadows"), $state.grade.shadows, 0...1)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Texture & Optics")).groupTitleStyle()
                            slider(L("Sharpness"), $state.grade.sharpness, 0...1)
                            slider(L("Grain"), $state.grade.grain, 0...1)
                            slider(L("Vignette"), $state.grade.vignette, 0...1)
                            slider(L("Bloom"), $state.grade.bloom, 0...1)
                            slider(L("Red glow"), $state.grade.halation, 0...1)
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            VStack(spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    saveButton(size: .extraLarge)
                    saveButton(size: .large)
                }
                .frame(maxWidth: .infinity)
                HStack {
                    DisabledReasonLabel(reason: hasPhoto ? nil : DisabledReasonLabel.nextStep(GradeLook.photoLabel.localizedLowercase))
                    Spacer()
                    Button(L("Reset")) { state.grade = .natural }
                        .buttonStyle(.link)
                        .font(.callout)
                        .fixedSize()
                        .disabled(settings == .natural)
                }
            }
            .animation(Motion.standard, value: hasPhoto)
            .padding(16)
        }
    }

    private func saveButton(size: ControlSize) -> some View {
        let isReady = state.source != nil
        return Button {
            save()
        } label: {
            saveLabel(size: size, isReady: true)
                .prominentLabel()
        }
        .buttonStyle(.glassProminent)
        .tint(.brandFill)
        .controlSize(size)
        .disabled(!isReady || isSaving)
        .keyboardShortcut("s", modifiers: .command)
        .opacity(isReady ? 1 : 0)
        .accessibilityHidden(!isReady)
        .help(isReady ? L("Save to Library (⌘S)") : "")
        .overlay {
            if !isReady {
                saveLabel(size: size, isReady: false)
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassEffect(.regular, in: .capsule)
                    .contentShape(.capsule)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityValue(L("Not ready yet"))
                    .help(DisabledReasonLabel.nextStep(GradeLook.photoLabel.localizedLowercase))
                    .transition(.opacity)
            }
        }
        .animation(Motion.fade, value: isReady)
    }

    private func saveLabel(size: ControlSize, isReady: Bool) -> some View {
        HStack(spacing: 8) {
            if isSaving {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "square.and.arrow.down")
            }
            Text(L("Save to Library"))
                .font(size == .extraLarge ? .title3.weight(.semibold) : .body.weight(.semibold))
            Text(L("Free"))
                .font(.subheadline)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isReady ? Color.white.opacity(0.18) : Color.primary.opacity(0.08), in: .capsule)
                .fixedSize()
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 22)
        .fixedSize(horizontal: true, vertical: false)
    }

    private struct PreviewKey: Equatable {
        let data: Data?
        let settings: GradeSettings
    }

    private func fineTuneSummary(_ settings: GradeSettings) -> String? {
        var style = GradeSettings()
        GradeLook.all.first { $0.id == settings.look }?.apply(to: &style)
        let sliders: [KeyPath<GradeSettings, Double>] = [\.exposure, \.temperature, \.tint, \.contrast, \.saturation,
                                                         \.highlights, \.shadows, \.sharpness, \.grain, \.vignette,
                                                         \.bloom, \.halation]
        let changed = sliders.filter { abs(settings[keyPath: $0] - style[keyPath: $0]) > 0.001 }.count
        return changed == 0 ? nil : changed == 1 ? L("1 changed") : L("%ld changed", changed)
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text(value.wrappedValue == 0 ? "0" : String(format: "%+.2f", value.wrappedValue))
                    .monospacedDigit()
                    .fineTextStyle()
            }
            Slider(value: value, in: range)
                .controlSize(.small)
                .onTapGesture(count: 2) { value.wrappedValue = 0 }
                .help(L("Double-click to set it back to 0"))
        }
    }

    private func save() {
        guard let source = state.source else { return }
        isSaving = true
        let current = state.grade
        Task {
            defer { isSaving = false }
            guard let image = await GradeRenderer.makeImage(source, settings: current, maxPixel: nil),
                  let png = ImageCoding.encode(image, as: .png) else { return }
            let look = GradeLook.all.first { $0.id == current.look }?.name ?? L("Custom")
            let template = Asset(
                id: UUID(), fileName: "", createdAt: .now, width: 0, height: 0, tool: .colorGrade,
                prompt: E("Color Grade: %@", english(look)), finalPrompt: "", modelID: "local:coreimage", modelName: "Core Image (local)",
                provider: .openRouter, aspectRatio: .auto, resolution: .oneK, batchID: UUID(),
                inputFileNames: [app.library.storeInput(InputImage(data: source, mimeType: "image/png"))],
                cost: 0, isFavorite: false
            )
            let saved = app.library.add(GeneratedImage(data: png, mimeType: "image/png"), template: template)
            app.engine.recordLocal(title: template.prompt, tool: .colorGrade, modelName: template.modelName, assetIDs: [saved.id])
            showsSaved = true
        }
    }
}
