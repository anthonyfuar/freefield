import Foundation
import FreefieldCore
import SwiftUI

enum SceneElementKind: String, Codable, CaseIterable, Identifiable {
    case location
    case prop

    var id: Self { self }

    var title: String { self == .location ? L("Locations") : L("Objects") }
    var singular: String { self == .location ? L("Location") : L("Object") }
    var newTitle: String { self == .location ? L("New Location") : L("New Object") }
    var systemImage: String { self == .location ? "mountain.2" : "lamp.desk" }

    var page: CharactersPage { self == .location ? .locations : .props }
}

struct SceneElement: Identifiable, Codable, Hashable {
    static let maxPhotos = 5

    let id: UUID
    var kind: SceneElementKind
    var name: String
    var details: String
    var photoFileNames: [String]
    var createdAt: Date
}

enum CharactersPage: String, CaseIterable, Identifiable {
    case people
    case locations
    case props
    case builder

    var id: Self { self }

    static let tabs: [CharactersPage] = [.people, .locations, .props]

    var kind: SceneElementKind? {
        switch self {
        case .locations: .location
        case .props: .prop
        default: nil
        }
    }

    var title: String {
        switch self {
        case .people: L("People")
        case .locations: L("Locations")
        case .props: L("Objects")
        case .builder: L("Design a Character")
        }
    }

    var systemImage: String {
        switch self {
        case .people: "person.2"
        case .locations: SceneElementKind.location.systemImage
        case .props: SceneElementKind.prop.systemImage
        case .builder: "wand.and.sparkles"
        }
    }
}

struct SceneCast {
    var images: [InputImage] = []
    var recipe = ""
    var userTexts: [String] = []
}

enum SceneRecipes {
    static let maxPeople = 5

    private static func images(_ first: Int, _ count: Int) -> String? {
        switch count {
        case ..<1: nil
        case 1: "Image \(first)"
        default: "Images \(first)–\(first + count - 1)"
        }
    }

    private static func named(_ name: String, _ details: String) -> String {
        let name = name.trimmingCharacters(in: .whitespaces)
        let details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return details.isEmpty ? name : "\(name) (\(details))"
    }

    static func person(_ character: Character, first: Int, count: Int) -> String {
        let who = named(character.name, character.details)
        guard let refs = images(first, count) else {
            return "Also in the scene: another person, \(who)."
        }
        let one = count == 1
        return "\(refs) \(one ? "is the identity reference" : "are identity references") for another person, \(who). Keep their face, facial structure, skin tone and hair identical to \(one ? "that reference" : "those references")."
    }

    static func together(_ count: Int) -> String {
        "Show all \(count) people together in the same scene, each one clearly recognizable as their own reference. Never merge, swap or blend their faces."
    }

    static func element(_ element: SceneElement, first: Int, count: Int) -> String {
        let what = named(element.name, element.details)
        let refs = images(first, count)
        let verb = count == 1 ? "shows" : "show"
        switch element.kind {
        case .location:
            guard let refs else { return "Set the scene in this place: \(what)." }
            return "\(refs) \(verb) the location: \(what). Set the scene in this exact place, with the same architecture, layout, materials, colors and landmarks; only the camera angle and light may change to fit the description."
        case .prop:
            guard let refs else { return "Include this object: \(what)." }
            return "\(refs) \(verb) an object to include: \(what). Show this exact object with the same shape, proportions, materials, colors and markings."
        }
    }
}

extension AppModel {
    func castCharacters(for state: ComposerState) -> [Character] {
        var seen: Set<UUID> = state.characterID.map { [$0] } ?? []
        return state.castIDs.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return library.character(id)
        }
    }

    func sceneElements(for state: ComposerState) -> [SceneElement] {
        var seen: Set<UUID> = []
        return state.elementIDs.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return library.element(id)
        }
    }

    func maxPeople(for model: ImageModel?) -> Int {
        guard let model, model.acceptsImageInput else { return 1 }
        return max(1, min(SceneRecipes.maxPeople, model.maxReferences))
    }

    func primaryCharacterImageLimit(for state: ComposerState, model: ImageModel) -> Int {
        let others = castCharacters(for: state).count + sceneElements(for: state).count
        guard others > 0 else { return min(4, model.maxReferences) }
        return max(1, min(3, model.maxReferences / (others + 1)))
    }

    func sceneCast(for state: ComposerState, model: ImageModel, firstImage: Int) -> SceneCast {
        let people = castCharacters(for: state)
        let elements = sceneElements(for: state)
        var cast = SceneCast()
        guard !people.isEmpty || !elements.isEmpty else { return cast }
        var room = model.acceptsImageInput ? max(0, model.maxReferences - firstImage + 1) : 0
        let share = max(1, min(3, room / (people.count + elements.count)))
        var next = firstImage
        var lines: [String] = []
        for person in people {
            let photos = room > 0 ? library.referenceImages(for: person, limit: min(share, room)) : []
            room -= photos.count
            cast.images += photos
            lines.append(SceneRecipes.person(person, first: next, count: photos.count))
            next += photos.count
            cast.userTexts += [person.name, person.details]
        }
        for element in elements {
            let photos = room > 0 ? library.elementImages(for: element, limit: min(min(share, 2), room)) : []
            room -= photos.count
            cast.images += photos
            lines.append(SceneRecipes.element(element, first: next, count: photos.count))
            next += photos.count
            cast.userTexts += [element.name, element.details]
        }
        if !people.isEmpty {
            lines.append(SceneRecipes.together(people.count + (library.character(state.characterID) == nil ? 0 : 1)))
        }
        cast.recipe = lines.joined(separator: "\n")
        cast.userTexts = cast.userTexts.filter { !$0.isEmpty }
        return cast
    }

    func attach(_ element: SceneElement, to state: ComposerState) {
        var ids = state.elementIDs
        if element.kind == .location {
            ids.removeAll { library.element($0)?.kind == .location }
        }
        if !ids.contains(element.id) { ids.append(element.id) }
        state.elementIDs = ids
    }

    func addToCast(_ character: Character, in state: ComposerState, limit: Int) {
        if library.character(state.characterID) == nil {
            state.characterID = character.id
            return
        }
        guard state.characterID != character.id, !state.castIDs.contains(character.id) else { return }
        guard castCharacters(for: state).count + 1 < limit else { return }
        state.castIDs.append(character.id)
    }

    func removeFromCast(_ id: UUID, in state: ComposerState) {
        if state.characterID == id {
            let rest = castCharacters(for: state)
            state.characterID = rest.first?.id
            state.castIDs = Array(rest.dropFirst().map(\.id))
        } else {
            state.castIDs.removeAll { $0 == id }
        }
    }

    func use(_ element: SceneElement, inVideo toolID: String) {
        guard let tool = VideoCatalog.tool(toolID), let slot = tool.slot(.imageReferences) else { return }
        let state = videoState(for: tool)
        let photos = library.elementPhotoData(element).prefix(2)
        state.references = Array((state.references + photos).prefix(slot.maxCount))
        openVideo(tool.id)
    }

    func use(_ element: SceneElement, in tool: Tool) {
        let state = composer(for: tool)
        if tool == .create {
            attach(element, to: state)
        } else {
            state.references = Array((state.references + library.elementPhotoData(element).prefix(2)).prefix(14))
        }
        selection = .tool(tool)
    }

    static let elementVideoTools = ["createVideo", "cinemaStudio"]
}
