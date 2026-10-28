import FreefieldCore
import SwiftUI

struct HookCheckView: View {
    let tool: VideoTool

    @Environment(AppModel.self) private var app

    private var reports: HookCheckReports { .shared }

    var body: some View {
        let state = app.videoState(for: tool)
        let source = state.source.assetID.flatMap(app.library.asset)
        VideoToolScreen(tool: tool, state: state) {
            HStack(alignment: .top, spacing: 16) {
                clip(state, source: source)
                    .frame(maxWidth: 420)
                options(state, isReady: source != nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let field = tool.textField("context") {
                ExtraInstructionField(text: Binding(get: { state.texts[field.id] ?? "" }, set: { state.texts[field.id] = $0 }),
                                      placeholder: field.placeholder, title: field.title,
                                      caption: L("Helps the review judge the message and the call to action."), limit: field.limit)
            }
            if let source, let report = reports.byAsset[source.id] {
                HookCheckCard(report: report)
            }
        } bar: {
            checkBar(state, source: source)
        }
    }

    @ViewBuilder private func clip(_ state: VideoState, source: Asset?) -> some View {
        @Bindable var state = state
        if let slot = tool.slot(.sourceVideo) {
            PanelSection(title: slot.title, systemImage: slot.symbol, step: 1, isDone: source != nil) {
                VStack(alignment: .leading, spacing: 6) {
                    VideoSourceWell(pick: $state.source, title: slot.title, hint: slot.hint, showsSharingNote: false, showsTitle: false)
                    Label(L("Private: only eight still frames are sent"), systemImage: "lock.shield")
                        .helperTextStyle()
                        .help(L("Only eight still frames go to Freefield's AI; the clip stays on this Mac."))
                    if let duration = source?.duration, duration > HookCheck.maxSeconds {
                        Label(L("Only the first minute is reviewed."), systemImage: "timer").font(.callout).foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private func options(_ state: VideoState, isReady: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(tool.optionGroups.enumerated()), id: \.element.id) { index, group in
                PanelSection(title: group.title, systemImage: group.id == "platform" ? "iphone" : "target", step: index + 2, isDone: isReady) {
                    if group.values.allSatisfy({ group.details[$0]?.subtitle == nil }) {
                        VideoColumns(minimum: 124, spacing: 6) {
                            ForEach(group.values, id: \.self) { value in
                                OptionTile(title: group.label(value), systemImage: group.details[value]?.symbol,
                                           isSelected: state.choice(group.id, in: tool) == value, compact: true) {
                                    state.choices[group.id] = value
                                }
                            }
                        }
                    } else {
                        VideoColumns(minimum: 96, spacing: 8, fillsRowHeight: true) {
                            ForEach(group.values, id: \.self) { value in
                                let detail = group.details[value]
                                OptionTile(title: group.label(value), subtitle: detail?.subtitle, systemImage: detail?.symbol,
                                           isSelected: state.choice(group.id, in: tool) == value) {
                                    state.choices[group.id] = value
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func checkBar(_ state: VideoState, source: Asset?) -> some View {
        let isWorking = state.localWork.contains(where: \.isRunning)
        let reason: String? = if !app.hasAnyKey {
            L("Add an API key in Settings")
        } else if app.helperModel == nil {
            L("No text model is available for Freefield's AI.")
        } else if source == nil {
            state.source.isEmpty ? L("Add a clip.") : L("This check needs a clip on this Mac, not a link.")
        } else if isWorking {
            L("Reviewing the clip…")
        } else {
            nil
        }
        return VideoLocalBar(title: L("Check Hook"), reason: reason, isWorking: isWorking,
                             label: Label(L("Reviewed by Freefield's AI"), systemImage: "text.bubble"),
                             detail: L("An estimate from eight frames; the sound isn't heard."), estimatedCost: HookCheck.estimate) {
            if let source { app.checkHook(source, tool: tool, state: state) }
        }
    }
}

struct HookCheckReport: Hashable {
    struct Part: Hashable, Identifiable {
        let id: String
        let title: String
        var score: Int?
        var note: String
    }

    let date: Date
    let platform: String
    let goal: String
    var score: Int?
    var parts: [Part] = []
    var suggestions: [String] = []
    var raw: String?
}

@Observable
final class HookCheckReports {
    static let shared = HookCheckReports()
    var byAsset: [UUID: HookCheckReport] = [:]
}

enum HookCheck {
    static let estimate = 0.003
    static let maxSeconds = 60.0
    static let frameCount = 8

    static func frameTimes(duration: Double) -> [Double] {
        let end = max(0, min(duration, maxSeconds) - 0.05)
        guard end >= 4 else {
            return (0..<frameCount).map { end * Double($0) / Double(frameCount - 1) }
        }
        var times: [Double] = [0, 0.5, 1, 1.5, 2.5]
        let rest = frameCount - times.count
        let from = times.last ?? 0
        times += (1...rest).map { from + (end - from) * Double($0) / Double(rest) }
        return times
    }

    static var replyLanguage: String {
        Bundle.main.preferredLocalizations.first?.lowercased().hasPrefix("es") == true ? "Spanish" : "English"
    }

    static func instructions(platform: String, goal: String) -> String {
        """
        You are a short-form video editor reviewing a clip for \(platform); the goal is \(goal.lowercased()). The images are frames of one clip in time order; their timestamps are listed. You can't hear the sound. Judge four things, each with a score from 0 to 100 and one short, concrete sentence: the hook (would the first 1.5 seconds stop someone scrolling?), the pacing (does something change often enough to hold attention?), the clarity (are the subject and the message clear at a glance on a phone?) and the call to action (does it tell viewers what to do, in a way that fits the goal?). Then give an overall score from 0 to 100 and exactly 3 specific, practical suggestions, each one sentence. Write every sentence in \(replyLanguage). Reply with JSON only, in this shape: {"score": 72, "hook": {"score": 80, "note": "…"}, "pacing": {"score": 60, "note": "…"}, "clarity": {"score": 75, "note": "…"}, "cta": {"score": 40, "note": "…"}, "suggestions": ["…", "…", "…"]}
        """
    }

    static func report(from reply: String, platform: String, goal: String) -> HookCheckReport {
        var report = HookCheckReport(date: .now, platform: platform, goal: goal)
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let object = try? JSONSerialization.jsonObject(with: Data(reply[start...end].utf8)) as? [String: Any] else {
            report.raw = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            return report
        }
        func number(_ value: Any?) -> Double? {
            if let value = value as? NSNumber { return value.doubleValue }
            if let value = value as? String { return Double(value.trimmingCharacters(in: CharacterSet(charactersIn: " %"))) }
            return nil
        }
        let labels: [(String, String)] = [("hook", L("Hook")), ("pacing", L("Pacing")), ("clarity", L("Clarity")), ("cta", L("Call to action"))]
        var scores: [Double?] = []
        var notes: [String] = []
        for (key, _) in labels {
            let value = object[key]
            if let part = value as? [String: Any] {
                scores.append(number(part["score"]))
                notes.append((part["note"] as? String) ?? (part["comment"] as? String) ?? "")
            } else {
                scores.append(number(value))
                notes.append((value as? String).flatMap { number($0) == nil ? $0 : nil } ?? "")
            }
        }
        var overall = number(object["score"] ?? object["overall"])
        let given = (scores + [overall]).compactMap { $0 }
        let outOfTen = !given.isEmpty && given.allSatisfy { $0 <= 10 }
        func scaled(_ value: Double?) -> Int? {
            value.map { min(100, max(0, Int((outOfTen ? $0 * 10 : $0).rounded()))) }
        }
        if overall == nil, !given.isEmpty { overall = given.reduce(0, +) / Double(given.count) }
        report.score = scaled(overall)
        report.parts = labels.enumerated().map { index, label in
            HookCheckReport.Part(id: label.0, title: label.1, score: scaled(scores[index]),
                                 note: notes[index].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        report.suggestions = ((object["suggestions"] ?? object["fixes"]) as? [Any] ?? [])
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3).map { $0 }
        if report.score == nil, report.suggestions.isEmpty { report.raw = reply.trimmingCharacters(in: .whitespacesAndNewlines) }
        return report
    }
}

extension AppModel {
    func checkHook(_ asset: Asset, tool: VideoTool, state: VideoState) {
        let platform = state.choice("platform", in: tool), goal = state.choice("goal", in: tool)
        let context = state.text("context").trimmingCharacters(in: .whitespacesAndNewlines)
        let url = library.url(for: asset)
        let work = VideoLocalWork(title: tool.name, step: L("Reading key frames…"))
        state.localWork.insert(work, at: 0)
        work.task = Task {
            do {
                let info = try await VideoMedia.probe(url)
                let times = HookCheck.frameTimes(duration: info.duration)
                var images: [InputImage] = []
                var stamps: [String] = []
                for time in times {
                    try Task.checkCancellation()
                    let data = try await VideoMedia.frame(url, at: time, maxPixel: 768)
                    if let image = ImageCoding.prepareForUpload(data, maxPixel: 768, role: "frame") {
                        images.append(image)
                        stamps.append("Frame \(images.count): \(String(format: "%.1f", time)) s")
                    }
                }
                guard !images.isEmpty else { throw VideoMediaError.frame }
                work.step = L("Reviewing the clip…")
                let reply = try await self.helperComplete(
                    title: E("Does My Video Hook?"), tool: .video, system: HookCheck.instructions(platform: platform, goal: goal),
                    user: "The clip is \(String(format: "%.1f", info.duration)) s long.\n" + stamps.joined(separator: "\n")
                        + (context.isEmpty ? "" : "\nAbout the clip, in the creator's words: \(context)"),
                    images: images
                )
                try Task.checkCancellation()
                HookCheckReports.shared.byAsset[asset.id] = HookCheck.report(from: reply, platform: platform, goal: goal)
                work.isDone = true
                state.localWork.removeAll { $0.id == work.id }
            } catch is CancellationError {
                state.localWork.removeAll { $0.id == work.id }
            } catch {
                work.failure = error.localizedDescription
            }
        }
    }
}

struct HookCheckCard: View {
    let report: HookCheckReport

    var body: some View {
        PanelSection(title: L("Estimated score"), systemImage: "gauge.with.needle") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 20) {
                    if let score = report.score { ring(score) }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(report.parts.filter { $0.score != nil || !$0.note.isEmpty }) { part in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(part.title).font(.callout.weight(.semibold))
                                    if let score = part.score {
                                        ProgressView(value: Double(score), total: 100)
                                            .tint(Self.tint(score))
                                            .frame(width: 140)
                                        Text("\(score)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                }
                                if !part.note.isEmpty {
                                    Text(part.note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                if !report.suggestions.isEmpty {
                    Text(L("Suggestions")).font(.body.weight(.semibold))
                    ForEach(Array(report.suggestions.enumerated()), id: \.offset) { index, text in
                        ExampleStep(number: index + 1, text: text)
                    }
                }
                if let raw = report.raw, !raw.isEmpty {
                    Text(raw).font(.callout).textSelection(.enabled)
                }
                Text(L("An estimate from Freefield's AI for %@ (%@), based on eight frames, not a prediction from real viewer data.",
                       L(report.platform), L(report.goal).lowercased()))
                    .fineTextStyle()
            }
            .padding(14)
            .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: Radius.card))
        }
    }

    private func ring(_ score: Int) -> some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(Self.tint(score), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)").font(.system(size: 30, weight: .bold).monospacedDigit())
                Text(L("of 100")).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(width: 104, height: 104)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Estimated score: %ld of 100", score))
    }

    static func tint(_ score: Int) -> Color {
        score >= 70 ? .green : score >= 40 ? .orange : .red
    }
}

struct HookCheckExample: View {
    let tool: VideoTool
    var mediaHeight: CGFloat = 260

    @State private var aspect: Double?

    private static func file(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Examples/video")
    }

    static var clip: URL? { file("hookCheck-before", "mp4") ?? file("videoAd-after", "mp4") }

    static var poster: URL? { file("hookCheck-poster", "heic") ?? (file("hookCheck-before", "mp4") == nil ? file("videoAd-poster", "heic") : nil) }

    static let report: HookCheckReport? = {
        guard let url = file("hookCheck-report", "json"), let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let platform = object["platform"] as? String ?? "TikTok", goal = object["goal"] as? String ?? "Sales"
        let localized = HookCheck.replyLanguage == "Spanish" ? object["es"] ?? object["en"] : object["en"]
        let reply: Any = localized ?? object
        guard let body = try? JSONSerialization.data(withJSONObject: reply),
              let text = String(data: body, encoding: .utf8) else { return nil }
        let report = HookCheck.report(from: text, platform: platform, goal: goal)
        return report.score == nil && report.suggestions.isEmpty ? nil : report
    }()

    static var isAvailable: Bool { clip != nil && report != nil }

    var body: some View {
        if let clip = Self.clip, let report = Self.report {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("Real example"), systemImage: "checkmark.seal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 14) {
                    LoopingVideo(url: clip, posterURL: Self.poster)
                        .aspectRatio(aspect ?? 9.0 / 16, contentMode: .fit)
                        .frame(height: max(170, mediaHeight))
                        .background(Color.primary.opacity(0.05))
                        .clipShape(.rect(cornerRadius: Radius.tile))
                        .overlay(alignment: .bottomLeading) {
                            Text(L("Original")).font(.callout.weight(.semibold))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .glassEffect(in: .capsule).padding(6)
                        }
                    Image(systemName: "arrow.right").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.top, 40)
                    HookCheckCard(report: report)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .task { aspect = await VideoPlayback.aspect(of: clip) }
        }
    }
}
