import SwiftUI

struct CameraMovePicker: View {
    @Binding var selection: [String]
    @Binding var strength: String
    var limit = CameraMoves.maxMix

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var groupName = Self.allGroups
    @FocusState private var searchIsFocused: Bool

    private static let allGroups = L("All")
    private static var groupNames: [String] { [allGroups] + CameraMoveGroup.allCases.map(\.title) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView { grid.padding(20) }
            Divider()
            footer
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 600, idealHeight: 720)
        .onAppear { searchIsFocused = true }
        .onExitCommand { dismiss() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Camera moves")).font(.title2.bold())
                Spacer()
                Text(L("%ld of %ld picked", selection.count, CameraMoves.maxMix))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(selection.count)))
            }
            Text(L("Video models have no camera controls, so each move is written into the instructions. Pick up to three: they play in order, one after another. Clips under 5 seconds fit one move."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                TextField(L("Search camera moves"), text: $search)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchIsFocused)
                    .onSubmit(pickFirstMatch)
                    .accessibilityHint(Text(L("Return picks the first match")))
                VStack(alignment: .trailing, spacing: 4) {
                    Picker(L("Strength"), selection: $strength) {
                        ForEach(CameraStrength.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .help(L("How strongly the moves play"))
                    Text(strengthNote).fineTextStyle()
                }
            }
            CategoryChips(categories: Self.groupNames, selection: $groupName, compact: true)
        }
        .padding(20)
    }

    private var strengthNote: String {
        switch CameraStrength(rawValue: strength) ?? .normal {
        case .subtle: L("Slow, gentle moves that keep the focus on the subject.")
        case .normal: L("Smooth moves at medium speed.")
        case .strong: L("Fast, dramatic moves with more energy.")
        }
    }

    private struct Section: Identifiable {
        let group: CameraMoveGroup
        let moves: [CameraMove]
        var id: CameraMoveGroup { group }
    }

    private var shown: [Section] {
        let found = Set(CameraMoves.search(search).map(\.id))
        let chosen = CameraMoveGroup.allCases.first { $0.title == groupName }
        return CameraMoveGroup.allCases
            .filter { chosen == nil || $0 == chosen }
            .map { group in Section(group: group, moves: CameraMoves.moves(in: group).filter { found.contains($0.id) }) }
            .filter { !$0.moves.isEmpty }
    }

    @ViewBuilder private var grid: some View {
        let sections = shown
        if sections.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(section.group.title, systemImage: section.group.symbol)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
                            ForEach(section.moves) { move in
                                let order = selection.firstIndex(of: move.id).map { $0 + 1 }
                                CameraMoveTile(move: move, order: order, isLeftOut: (order ?? 0) > limit) { toggle(move.id) }
                                    .disabled(order == nil && selection.count >= CameraMoves.maxMix)
                            }
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Group {
                    if selection.isEmpty {
                        Text(L("No move picked: the model chooses the camera."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(Array(selection.enumerated()), id: \.element) { index, id in
                                if let move = CameraMoves.move(id) {
                                    HStack(spacing: 8) {
                                        if index > 0 {
                                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                                                .accessibilityHidden(true)
                                        }
                                        chip(move, index: index)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(L("Clear")) { withAnimation(Motion.standard) { selection = [] } }
                    .disabled(selection.isEmpty)
                    .keyboardShortcut(.delete, modifiers: [.command, .option])
                    .help(L("Clear all moves (⌥⌘⌫)"))
                Button(L("Done")) { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help(L("Done (⌘↩)"))
            }
            if selection.count > limit {
                Label(limit == 1 ? L("This clip fits one move; the others are left out.")
                      : L("This clip fits %ld moves; the others are left out.", limit), systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if selection.prefix(limit).compactMap(CameraMoves.move).contains(where: \.isBig) {
                Label(L("Big camera moves like orbits, FPV flights and crash zooms work best on Kling or Veo."), systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func chip(_ move: CameraMove, index: Int) -> some View {
        HStack(spacing: 6) {
            CameraMoveNumber(number: index + 1, isLeftOut: index >= limit)
            Text(move.name).font(.callout).lineLimit(1)
            Button {
                withAnimation(Motion.standard) { selection.removeAll { $0 == move.id } }
            } label: {
                Image(systemName: "xmark").font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L("Remove %@", move.name))
            .accessibilityLabel(Text(L("Remove %@", move.name)))
        }
        .padding(.leading, 4).padding(.trailing, 8).padding(.vertical, 4)
        .glassEffect(in: .capsule)
        .contextMenu {
            Button(L("Play Earlier"), systemImage: "chevron.left") { reorder(at: index, by: -1) }.disabled(index == 0)
            Button(L("Play Later"), systemImage: "chevron.right") { reorder(at: index, by: 1) }.disabled(index >= selection.count - 1)
            Divider()
            Button(L("Remove"), systemImage: "xmark", role: .destructive) { selection.removeAll { $0 == move.id } }
        }
    }

    private func toggle(_ id: String) {
        withAnimation(Motion.standard) {
            if let index = selection.firstIndex(of: id) {
                selection.remove(at: index)
            } else if selection.count < CameraMoves.maxMix {
                selection.append(id)
            }
        }
    }

    private func reorder(at index: Int, by offset: Int) {
        let target = index + offset
        guard selection.indices.contains(index), selection.indices.contains(target) else { return }
        withAnimation(Motion.standard) { selection.swapAt(index, target) }
    }

    private func pickFirstMatch() {
        guard selection.count < CameraMoves.maxMix,
              let first = shown.flatMap(\.moves).first(where: { !selection.contains($0.id) }) else { return }
        toggle(first.id)
    }
}

struct CameraMoveTile: View {
    let move: CameraMove
    let order: Int?
    var isLeftOut = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let isPicked = order != nil && !isLeftOut
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: move.symbol)
                    .iconSymbol(IconScale.medium)
                    .foregroundStyle(Color.brand)
                    .frame(height: 28)
                Text(move.name)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .padding(.horizontal, 6)
            .background(isPicked ? Color.appAccent.opacity(0.12) : Color.primary.opacity(0.05), in: .rect(cornerRadius: Radius.tile))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.tile)
                    .strokeBorder(order != nil ? (isLeftOut ? Color.orange : .appAccent) : .primary.opacity(0.08),
                                  lineWidth: order != nil ? 2.5 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if let order { CameraMoveNumber(number: order, isLeftOut: isLeftOut).padding(6) }
            }
            .overlay(alignment: .topLeading) {
                if move.isBig {
                    Text(L("Big"))
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.primary.opacity(0.1), in: .capsule)
                        .padding(6)
                }
            }
            .contentShape(.rect(cornerRadius: Radius.tile))
        }
        .buttonStyle(CardButtonStyle(isCompact: true))
        .opacity(isEnabled ? 1 : 0.45)
        .help(helpText)
        .accessibilityLabel(Text(move.name))
        .accessibilityValue(Text(order.map { L("Number %ld in the order", $0) } ?? ""))
        .accessibilityHint(Text(move.isBig ? L("A big move: works best on Kling or Veo") : ""))
        .accessibilityAddTraits(order != nil ? .isSelected : [])
    }

    private var helpText: String {
        if !isEnabled { return L("Up to %ld moves; remove one to pick another.", CameraMoves.maxMix) }
        if isLeftOut { return L("Left out: this clip is too short for this many moves.") }
        return move.isBig ? L("%@ · a big move: works best on Kling or Veo", move.name) : move.name
    }
}

struct CameraMoveNumber: View {
    let number: Int
    var isLeftOut = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("\(number)")
            .font(.caption.weight(.bold).monospacedDigit())
            .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(number)))
            .frame(width: 20, height: 20)
            .background(isLeftOut ? Color.orange : .appAccent, in: .circle)
            .foregroundStyle(.white)
            .accessibilityHidden(true)
    }
}

extension CameraMove {
    var symbol: String { CameraMoveSymbols.byID[id] ?? group.symbol }
}

private enum CameraMoveSymbols {
    static let byID: [String: String] = [
        "static": "lock",
        "general": "scribble.variable",
        "zoom-in": "plus.magnifyingglass",
        "zoom-out": "minus.magnifyingglass",
        "dolly-in": "arrow.down.right.and.arrow.up.left",
        "dolly-out": "arrow.up.left.and.arrow.down.right",
        "dolly-left": "arrow.left",
        "dolly-right": "arrow.right",
        "pan-left": "arrow.turn.up.left",
        "pan-right": "arrow.turn.up.right",
        "tilt-up": "arrow.uturn.up",
        "tilt-down": "arrow.uturn.down",
        "pedestal-up": "arrow.up",
        "pedestal-down": "arrow.down",
        "arc-left": "arrow.counterclockwise",
        "arc-right": "arrow.clockwise",
        "handheld": "hand.raised",
        "overhead": "map",
        "tracking": "figure.walk",
        "side-tracking": "figure.walk.motion",
        "crane-up": "arrow.up.to.line",
        "crane-down": "arrow.down.to.line",
        "crane-over-the-head": "rainbow",
        "jib-up": "arrow.up.right",
        "jib-down": "arrow.down.right",
        "360-orbit": "arrow.triangle.2.circlepath",
        "drone-orbit": "arrow.2.circlepath",
        "aerial-pullback": "airplane.departure",
        "helicopter-shot": "airplane.circle",
        "fpv-drone": "drone",
        "hero-cam": "figure.stand",
        "super-dolly-in": "arrow.down.forward.and.arrow.up.backward.circle",
        "super-dolly-out": "arrow.up.backward.and.arrow.down.forward.circle",
        "through-object-in": "door.left.hand.open",
        "through-object-out": "door.right.hand.open",
        "crash-zoom-in": "bolt",
        "crash-zoom-out": "bolt.horizontal",
        "rapid-zoom-in": "plus.viewfinder",
        "rapid-zoom-out": "viewfinder",
        "whip-pan": "wind",
        "yoyo-zoom": "repeat",
        "wiggle": "waveform.path",
        "robo-arm": "gearshape.2",
        "flying-cam-transition": "paperplane",
        "bullet-time": "camera.rotate",
        "3d-rotation": "rotate.3d",
        "lazy-susan": "rotate.right",
        "eating-zoom": "fork.knife",
        "mouth-in": "mouth",
        "eyes-in": "eye",
        "buckle-up": "steeringwheel",
        "car-chasing": "car.rear",
        "car-grip": "car.side",
        "road-rush": "road.lanes",
        "fisheye": "globe",
        "low-shutter": "camera.shutter.button",
        "hyperlapse": "forward",
        "timelapse-landscape": "sun.horizon",
        "timelapse-human": "person.3",
        "timelapse-glam": "person.and.background.dotted",
        "dolly-zoom-in": "arrow.up.left.and.down.right.magnifyingglass",
        "dolly-zoom-out": "scale.3d",
        "double-dolly": "chevron.forward.2",
        "dutch-angle": "angle",
        "incline": "arrow.up.forward",
        "focus-change": "camera.aperture",
        "snorricam": "person.fill.viewfinder",
        "head-tracking": "face.dashed",
        "object-pov": "cup.and.saucer",
        "pov": "eyeglasses",
        "bts": "video.badge.ellipsis",
        "glam": "comb",
    ]
}
