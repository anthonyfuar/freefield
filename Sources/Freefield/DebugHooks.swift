#if DEBUG
import AppKit
import FreefieldCore
import SwiftUI

enum DebugHooks {
    private static var installed = false
    static var openSettings: () -> Void = {}

    static func install(app: AppModel) {
        guard !installed else { return }
        installed = true
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Notification.Name("app.freefield.debug.navigate"), object: nil, queue: .main) { note in
            let target = note.object as? String ?? ""
            MainActor.assumeIsolated { navigate(app, to: target) }
        }
        center.addObserver(forName: Notification.Name("app.freefield.debug.snapshot"), object: nil, queue: .main) { note in
            guard let path = note.object as? String else { return }
            MainActor.assumeIsolated {
                if path.hasPrefix("front:") { snapshot(to: String(path.dropFirst(6)), frontmost: true) } else { snapshot(to: path, frontmost: false) }
            }
        }
    }

    private static func navigate(_ app: AppModel, to target: String) {
        switch target {
        case "home": app.selection = .home
        case "styles": app.selection = .styles
        case "characters": app.selection = .characters
        case "products": app.selection = .products
        case "apps": app.selection = .apps
        case "library": app.selection = .library
        case "favorites": app.selection = .favorites
        case "usage": app.selection = .usage
        case "settingsview": app.selection = .settings
        case "onboarding": app.showOnboarding = true
        case "dismiss": app.showOnboarding = false
        case "settings": openSettings()
        default:
            if target.hasPrefix("tool:"), let tool = Tool(rawValue: String(target.dropFirst(5))) {
                app.selection = .tool(tool)
            } else if target.hasPrefix("load:"), let data = try? Data(contentsOf: URL(fileURLWithPath: String(target.dropFirst(5)))) {
                if case .tool(let tool) = app.selection { app.composer(for: tool).source = data }
            } else if target.hasPrefix("importkey:") {
                let path = String(target.dropFirst(10))
                if let text = try? String(contentsOfFile: path, encoding: .utf8),
                   let match = text.range(of: #"sk-or-v1-[A-Za-z0-9]+"#, options: .regularExpression) {
                    app.keys.set(String(text[match]), for: .openRouter)
                    app.showOnboarding = false
                    Task { await app.refreshModels() }
                }
            } else if handleTestCommand(app, target) || handleVideoCommand(app, target) {
            } else if target == "vrun" {
                if let (tool, state) = currentVideo(app) { app.runVideoTool(tool, state: state) }
            } else if target == "run" {
                if case .ad(let id) = app.selection, let tool = AdCatalog.tool(id) {
                    let ad = app.adState(for: tool)
                    let requirement = ModelRequirement(images: 1, promptLength: tool.recipe.count + 200)
                    let featured = app.choices(for: requirement).featured
                    let model = ad.modelID.flatMap { id in app.catalog.allModels.first { $0.id == id } }
                        ?? featured.first { $0.lineup?.id == tool.model }?.model ?? featured.first?.model
                    if let model { app.runAd(tool, state: ad, model: model) }
                }
                if case .tool(let tool) = app.selection {
                    let state = app.composer(for: tool)
                    let images = tool == .create ? state.references.count : 1
                    let requirement = ModelRequirement(images: images)
                    let model = tool == .create ? app.resolvedModel(for: state, requirement: requirement)
                        : app.toolModel(for: state, requirement: requirement)
                    if let model {
                        switch tool {
                        case .create: app.runCreate(state, model: model)
                        case .storyboard:
                            app.runStoryboard(state, scenes: state.storyScenes.map(\.text).filter { !$0.isEmpty }, model: model)
                        case .photoSession:
                            if let character = app.library.character(state.characterID),
                               let set = PhotoSessionSet.all.first(where: { $0.id == state.sessionSetID }) {
                                app.runPhotoSession(state, set: set, model: model, character: character)
                            }
                        default: app.runTool(tool, state: state, model: model)
                        }
                    }
                }
            } else if target.hasPrefix("model:") {
                if case .tool(let tool) = app.selection {
                    app.composer(for: tool).modelID = app.catalog.allModels.first { $0.modelID == String(target.dropFirst(6)) }?.id
                }
            } else if target.hasPrefix("preset:") {
                if case .tool(let tool) = app.selection { app.composer(for: tool).presetID = String(target.dropFirst(7)) }
            } else if target.hasPrefix("count:") {
                if case .tool(let tool) = app.selection { app.composer(for: tool).count = Int(target.dropFirst(6)) ?? 1 }
            } else if target.hasPrefix("gradelook:"), let look = GradeLook.all.first(where: { $0.id == String(target.dropFirst(10)) }) {
                look.apply(to: &app.composer(for: .colorGrade).grade)
            } else if target == "loadlatest", case .tool(let tool) = app.selection, let asset = app.library.images.first {
                app.composer(for: tool).source = app.library.imageData(for: asset)
            } else if target == "detecttext", let source = app.composer(for: .editText).source {
                Task {
                    let lines = (try? await app.readText(in: source)) ?? []
                    app.composer(for: .editText).textEdits = lines.map { TextEdit(original: $0, replacement: $0) }
                }
            } else if target == "enhance", case .tool(let tool) = app.selection {
                Task { await app.enhancePrompt(in: app.composer(for: tool)) }
            } else if target.hasPrefix("prompt:") {
                if case .tool(let tool) = app.selection { app.composer(for: tool).prompt = String(target.dropFirst(7)) }
            }
        }
    }

    private static func layerSnapshot(_ window: NSWindow) -> CGImage? {
        guard let view = window.contentView?.superview ?? window.contentView, let layer = view.layer else { return nil }
        let scale = window.backingScaleFactor
        let size = view.bounds.size
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        if !view.isFlipped {
        }
        layer.render(in: context)
        return context.makeImage()
    }

    private static func handleTestCommand(_ app: AppModel, _ target: String) -> Bool {
        let parts = target.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return false
        }
        let (command, argument) = (parts[0], parts[1])
        let tool: Tool? = if case .tool(let current) = app.selection { current } else { nil }
        let state = tool.map { app.composer(for: $0) }
        let data: (String) -> Data? = { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
        switch command {
        case "winsize":
            let size = argument.split(separator: "x").compactMap { Double($0) }
            let windows = NSApp.orderedWindows.filter { $0.isVisible && $0.sheetParent == nil }
            guard size.count == 2, let window = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
            else { return true }
            window.setContentSize(NSSize(width: size[0], height: size[1]))
            window.center()
        case "scrollpage", "scrollinfo":
            func scrollViews(in view: NSView) -> [NSScrollView] {
                (view as? NSScrollView).map { [$0] + $0.subviews.flatMap(scrollViews) } ?? view.subviews.flatMap(scrollViews)
            }
            let windows = NSApp.orderedWindows.filter { $0.isVisible && $0.sheetParent == nil }
            guard let window = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
                  let root = window.contentView?.superview else { return true }
            let all = scrollViews(in: root)
            if command == "scrollinfo" {
                let lines = all.map { view in
                    let frame = view.convert(view.bounds, to: nil)
                    return "\(type(of: view)) frame:\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)) "
                        + "doc:\(Int(view.documentView?.frame.height ?? -1)) clip:\(Int(view.contentView.bounds.height))"
                }
                try? lines.joined(separator: "\n").write(toFile: argument, atomically: true, encoding: .utf8)
                return true
            }
            guard let fraction = Double(argument) else { return true }
            func room(_ view: NSScrollView) -> (top: CGFloat, bottom: CGFloat) {
                let insets = view.contentInsets
                let document = view.documentView?.frame.height ?? 0
                return (-insets.top, document - view.contentView.bounds.height + insets.bottom)
            }
            let main = all.filter { view in
                view.convert(view.bounds, to: nil).maxX > 500 && room(view).bottom > room(view).top + 1
            }
            .max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
            if let main, let document = main.documentView {
                let (top, bottom) = room(main)
                let offset = top + (bottom - top) * fraction
                let y = document.isFlipped ? offset : document.frame.height - main.contentView.bounds.height - offset
                main.contentView.scroll(to: NSPoint(x: 0, y: y))
                main.reflectScrolledClipView(main.contentView)
            }
        case "selectrow":
            let fields = argument.split(separator: "|").map(String.init)
            guard fields.count == 2, let row = Int(fields[0]) else { return true }
            func tables(in view: NSView) -> [NSTableView] {
                (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(tables)
            }
            let windows = NSApp.orderedWindows.filter { $0.isVisible && $0.sheetParent == nil }
            guard let window = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
                  let root = window.contentView?.superview else { return true }
            let sidebar = tables(in: root).min { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
            let before = String(describing: app.selection)
            sidebar?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                let report = "rows:\(sidebar?.numberOfRows ?? -1) selectedRow:\(sidebar?.selectedRow ?? -9) before:\(before) after:\(String(describing: app.selection))\n"
                try? report.write(toFile: fields[1], atomically: true, encoding: .utf8)
            }
        case "gradeexport":
            let fields = argument.split(separator: "|").map(String.init)
            guard fields.count == 3, let look = GradeLook.all.first(where: { $0.id == fields[0] }),
                  let input = data(fields[1]) else { return true }
            var settings = GradeSettings()
            look.apply(to: &settings)
            Task {
                if let image = await GradeRenderer.makeImage(input, settings: settings, maxPixel: 1400),
                   let png = ImageCoding.encode(image, as: .png) {
                    try? png.write(to: URL(fileURLWithPath: fields[2]))
                }
            }
        case "secondary":
            state?.secondary = data(argument)
        case "ref":
            if let image = data(argument) { state?.references.append(image) }
        case "stroke":
            let values = argument.split(separator: ",").compactMap { Double($0) }
            guard values.count == 5, let state else { return true }
            let points = (0...20).map { step -> CGPoint in
                let t = Double(step) / 20
                return CGPoint(x: values[0] + (values[2] - values[0]) * t, y: values[1] + (values[3] - values[1]) * t)
            }
            state.strokes.append(Stroke(points: points, width: values[4], color: tool == .drawToEdit ? state.inkColor : .systemRed))
        case "circle":
            let values = argument.split(separator: ",").compactMap { Double($0) }
            guard values.count == 4, let state else { return true }
            let points = (0...40).map { step -> CGPoint in
                let angle = Double(step) / 40 * 2 * .pi
                return CGPoint(x: values[0] + values[2] * cos(angle), y: values[1] + values[2] * sin(angle) * 1.3)
            }
            state.strokes.append(Stroke(points: points, width: values[3], color: state.inkColor))
        case "note":
            let values = argument.split(separator: ",", maxSplits: 2).map(String.init)
            guard values.count == 3, let x = Double(values[0]), let y = Double(values[1]), let state else { return true }
            state.notes.append(TextNote(position: CGPoint(x: x, y: y), text: values[2], color: state.inkColor))
        case "opt":
            let pair = argument.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2, let state else { return true }
            let (key, value) = (pair[0], pair[1])
            switch key {
            case "light": state.lightPreset = value
            case "hard": state.lightHard = value == "1"
            case "anglesMode": state.anglesMode = value
            case "angles": state.angles = Set(value.split(separator: ",").map(String.init))
            case "orbit":
                let values = value.split(separator: ",").compactMap { Double($0) }
                if values.count == 3 { (state.orbitRotation, state.orbitTilt, state.orbitZoom) = (values[0], values[1], values[2]) }
            case "expand": state.expandTarget = AspectRatio(rawValue: value) ?? .landscape16x9
            case "bg": state.backgroundMode = value
            case "res": state.resolution = Resolution(rawValue: value) ?? .oneK
            case "aspect": state.aspectRatio = AspectRatio(rawValue: value) ?? .auto
            case "set": state.sessionSetID = value
            case "shots": state.sessionShots = Int(value) ?? 3
            case "template": state.storyTemplate = value
            case "story": state.story = value
            case "frames": state.storyFrames = Int(value) ?? 3
            case "scenes": state.storyScenes = value.split(separator: "|").map { StoryScene(text: String($0)) }
            case "camera": state.cameraBody = value
            case "lens": state.cameraLens = value
            case "focal": state.cameraFocalLength = value
            case "aperture": state.cameraAperture = value
            case "palette": state.paletteID = value
            case "creativity": state.upscaleCreativity = Double(value) ?? 0.2
            default: break
            }
        case "textedit":
            let pair = argument.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2, let state else { return true }
            for index in state.textEdits.indices where state.textEdits[index].original == pair[0] {
                state.textEdits[index].replacement = pair[1]
            }
        case "newcharacter":
            let fields = argument.split(separator: "|", maxSplits: 2).map(String.init)
            guard fields.count == 3 else { return true }
            let photos = fields[2].split(separator: ",").compactMap { data(String($0)) }
            let character = app.library.addCharacter(name: fields[0], details: fields[1], photos: photos)
            state?.characterID = character.id
        case "character":
            state?.characterID = app.library.characters.first { $0.name == argument }?.id
        case "newmoodboard":
            let fields = argument.split(separator: "|", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { return true }
            let images = fields[1].split(separator: ",").compactMap { data(String($0)) }
            let board = app.library.addMoodboard(name: fields[0], images: images)
            app.composer(for: .create).moodboardID = board.id
            app.composer(for: .create).presetID = nil
            Task { await app.describeMoodboard(board) }
        case "runapp":
            let fields = argument.split(separator: "|").map(String.init)
            guard fields.count >= 2, let item = AppCatalog.item(fields[0]), let image = data(fields[1]) else { return true }
            let appState = app.composer(for: .app)
            let preferred = item.model.flatMap { id in app.choices(for: ModelRequirement(images: item.slots.count)).featured.first { $0.lineup?.id == id }?.model }
            let forced = fields.count > 3 ? app.catalog.allModels.first { $0.modelID == fields[3] } : nil
            if let model = forced ?? preferred ?? app.resolvedModel(for: appState, requirement: ModelRequirement(images: item.slots.count)) {
                app.runApp(item, inputs: [image], option: fields.count > 2 && !fields[2].isEmpty ? fields[2] : item.options.first, text: "",
                           model: model, aspect: item.aspect, count: 1)
            }
        case "importproduct":
            Task {
                if let product = try? await ProductImporter.fetch(argument) {
                    app.library.addProduct(name: String(product.title.prefix(60)), details: String(product.description.prefix(300)),
                                           photos: product.photos, sourceURL: product.sourceURL.absoluteString)
                }
            }
        case "ad":
            app.selection = .ad(argument)
        case "adproduct", "adphoto", "adperson", "adpersonphoto", "adref", "adopt", "adtext", "adtext2", "admodel":
            guard case .ad(let id) = app.selection, let tool = AdCatalog.tool(id) else { return true }
            let ad = app.adState(for: tool)
            switch command {
            case "adproduct": ad.productID = app.library.products.first { $0.name == argument }?.id
            case "adphoto": ad.productPhoto = data(argument)
            case "adperson": ad.characterID = app.library.characters.first { $0.name == argument }?.id
            case "adpersonphoto": ad.personPhoto = data(argument)
            case "adref": ad.reference = data(argument)
            case "adopt":
                let pair = argument.split(separator: "=", maxSplits: 1).map(String.init)
                if pair.count == 2, let index = Int(pair[0]) { ad.choices[index] = pair[1] }
            case "adtext": ad.text = argument.replacingOccurrences(of: "\\n", with: "\n")
            case "adtext2": ad.text2 = argument
            default: ad.modelID = app.catalog.allModels.first { $0.modelID == argument }?.id
            }
        case "style":
            app.selection = .apps
            app.pendingQuickStyle = argument
        case "product":
            state?.productID = app.library.products.first { $0.name == argument }?.id
        case "optionaudit":
            var keys: [String] = []
            for tool in AdCatalog.all {
                for group in tool.options {
                    if let source = tool.picturesFrom {
                        let title = group.pictureTitle ?? english(group.title)
                        keys += group.values.map { "ads/\(source)/" + OptionImages.slug("\(title) \($0)") }
                    }
                    keys += group.values.map { "ads/\(tool.id)/" + OptionImages.slug("\(english(group.title)) \($0)") }
                }
            }
            for tool in VideoCatalog.all {
                for group in tool.optionGroups {
                    keys += group.values.map { "video/\(tool.id)-\(group.id)/" + OptionImages.slug($0) }
                }
            }
            try? keys.joined(separator: "\n").write(toFile: argument, atomically: true, encoding: .utf8)
        case "deleteassets":
            app.library.delete(Set(argument.split(separator: ",").compactMap { UUID(uuidString: String($0)) }))
        case "retryfailed":
            for job in app.engine.jobs where { if case .failed = job.status { !job.isStillAtProvider } else { false } }() {
                app.engine.retry(job)
            }
        case "writescenes":
            guard let state else { return true }
            Task { state.storyScenes = ((try? await app.writeStoryScenes(state)) ?? []).map { StoryScene(text: $0) } }
        case "dumpjobs":
            let jobs = app.engine.jobs.map { job -> [String: Any] in
                let status: String = switch job.status {
                case .running: "running"
                case .finished: "finished"
                case .failed(let message): "failed: \(message)"
                case .cancelled: "cancelled"
                }
                let assets = job.assetIDs.compactMap { app.library.asset($0) }
                let files = assets.map { app.library.url(for: $0).path }
                var row: [String: Any] = [
                    "tool": job.tool.rawValue, "title": job.title, "status": status, "received": job.received,
                    "requested": job.requested, "failures": job.failures, "files": files,
                    "model": assets.first?.modelDisplayName ?? job.videoSpec?.request.model.id ?? "",
                ]
                if let appID = job.spec?.appID { row["appID"] = appID }
                if job.isVideo { row["video"] = videoJobDump(job, assets: assets) }
                return row
            }
            var extra: [String: Any] = [
                "moodboards": app.library.moodboards.map { ["name": $0.name, "style": $0.styleDescription] },
                "characters": app.library.characters.map { ["name": $0.name, "photos": $0.photoFileNames.count] },
                "storyScenes": app.composer(for: .storyboard).storyScenes.map(\.text),
                "tunnel": ["sharesClips": SettingsKey.sharesClips, "openShares": app.clipSharing.openCount],
                "videoModels": app.videoModels.count,
            ]
            if let (tool, state) = currentVideo(app) { extra["video"] = videoStateDump(app, tool: tool, state: state) }
            if let json = try? JSONSerialization.data(withJSONObject: ["jobs": jobs, "state": extra], options: [.prettyPrinted]) {
                try? json.write(to: URL(fileURLWithPath: argument))
            }
        case "dumpprompts":
            dumpPrompts(app, to: argument)
        default:
            return false
        }
        return true
    }

    private static func currentVideo(_ app: AppModel) -> (VideoTool, VideoState)? {
        let id: String? = switch app.selection {
        case .video(let id): id
        case .videoEffects: "videoEffects"
        case .tool(.video): "createVideo"
        default: nil
        }
        guard let tool = id.flatMap(VideoCatalog.tool) else { return nil }
        return (tool, app.videoState(for: tool))
    }

    private static func handleVideoCommand(_ app: AppModel, _ target: String) -> Bool {
        let parts = target.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == "video" || parts[0].hasPrefix("v") else { return false }
        let (command, argument) = (parts[0], parts[1])
        let data: (String) -> Data? = { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
        switch command {
        case "video":
            guard VideoCatalog.tool(argument) != nil else { return true }
            app.openVideo(argument)
            return true
        case "veffect":
            guard let effect = VideoEffects.effect(argument), let tool = VideoCatalog.tool("videoEffects") else { return true }
            app.videoState(for: tool).apply(effect)
            app.openVideo(tool.id)
            return true
        case "vimport":
            if let data = data(argument) { _ = app.library.importImage(data: data, name: (argument as NSString).lastPathComponent) }
            return true
        case "vhandoff":
            if let asset = app.library.assets.first(where: { !$0.isVideo }) { app.makeVideo(from: asset, in: argument) }
            return true
        case "vtunnel":
            UserDefaults.standard.set(argument == "on" || argument == "1", forKey: SettingsKey.shareClipsWithTunnel)
            return true
        case "vselfcheck":
            let problems = VideoRecipes.selfCheck(models: app.videoModels)
            let report: [String: Any] = ["problems": problems, "count": problems.count, "tools": VideoCatalog.all.count,
                                         "liveModels": app.videoModels.count]
            if let json = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                try? json.write(to: URL(fileURLWithPath: argument))
            }
            return true
        case "vdump":
            try? VideoRecipes.sampleDump(models: app.videoModels).write(toFile: argument, atomically: true, encoding: .utf8)
            return true
        case "vprompt", "vtext", "vframe", "vlast", "vref", "vsource", "vdriving", "vclip", "vcharacter", "vproduct",
             "vopt", "vmodel", "vdur", "vres", "vaspect", "vaudio", "vcamera", "vrun", "vshot", "vstroke", "vperson", "vconsent", "vkeyframe":
            break
        default:
            return false
        }
        guard let (tool, state) = currentVideo(app) else { return true }
        switch command {
        case "vprompt": state.prompt = argument.replacingOccurrences(of: "\\n", with: "\n")
        case "vtext":
            let pair = argument.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { state.texts[pair[0]] = pair[1].replacingOccurrences(of: "\\n", with: "\n") }
        case "vframe": state.firstFrame = data(argument)
        case "vlast": state.lastFrame = data(argument)
        case "vref": if let image = data(argument) { state.references.append(image) }
        case "vsource", "vdriving", "vclip":
            if argument.lowercased().hasPrefix("https://") {
                if command == "vsource" { state.source = VideoClipPick(assetID: nil, link: argument) }
                if command == "vdriving" { state.driving = VideoClipPick(assetID: nil, link: argument) }
                return true
            }
            Task {
                guard let asset = await videoAsset(app, argument) else { return }
                switch command {
                case "vsource": state.source = VideoClipPick(assetID: asset.id, link: app.pastedLink(for: asset) ?? "")
                case "vdriving": state.driving = VideoClipPick(assetID: asset.id, link: app.pastedLink(for: asset) ?? "")
                default: state.clipIDs.append(asset.id)
                }
            }
        case "vcharacter": state.characterID = app.library.characters.first { $0.name == argument }?.id
        case "vproduct": state.productID = app.library.products.first { $0.name == argument }?.id
        case "vopt":
            let pair = argument.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return true }
            let id = Int(pair[0]).flatMap { tool.optionGroups.indices.contains($0) ? tool.optionGroups[$0].id : nil } ?? pair[0]
            state.choices[id] = pair[1]
        case "vmodel": state.modelID = argument == "auto" ? nil : argument
        case "vdur": state.duration = Int(argument)
        case "vres": state.resolution = argument == "auto" ? nil : argument
        case "vaspect": state.aspect = argument == "auto" ? nil : argument
        case "vaudio": state.audio = argument == "1" || argument == "on"
        case "vkeyframe": state.firstFrameIsKeyframe = argument == "1" || argument == "on"
        case "vperson": state.characterPhoto = data(argument)
        case "vconsent": state.consent = argument == "1" || argument == "on"
        case "vshot":
            let fields = argument.split(separator: "|", maxSplits: 2).map(String.init)
            var shot = VideoShotDraft(action: fields.count > 1 ? fields[1] : "", image: fields.first.flatMap { $0.isEmpty ? nil : data($0) })
            if fields.count > 2 { shot.camera = fields[2] }
            state.shots.append(shot)
        case "vstroke":
            let values = argument.split(separator: ",").compactMap { Double($0) }
            guard values.count == 5 else { return true }
            let points = (0...20).map { step -> CGPoint in
                let t = Double(step) / 20
                return CGPoint(x: values[0] + (values[2] - values[0]) * t, y: values[1] + (values[3] - values[1]) * t)
            }
            state.drawStrokes.append(Stroke(points: points, width: values[4], color: .systemRed))
        case "vcamera":
            state.cameraMoves = argument.split(separator: ",").map(String.init).filter { CameraMoves.move($0) != nil }
        case "vrun":
            app.runVideoTool(tool, state: state, confirmed: argument == "confirmed")
        default: break
        }
        return true
    }

    private static func videoAsset(_ app: AppModel, _ reference: String) async -> Asset? {
        if let id = UUID(uuidString: reference), let asset = app.library.asset(id), asset.isVideo { return asset }
        guard FileManager.default.fileExists(atPath: reference) else { return nil }
        return await app.library.importVideo(url: URL(fileURLWithPath: reference))
    }

    private static func videoJobDump(_ job: Job, assets: [Asset]) -> [String: Any] {
        guard let spec = job.videoSpec else { return [:] }
        let request = spec.request
        let phase: String = switch job.videoPhase {
        case .submitting: job.isSendingVideo ? "sending" : "submitting"
        case .waiting: "waiting"
        case .downloading: "downloading"
        case .stillAtProvider: "stillAtProvider"
        case nil: ""
        }
        let references = request.references.map { input -> String in
            switch input {
            case .image: "image"
            case .videoURL(let url): "video \(url)"
            case .audioURL(let url): "audio \(url)"
            }
        }
        let costs = assets.compactMap(\.cost)
        return [
            "toolID": spec.toolID, "model": request.model.id, "prompt": request.prompt, "record": spec.record ?? "",
            "literalTexts": spec.literalTexts, "userTexts": spec.userTexts,
            "duration": json(request.duration), "resolution": json(request.resolution),
            "aspect": json(request.aspectRatio), "audio": json(request.generateAudio),
            "firstFrame": request.firstFrame != nil, "lastFrame": request.lastFrame != nil, "references": references,
            "remoteID": json(job.remoteID), "remoteState": json(job.remoteState?.rawValue), "phase": phase,
            "submittedAt": json(job.submittedAt.map { ISO8601DateFormatter().string(from: $0) }),
            "elapsed": json(job.submittedAt.map { Date.now.timeIntervalSince($0) }),
            "estimate": json(job.estimate ?? spec.estimatedCost),
            "cost": json(costs.isEmpty ? nil : costs.reduce(0, +)), "costRecorded": job.costRecorded,
            "quiet": job.isQuiet, "discardsResult": job.discardsResult, "parentAssetID": json(spec.parentAssetID?.uuidString),
            "assets": assets.map { asset -> [String: Any] in
                ["id": asset.id.uuidString, "duration": json(asset.duration), "size": asset.pixelSizeLabel,
                 "hasAudio": json(asset.hasAudio), "remoteJobID": json(asset.remoteJobID)]
            },
        ]
    }

    private static func json(_ value: Any?) -> Any { value ?? NSNull() }

    private static func videoStateDump(_ app: AppModel, tool: VideoTool, state: VideoState) -> [String: Any] {
        let inputs = app.videoInputs(tool, state: state, forRun: false)
        let model = app.resolvedVideoModel(tool, state: state, inputs: inputs)
        return [
            "toolID": tool.id, "prompt": state.prompt, "choices": state.choices, "texts": state.texts,
            "modelID": json(state.modelID), "resolvedModel": json(model?.id),
            "sizes": app.videoSizeOptions(tool, state: state, inputs: inputs).map { ["size": $0.size, "model": $0.model.id, "cost": $0.cost ?? -1] },
            "duration": json(state.duration), "resolution": json(state.resolution), "aspect": json(state.aspect),
            "audio": state.audio, "count": state.count, "cameraMoves": state.cameraMoves, "effectID": json(state.effectID),
            "firstFrame": state.firstFrame != nil, "lastFrame": state.lastFrame != nil, "references": state.references.count,
            "source": state.source.assetID?.uuidString ?? state.source.trimmedLink, "clips": state.clipIDs.map(\.uuidString),
            "usesFrames": state.usesFrames, "isPreparing": state.isPreparing, "preparingStep": json(state.preparingStep),
            "inputProblem": json(state.inputProblem?.message), "confirmation": json(state.confirmation.map { $0.total ?? -1 }),
            "runNotes": state.runNotes,
            "localWork": state.localWork.map { ["title": $0.title, "step": $0.step ?? "", "failure": $0.failure ?? "", "done": $0.isDone] },
        ]
    }

    private static func dumpPrompts(_ app: AppModel, to path: String) {
        func model(_ lineupID: String) -> ImageModel? {
            guard let entry = Lineup.entry(lineupID) else { return nil }
            if let model = app.catalog.allModels.first(where: entry.matches) { return model }
            let provider: Provider = entry.ids(for: .openRouter).isEmpty ? .google : .openRouter
            guard let id = entry.ids(for: provider).first else { return nil }
            return ImageModel(provider: provider, modelID: id, name: entry.name, vendor: "", summary: "",
                              endpoint: provider == .google ? .geminiGenerateContent : .openRouterImages,
                              aspectRatios: [], resolutions: [])
        }
        func budget(_ lineupID: String, overhead: Int) -> [String: Any] {
            let model = model(lineupID)
            return ["model": lineupID, "modelID": model?.modelID ?? "", "modelLimit": PromptBudget.modelLimit(model),
                    "userLimit": PromptBudget.userLimit(model: model, overhead: overhead)]
        }

        let descriptiveSample = "in a red wool coat on a snowy street at dusk, smiling softly"
        let literalSample = "Grand Opening This Saturday: Free Coffee for the First Fifty"
        let apps = AppCatalog.all.map { item -> [String: Any] in
            let option = item.options.first
            let prompt = item.prompt(option: option, text: "")
            var row = budget(item.model ?? Lineup.defaultModelIDs(for: .app).first ?? "", overhead: prompt.utf16.count)
            row["id"] = item.id
            row["option"] = option ?? ""
            row["prompt"] = prompt
            row["length"] = prompt.utf16.count
            if item.textPlaceholder != nil {
                let sample = item.prompt(option: option, text: item.textIsLiteral ? literalSample : descriptiveSample)
                row["samplePrompt"] = sample
                row["sampleLength"] = sample.utf16.count
            }
            return row
        }

        let product = Product(id: UUID(), name: "Glow Serum", details: "hydrating vitamin C face serum in a 30 ml amber glass dropper bottle",
                              photoFileNames: ["1.jpg", "2.jpg"], sourceURL: nil, createdAt: .now)
        let character = Character(id: UUID(), name: "Ana", details: "woman in her early 30s with short curly brown hair and freckles",
                                  photoFileNames: ["1.jpg", "2.jpg", "3.jpg"], createdAt: .now)
        let moodboard = Moodboard(id: UUID(), name: "Warm film", imageFileNames: ["1.jpg", "2.jpg", "3.jpg"],
                                  styleDescription: "Warm 35mm film look with soft golden light, lifted blacks, muted greens and gentle grain.",
                                  createdAt: .now)
        let adCopy: [String: (String, String)] = [
            "ugc-photo": ("she's laughing and holds it next to her face", ""),
            "model-shoot": ("woman in her 30s, short curly hair, minimal makeup", ""),
            "product-shoot": ("with fresh lemons and ice around it", ""),
            "before-after": ("Before | After", ""),
            "testimonial": ("My skin has never felt this soft.", "– Ana, verified buyer ★★★★★"),
            "static-ad": ("Hydration that lasts 72 hours\nVegan glow, all day", "Vegan | Fragrance-free | Shop now"),
            "hook-frame": ("I didn't expect this to work…\nPOV: you finally found it", ""),
            "carousel": ("POV: your skin in winter | The fix | 30 days later", ""),
            "marketplace": ("72-hour hydration | Vegan | Fragrance-free", "Serum | Dropper | Pouch"),
            "recreate-ad": ("Glow that lasts | 30% off today", "make the background pastel blue"),
        ]
        var ads: [[String: Any]] = []
        for tool in AdCatalog.all {
            let copy = adCopy[tool.id] ?? ("sample copy", "sample details")
            let settings = AdSettings(choices: tool.options.map { $0.values.first ?? "" }, text: tool.text == nil ? "" : copy.0,
                                      text2: tool.text2 == nil ? "" : copy.1, product: product, character: nil,
                                      aspect: tool.aspect, count: 1)
            func prompt(_ settings: AdSettings) -> String {
                if tool.isCarousel {
                    let count = Int(settings.choice(1)) ?? 5
                    let beats = AppModel.carouselBeats(story: settings.choice(0), count: count)
                    return AppModel.adPrompt(tool, settings: settings, text: "", extra: [
                        "index": "1", "count": "\(count)", "beat": beats.first ?? "",
                        "caption": AppModel.carouselCaptions(settings.text).first ?? "",
                    ])
                }
                if tool.text?.onePerLine == true {
                    return AppModel.adPrompt(tool, settings: settings, text: AppModel.lines(settings.text).first ?? "")
                }
                return AppModel.adPrompt(tool, settings: settings, text: settings.text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            var empty = settings
            (empty.text, empty.text2) = ("", "")
            let emptyLength = prompt(empty).utf16.count
            let sample = prompt(settings)
            var row = budget(tool.model, overhead: emptyLength)
            row["id"] = tool.id
            row["choices"] = settings.choices
            row["text"] = settings.text
            row["text2"] = settings.text2
            row["prompt"] = sample
            row["length"] = sample.utf16.count
            row["emptyLength"] = emptyLength
            ads.append(row)
        }

        let scene = "a woman walks into a sunlit flower market, smiling"
        let preset = StylePresets.preset("realistic")
        let palette = ColorPalette.builtIn.first
        let camera = CinemaCamera.prompt(body: "35mm", lens: "anamorphic")
        var recipes: [(String, String)] = [
            ("create (empty)", Recipes.create(prompt: "", preset: nil, character: nil, referenceCount: 0)),
            ("create", Recipes.create(prompt: scene, preset: nil, character: nil, referenceCount: 0)),
            ("create (character)", Recipes.create(prompt: scene, preset: nil, character: character, referenceCount: 0)),
            ("create (preset)", Recipes.create(prompt: scene, preset: preset, character: nil, referenceCount: 0)),
            ("create (palette)", Recipes.create(prompt: scene, preset: nil, character: nil, referenceCount: 0, palette: palette)),
            ("create (moodboard)", Recipes.create(prompt: scene, preset: nil, character: nil, referenceCount: 0, moodboard: moodboard,
                                                  styleImages: 1...3)),
            ("create (camera)", Recipes.create(prompt: scene, preset: nil, character: nil, referenceCount: 0, camera: camera)),
            ("create (2 references)", Recipes.create(prompt: scene, preset: nil, character: nil, referenceCount: 2)),
            ("create (quoted text)", Recipes.create(prompt: "a neon sign that reads \"OPEN LATE\" above a diner door", preset: nil,
                                                    character: nil, referenceCount: 0)),
            ("create (everything)", Recipes.create(prompt: scene, preset: preset, character: character, referenceCount: 1,
                                                   camera: camera, palette: palette, moodboard: moodboard, styleImages: 6...8)),
            ("create (character + product)", Recipes.create(prompt: scene, preset: nil, character: character, referenceCount: 0)
                + "\n" + Recipes.productReference(product, imageRange: 4...5)),
            ("storyboard", Recipes.storyboard(scene: scene, index: 0, total: 4, context: "A florist's first day running her own shop.",
                                              preset: preset, character: character)),
            ("edit", Recipes.edit("make the jacket dark green", referenceCount: 0)),
            ("edit (2 references)", Recipes.edit("give her the hat and scarf from the references", referenceCount: 2)),
            ("inpaint", Recipes.inpaint("a small potted cactus")),
            ("drawToEdit (empty)", Recipes.drawToEdit("")),
            ("drawToEdit", Recipes.drawToEdit("make the new window larger")),
            ("upscale (0.2)", Recipes.upscale(creativity: 0.2)),
            ("upscale (0.5)", Recipes.upscale(creativity: 0.5)),
            ("upscale (0.9)", Recipes.upscale(creativity: 0.9)),
            ("relight", Recipes.relight(preset: LightPreset.preset("golden-hour"), direction: CGPoint(x: -0.6, y: -0.5),
                                        color: .orange, intensity: 0.5, hard: false, extra: "")),
            ("relight (hard, extra)", Recipes.relight(preset: LightPreset.preset("neon"), direction: CGPoint(x: 0.6, y: 0.5),
                                                      color: .purple, intensity: 0.9, hard: true, extra: "add rain on the window")),
            ("orbit (45, 20, 1.3)", Recipes.orbit(rotation: 45, tilt: 20, zoom: 1.3)),
            ("orbit (180, -15, 0.7)", Recipes.orbit(rotation: 180, tilt: -15, zoom: 0.7)),
            ("editText", Recipes.editText([("SUMMER SALE", "WINTER SALE"), ("50% OFF", "30% OFF")])),
            ("expand (empty)", Recipes.expand(extra: "")),
            ("expand", Recipes.expand(extra: "a sandy beach with palm trees")),
            ("replaceBackground", Recipes.replaceBackground("a sunlit Parisian street café")),
            ("productReference (1 image)", Recipes.productReference(product, imageRange: 1...1)),
            ("productReference (3 images)", Recipes.productReference(product, imageRange: 2...4)),
            ("faceSwap (keep expression)", Recipes.faceSwap(keepExpression: true)),
            ("faceSwap", Recipes.faceSwap(keepExpression: false)),
            ("characterSwap", Recipes.characterSwap(details: character.details, extra: "")),
            ("characterSwap (extra)", Recipes.characterSwap(details: "", extra: "she holds a coffee cup")),
            ("outfitSwap", Recipes.outfitSwap(extra: "")),
            ("outfitSwap (extra)", Recipes.outfitSwap(extra: "tuck the shirt in")),
            ("placement (zones)", Recipes.placement(withZones: true, placement: "standing upright on the counter")),
            ("placement (no zones)", Recipes.placement(withZones: false, placement: "")),
            ("product (scene)", Recipes.product(sceneProvided: true, placement: "")),
            ("product (no scene)", Recipes.product(sceneProvided: false, placement: "on wet black stone with soft mist")),
        ]
        recipes += CameraAngle.all.map { ("angle (\($0.id))", Recipes.angle($0)) }

        let json: [String: Any] = [
            "apps": apps,
            "ads": ads,
            "recipes": recipes.map { ["name": $0.0, "prompt": $0.1, "length": $0.1.utf16.count] },
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private typealias WindowImageFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    private static func snapshot(to path: String, frontmost: Bool) {
        let symbol = dlopen(nil, RTLD_NOW).flatMap { dlsym($0, "CGWindowListCreateImage") }
        let capture = symbol.map { unsafeBitCast($0, to: WindowImageFunction.self) }
        let windows = NSApp.orderedWindows.filter { $0.isVisible && $0.frame.width > 200 && $0.sheetParent == nil }
        let main = windows.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        guard let window = frontmost ? windows.first : main else { return }
        let ids = [window] + (window.attachedSheet.map { [$0] } ?? [])
        var images: [(NSWindow, CGImage)] = []
        for item in ids {
            if let image = capture?(.null, 1 << 3, UInt32(item.windowNumber), 1 << 0)?.takeRetainedValue() {
                images.append((item, image))
            }
        }
        let note = "symbol:\(symbol != nil) windows:\(windows.count) captured:\(images.count)\n"
        try? note.write(toFile: path + ".log", atomically: true, encoding: .utf8)
        if images.isEmpty, let layerImage = layerSnapshot(window) { images.append((window, layerImage)) }
        guard let (main, base) = images.first else { return }
        let scale = CGFloat(base.width) / main.frame.width
        guard let context = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        for (sheet, image) in images.dropFirst() {
            let x = (sheet.frame.minX - main.frame.minX) * scale
            let y = (sheet.frame.minY - main.frame.minY) * scale
            context.draw(image, in: CGRect(x: x, y: y, width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        guard let composed = context.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: composed)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
