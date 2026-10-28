import FreefieldCore
import SwiftUI

struct PhotoSessionSet: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let symbol: String
    let scenes: [String]

    static let all: [PhotoSessionSet] = [
        PhotoSessionSet(id: "candid-glow", name: L("Candid Glow"), summary: L("Natural moments at golden hour."), symbol: "sun.max", scenes: [
            "laughing candidly on a rooftop at golden hour, hair blowing in the wind",
            "walking down a sunlit street holding an iced coffee, caught mid-step",
            "sitting on a café terrace, looking away from the camera, warm backlight",
            "close-up portrait with sun flare across the face, soft smile",
            "leaning out of a car window on a coastal road at sunset",
            "dancing barefoot in a field of tall grass at dusk",
            "reading on a park bench, dappled light through leaves",
            "mirror selfie in a vintage shop with warm lamps",
            "eating gelato on old town steps, candid laugh",
        ]),
        PhotoSessionSet(id: "sleepy-head", name: L("Slow Morning"), summary: L("Bed, coffee and soft light."), symbol: "bed.double", scenes: [
            "waking up in white linen sheets, messy hair, soft morning window light",
            "holding a warm mug of coffee by the window in an oversized sweater",
            "lying on the bed scrolling the phone, top-down view",
            "brushing teeth in a bright bathroom mirror, candid",
            "curled up on a sofa under a knitted blanket with a book",
            "making pancakes in pajamas in a cozy kitchen",
            "sitting on the balcony at sunrise wrapped in a duvet",
            "napping with a cat on the bed, afternoon light",
            "sleepy selfie with a sleep mask on the forehead",
        ]),
        PhotoSessionSet(id: "zen", name: L("Zen"), summary: L("Calm, yoga, tea and nature."), symbol: "leaf", scenes: [
            "doing a yoga pose on a wooden deck surrounded by jungle",
            "meditating cross-legged by a calm lake at dawn",
            "pouring matcha in a minimalist Japanese tea room",
            "walking through a bamboo forest path, serene",
            "floating in a natural hot spring with mist rising",
            "journaling at a linen-covered table with dried flowers",
            "stretching on a beach at sunrise",
            "tending to plants in a sunlit greenhouse",
            "sitting on stone steps of a temple garden",
        ]),
        PhotoSessionSet(id: "office-dresscode", name: L("Office Style"), summary: L("Suits and confidence at work."), symbol: "briefcase", scenes: [
            "walking into a glass office lobby in a tailored suit, power stride",
            "sitting on the edge of a desk with a laptop, confident look",
            "in a sleek elevator mirror, outfit check",
            "presenting at a whiteboard in a modern meeting room",
            "coffee break at a city café in business casual",
            "crossing the street in the financial district at rush hour",
            "rooftop terrace after work, blazer over the shoulder",
            "close-up of hands typing with a statement watch",
            "candid laugh with colleagues in an open-plan office",
        ]),
        PhotoSessionSet(id: "surreal-self", name: L("Surreal Self"), summary: L("Impossible, dreamlike scenes."), symbol: "moon.stars", scenes: [
            "standing on a giant floating teacup above the clouds",
            "walking on a staircase that loops into the sky",
            "sitting inside a room filled entirely with pink balloons",
            "riding a giant goldfish through a city street",
            "reflection in the mirror shows a different season",
            "lying on the surface of the moon in a silk dress",
            "holding an umbrella under a rain of flower petals indoors",
            "a door in the middle of the desert opening onto the ocean",
            "giant version of themselves peeking into a dollhouse city",
        ]),
        PhotoSessionSet(id: "alter-ego", name: L("Other Lives"), summary: L("Rock star, astronaut, chef…"), symbol: "theatermasks", scenes: [
            "as a 1970s rock star on stage under spotlights",
            "as an astronaut floating in a space station",
            "as a Formula 1 driver in the pit lane",
            "as a renaissance noble in an oil-painting style portrait",
            "as a chef plating food in a Michelin kitchen",
            "as a film noir detective in a rainy alley",
            "as a surfer riding a huge wave",
            "as a ballet dancer backstage at the opera",
            "as a fashion designer in a messy atelier",
        ]),
        PhotoSessionSet(id: "cool-girl", name: L("Everyday Casual"), summary: L("Little moments, with style."), symbol: "camera.aperture", scenes: [
            "flash photo at a dinner party holding a glass of wine",
            "mirror selfie in an outfit with sunglasses on",
            "sitting on a vintage car in the city at night",
            "close-up of rings and nails holding a coffee",
            "candid on the subway with headphones",
            "record store browsing vinyl, candid",
            "beach day with a striped towel and film camera",
            "night street with neon signs, blurry motion",
            "photobooth strip with friends making faces",
        ]),
        PhotoSessionSet(id: "male-archive", name: L("Classic Menswear"), summary: L("Timeless and elegant, for him."), symbol: "figure.stand", scenes: [
            "leaning on a motorcycle in a leather jacket at dusk",
            "barbershop chair candid, hot towel and mirror",
            "walking in a wool coat through a snowy city",
            "black-and-white portrait with cigarette smoke-like mist, moody",
            "fishing on a dock at sunrise",
            "tailor fitting a suit in an old atelier",
            "playing basketball on a street court",
            "reading a newspaper at a Parisian café",
            "hiking ridge with a backpack, epic mountains",
        ]),
        PhotoSessionSet(id: "travel", name: L("Trip"), summary: L("Around the world in one session."), symbol: "airplane", scenes: [
            "boarding a plane at a sunny airport gate",
            "Santorini white rooftops and blue domes at sunset",
            "street food market in Bangkok at night",
            "Times Square at night, candid crossing",
            "hot air balloons over Cappadocia at sunrise",
            "train window seat through the Swiss Alps",
            "Kyoto lantern alley in the evening",
            "Mexico City colorful street with papel picado",
            "hotel balcony overlooking the sea with breakfast",
        ]),
    ]
}

struct PhotoSessionView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedAssetID: UUID?
    @State private var ownPhotos: [Data] = []
    @State private var showControls = true
    @State private var canvasWidth: CGFloat = 0
    @AppStorage("lastCharacterID") private var lastCharacterID = ""

    private var state: ComposerState { app.composer(for: .photoSession) }

    var body: some View {
        PhotoSessionResults(selectedAssetID: $selectedAssetID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { canvasWidth = $0 }
            .navigationTitle(Tool.photoSession.title)
            .canvasSubtitle(L("Different scenes, the same star"), canvasWidth: canvasWidth)
            .inspector(isPresented: $showControls) {
                controls
                    .toolPanelWidth()
            }
            .toolbar {
                ToolbarItem {
                    Button(L("Controls"), systemImage: "sidebar.right") { showControls.toggle() }
                        .help(L("Show or hide controls (⌥⌘I)"))
                        .keyboardShortcut("i", modifiers: [.command, .option])
                }
            }
            .onAppear {
                if state.aspectRatio == .auto { state.aspectRatio = .portrait3x4 }
                preselectCharacter()
            }
            .onChange(of: state.characterID) { _, id in
                if let id { lastCharacterID = id.uuidString }
            }
    }

    private var controls: some View {
        @Bindable var state = state
        let character = app.library.character(state.characterID)
        let requirement = ModelRequirement(images: 1)
        let model = app.resolvedModel(for: state, requirement: requirement)
        let set = PhotoSessionSet.all.first { $0.id == state.sessionSetID } ?? PhotoSessionSet.all[0]
        let reason = disabledReason(model: model, character: character)
        let hasStar = character != nil || (app.library.characters.isEmpty && !ownPhotos.isEmpty)
        let cost = app.estimatedCost(model: model, count: state.sessionShots, resolution: state.resolution)
        let create = {
            guard let model, reason == nil, let character = character ?? saveOwnPhotos() else { return }
            app.runPhotoSession(state, set: set, model: model, character: character)
        }

        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 12) {
                            PanelSection(title: L("Your character"), step: 1, isDone: hasStar) {
                                characterPicker(selection: $state.characterID)
                            }
                            ExtraInstructionField(text: $state.prompt, placeholder: L("E.g. the same red dress in every photo, in Oaxaca"),
                                                  limit: PromptBudget.userLimit(model: model, overhead: app.photoSessionOverhead(set: set, character: character)))
                        }
                        PanelSection(title: L("Choose the theme"), step: 2, isDone: hasStar) {
                            let pictures = OptionImages.pictures(family: "sessions", values: PhotoSessionSet.all.map(\.id))
                            OptionGrid(minimum: pictures == nil ? 130 : PanelLayout.pictureCardMinimum) {
                                ForEach(PhotoSessionSet.all) { item in
                                    OptionTile(title: item.name, subtitle: item.summary, systemImage: item.symbol,
                                               picture: pictures?[item.id], isSelected: state.sessionSetID == item.id) {
                                        state.sessionSetID = item.id
                                    }
                                }
                            }
                        }
                        PanelSection(title: L("How many photos"), step: 3, isDone: hasStar) {
                            Picker(L("Photos"), selection: $state.sessionShots) {
                                ForEach([3, 6, 9], id: \.self) { Text("\($0)").tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                    ExtrasHeader()
                    OptionalSection(L("More options"), systemImage: "slider.horizontal.3",
                                    summary: [state.aspectRatio.label,
                                              state.modelID == nil ? L("Auto") : model.map { app.catalog.choice(for: $0).displayName } ?? ""]
                                        .filter { !$0.isEmpty }.joined(separator: " · "),
                                    storageKey: "photoSession.moreOptions") {
                        FlowLayout(spacing: 8) {
                            if let model, !model.aspectRatios.isEmpty {
                                AspectRatioMenu(selection: $state.aspectRatio, available: model.aspectRatios)
                            }
                            ModelPicker(selectionID: $state.modelID, current: model, requirement: requirement)
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            VStack(spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    GenerateButton(title: L("Create %ld-Photo Session", state.sessionShots), isEnabled: reason == nil,
                                   disabledReason: reason, estimatedCost: cost, size: .extraLarge, action: create)
                    GenerateButton(title: L("Create %ld-Photo Session", state.sessionShots), isEnabled: reason == nil,
                                   disabledReason: reason, estimatedCost: cost, action: create)
                }
                .frame(maxWidth: .infinity)
                DisabledReasonLabel(reason: reason)
            }
            .animation(reduceMotion ? nil : Motion.standard, value: reason)
            .padding(16)
        }
    }

    private func characterPicker(selection: Binding<UUID?>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if app.library.characters.isEmpty {
                Text(L("Upload 1–5 photos of yourself"))
                    .font(.callout.weight(.medium))
                ReferenceStrip(images: $ownPhotos, limit: 5, label: L("Your photos"))
                Text(ownPhotos.isEmpty
                     ? L("Clear photos of your face, from the front and the side. They're saved in Characters as “%@”.", Self.ownCharacterName)
                     : L("Saved in Characters as “%@” when you create the session.", Self.ownCharacterName))
                    .helperTextStyle()
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Or create a character with more details…")) {
                    app.selection = .characters
                    app.creatingCharacter = true
                }
                .buttonStyle(.link)
                .font(.callout)
            } else {
                CharacterTiles(selection: selection)
                Button(L("New character…"), systemImage: "plus") {
                    app.selection = .characters
                    app.creatingCharacter = true
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
    }

    private func preselectCharacter() {
        guard app.library.character(state.characterID) == nil else { return }
        if let last = UUID(uuidString: lastCharacterID), app.library.character(last) != nil {
            state.characterID = last
        } else if app.library.characters.count == 1 {
            state.characterID = app.library.characters[0].id
        }
    }

    private func disabledReason(model: ImageModel?, character: Character?) -> String? {
        if !app.hasAnyKey { return L("Add an API key") }
        if character == nil, ownPhotos.isEmpty || !app.library.characters.isEmpty {
            return app.library.characters.isEmpty ? L("Add 1–5 photos of yourself") : L("Choose a character")
        }
        if model == nil { return app.catalog.isLoading ? L("Loading models…") : L("No model available") }
        return nil
    }

    static var ownCharacterName: String { L("Me") }

    private func saveOwnPhotos() -> Character? {
        guard !ownPhotos.isEmpty else { return nil }
        let character = app.library.addCharacter(name: Self.ownCharacterName, details: "", photos: ownPhotos)
        guard !character.photoFileNames.isEmpty else { return nil }
        state.characterID = character.id
        ownPhotos = []
        return character
    }
}

private struct CharacterTiles: View {
    @Binding var selection: UUID?
    @Environment(AppModel.self) private var app

    var body: some View {
        let characters = app.library.characters
        ExpandableOptionGrid(values: characters.map(\.id.uuidString), columns: 3, minimum: 70, rows: 2,
                             selection: selection?.uuidString) { id in
            if let character = characters.first(where: { $0.id.uuidString == id }) {
                OptionTile(title: character.name, systemImage: "person.crop.square",
                           picture: OptionPicture(url: cover(of: character), aspect: 1),
                           isSelected: selection == character.id, compact: true) {
                    selection = character.id
                }
            }
        }
    }

    private func cover(of character: Character) -> URL? {
        let names = character.photoFileNames
        guard !names.isEmpty else { return nil }
        return app.library.characterPhotoURL(names[min(max(0, character.coverIndex), names.count - 1)])
    }
}

struct PhotoSessionResults: View {
    @Binding var selectedAssetID: UUID?
    @Environment(AppModel.self) private var app

    var body: some View {
        let feed = FeedModel(app: app, tool: .photoSession)
        if feed.isEmpty {
            VStack(spacing: 18) {
                ContentUnavailableView {
                    Label(L("Your session will appear here"), systemImage: "photo.stack")
                } description: {
                    Text(L("Choose your character and a theme. Freefield creates several different scenes starring you."))
                }
                if let example = Examples.tool(.photoSession) {
                    ToolExampleCard(example: example)
                        .frame(maxWidth: 560, maxHeight: 220)
                }
            }
            .padding(24)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    videoBar
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                        ForEach(feed.batches) { batch in
                            if let slot = batch.slots.first {
                                FeedSlotView(slot: slot, batch: batch, failedAspect: 0.75) { asset in
                                    AssetCard(asset: asset, isSelected: selectedAssetID == asset.id, maxPixel: 600)
                                        .onTapGesture { selectedAssetID = asset.id }
                                        .onTapGesture(count: 2) { app.quickLook(asset) }
                                }
                            }
                        }
                    }
                    .animation(Motion.emphasized, value: feed.slotKeys)
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder private var videoBar: some View {
        let sessions = PhotoSessionRuns.all(in: app.library.assets)
        if let session = sessions.first(where: { $0.shots.contains { $0.asset.id == selectedAssetID } }) ?? sessions.first {
            let isFinished = !app.engine.jobs.contains { $0.tool == .photoSession && $0.isRunning && $0.createdAt < session.date }
            HStack(spacing: 10) {
                Label(session.title, systemImage: "photo.stack")
                    .fineTextStyle()
                    .lineLimit(1)
                Spacer()
                Button(L("Make a Video"), systemImage: "video.badge.plus") {
                    app.makeStoryboardVideo(session.shots.map { (asset: $0.asset, action: $0.scene) })
                }
                .buttonStyle(.glass)
                .disabled(!isFinished)
                .help(isFinished ? L("Sends up to 8 photos of this session, in order, to Photos to Video")
                                 : L("Wait until every photo is ready"))
            }
        }
    }
}

struct PhotoSessionRun: Identifiable {
    let id: UUID
    let date: Date
    let set: String
    let characterID: UUID?
    var shots: [(asset: Asset, scene: String)]

    var title: String {
        [L("%ld photos", shots.count), date.formatted(date: .abbreviated, time: .shortened), L(set)].joined(separator: " · ")
    }
}

enum PhotoSessionRuns {
    static func all(in assets: [Asset]) -> [PhotoSessionRun] {
        let photos = assets.filter { $0.tool == .photoSession && !$0.isVideo }.sorted { $0.createdAt < $1.createdAt }
        var runs: [PhotoSessionRun] = []
        for asset in photos {
            guard let colon = asset.prompt.firstRange(of: ": ") else { continue }
            let set = String(asset.prompt[..<colon.lowerBound]), scene = String(asset.prompt[colon.upperBound...])
            if var current = runs.last, current.set == set, current.characterID == asset.characterID,
               !current.shots.contains(where: { $0.scene == scene }), let last = current.shots.last,
               asset.createdAt.timeIntervalSince(last.asset.createdAt) < 30 * 60 {
                current.shots.append((asset: asset, scene: scene))
                runs[runs.count - 1] = current
            } else {
                runs.append(PhotoSessionRun(id: asset.id, date: asset.createdAt, set: set, characterID: asset.characterID,
                                            shots: [(asset: asset, scene: scene)]))
            }
        }
        return runs.filter { $0.shots.count >= 2 }.reversed()
    }
}
