import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct VideoInfo: Sendable, Equatable {
    var size: CGSize
    var duration: Double
    var fps: Double
    var hasAudio: Bool

    var aspect: Double { size.height > 0 ? size.width / size.height : 1 }
}

nonisolated enum VideoMediaError: LocalizedError, Sendable, Equatable {
    case unreadable
    case noVideo
    case noAudio
    case noClips
    case tooShort
    case frame
    case export(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: L("Couldn't read the video file.")
        case .noVideo: L("The file has no video track.")
        case .noAudio: L("The source clip has no sound.")
        case .noClips: L("Add at least one clip.")
        case .tooShort: L("The selection is too short.")
        case .frame: L("Couldn't read a frame from the video.")
        case .export(let detail): L("Couldn't export the video (%@).", detail)
        }
    }
}

nonisolated enum VideoMedia {
    static var workFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Freefield-Video", isDirectory: true)
    }

    @concurrent
    static func scratchCopy(of source: URL, prefix: String) async throws -> URL {
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        let copy = workFolder.appendingPathComponent("\(prefix)-\(UUID().uuidString.prefix(8))_\(source.lastPathComponent)")
        try FileManager.default.copyItem(at: source, to: copy)
        return copy
    }

    @concurrent
    static func probe(_ url: URL) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url)
        let track = try await videoTrack(of: asset)
        let (natural, transform, rate, minFrame) = try await load {
            try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate, .minFrameDuration)
        }
        let duration = try await load { try await asset.load(.duration) }.seconds
        let audio = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        return VideoInfo(size: displaySize(natural, transform), duration: duration, fps: fps(rate, minFrame), hasAudio: !audio.isEmpty)
    }

    @concurrent
    static func poster(_ url: URL, at seconds: Double = 0.5, maxPixel: Int = 1024) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let range = try await videoRange(of: asset)
        let offset = min(max(0, seconds), range.duration.seconds / 2)
        return try await jpeg(url, at: time(range.start.seconds + offset), maxPixel: maxPixel)
    }

    @concurrent
    static func frame(_ url: URL, at seconds: Double, maxPixel: Int? = nil) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let track = try await videoTrack(of: asset)
        let (range, timescale) = try await load { try await track.load(.timeRange, .naturalTimeScale) }
        return try await jpeg(url, at: clamped(time(seconds, timescale: timescale), to: range), maxPixel: maxPixel)
    }

    @concurrent
    static func frame(_ url: URL, at time: CMTime, maxPixel: Int? = nil) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let range = try await videoRange(of: asset)
        return try await jpeg(url, at: clamped(time, to: range), maxPixel: maxPixel)
    }

    @concurrent
    static func lastFrame(_ url: URL, maxPixel: Int? = nil) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let track = try await videoTrack(of: asset)
        let (range, rate, minFrame) = try await load { try await track.load(.timeRange, .nominalFrameRate, .minFrameDuration) }
        let frameLength = 1 / fps(rate, minFrame)
        let seconds = max(range.start.seconds, range.end.seconds - frameLength * 0.5)
        return try await jpeg(url, at: time(seconds), maxPixel: maxPixel)
    }

    @concurrent
    static func join(_ urls: [URL], trimSeams: Bool, keepsEnds: Bool = false, crossfade: Double = 0) async throws -> URL {
        guard !urls.isEmpty else { throw VideoMediaError.noClips }
        let clips = try await loadClips(urls, trimSeams: trimSeams, keepsEnds: keepsEnds)
        defer { withExtendedLifetime(clips) {} }
        let shortest = clips.map(\.range.duration.seconds).min() ?? 0
        let fadeSeconds = clips.count > 1 ? min(max(0, crossfade), shortest / 3) : 0
        let fade = fadeSeconds >= 0.04 ? CMTime(seconds: fadeSeconds, preferredTimescale: 6000) : .zero
        let lanes = fade > .zero ? 2 : 1

        let composition = AVMutableComposition()
        let videoLanes = (0..<lanes).compactMap { _ in
            composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        let audioLanes = clips.contains { $0.audio != nil }
            ? (0..<lanes).compactMap { _ in composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) }
            : []
        guard videoLanes.count == lanes else { throw VideoMediaError.export(L("no video track")) }

        var placed: [CMTimeRange] = []
        var cursor = CMTime.zero
        for (index, clip) in clips.enumerated() {
            let lane = index % lanes
            do {
                try videoLanes[lane].insertTimeRange(clip.range, of: clip.video, at: cursor)
                if let audio = clip.audio, lane < audioLanes.count {
                    let overlap = clip.range.intersection(clip.audioRange)
                    if overlap.duration > .zero {
                        try audioLanes[lane].insertTimeRange(overlap, of: audio, at: cursor + (overlap.start - clip.range.start))
                    }
                }
            } catch {
                throw VideoMediaError.export(error.localizedDescription)
            }
            placed.append(CMTimeRange(start: cursor, duration: clip.range.duration))
            cursor = cursor + clip.range.duration - fade
        }
        for track in audioLanes where track.segments.isEmpty { composition.removeTrack(track) }
        let total = placed.last?.end ?? .zero

        let renderSize = evenSize(clips[0].size)
        var instructions: [AVVideoCompositionInstruction] = []
        func layer(_ index: Int, at time: CMTime) -> AVVideoCompositionLayerInstruction.Configuration {
            var configuration = AVVideoCompositionLayerInstruction.Configuration(trackID: videoLanes[index % lanes].trackID)
            configuration.setTransform(fillTransform(clips[index], in: renderSize), at: time)
            return configuration
        }
        for index in clips.indices {
            let range = placed[index]
            let solidStart = index == 0 ? range.start : range.start + fade
            let solidEnd = index == clips.count - 1 ? range.end : range.end - fade
            if solidEnd > solidStart {
                instructions.append(instruction([layer(index, at: solidStart)], CMTimeRange(start: solidStart, end: solidEnd)))
            }
            if fade > .zero, index < clips.count - 1 {
                let transition = CMTimeRange(start: range.end - fade, end: range.end)
                var outgoing = layer(index, at: transition.start)
                outgoing.addOpacityRamp(.init(timeRange: transition, start: 1, end: 0))
                instructions.append(instruction([outgoing, layer(index + 1, at: transition.start)], transition))
            }
        }
        let videoComposition = AVVideoComposition(configuration: .init(
            frameDuration: frameDuration(clips[0].fps), instructions: instructions, renderSize: renderSize
        ))

        var audioMix: AVAudioMix?
        if fade > .zero, !composition.tracks(withMediaType: .audio).isEmpty {
            let mix = AVMutableAudioMix()
            mix.inputParameters = audioLanes.enumerated().filter { !$0.element.segments.isEmpty }.map { lane, track in
                let parameters = AVMutableAudioMixInputParameters(track: track)
                for index in clips.indices where index % lanes == lane {
                    let range = placed[index]
                    if index > 0 {
                        parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: CMTimeRange(start: range.start, duration: fade))
                    }
                    if index < clips.count - 1 {
                        parameters.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: range.end - fade, duration: fade))
                    }
                }
                return parameters
            }
            audioMix = mix
        }
        return try await export(composition, videoComposition: videoComposition, audioMix: audioMix,
                                timeRange: CMTimeRange(start: .zero, duration: total))
    }

    @concurrent
    static func trim(_ url: URL, start: Double, end: Double) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let duration = try await load { try await asset.load(.duration) }
        let lower = max(0, start), upper = min(duration.seconds, end)
        guard upper - lower >= 0.1 else { throw VideoMediaError.tooShort }
        let track = try await videoTrack(of: asset)
        let timescale = try await load { try await track.load(.naturalTimeScale) }
        let range = CMTimeRange(start: time(lower, timescale: timescale), end: CMTimeMinimum(time(upper, timescale: timescale), duration))
        return try await export(asset, timeRange: range)
    }

    @concurrent
    static func smartCrop(_ url: URL, toAspect aspect: Double) async throws -> URL {
        guard aspect > 0 else { throw VideoMediaError.export(L("invalid aspect ratio")) }
        let asset = AVURLAsset(url: url)
        let track = try await videoTrack(of: asset)
        let (range, natural, transform, rate, minFrame) = try await load {
            try await track.load(.timeRange, .naturalSize, .preferredTransform, .nominalFrameRate, .minFrameDuration)
        }
        let duration = try await load { try await asset.load(.duration) }
        let display = displaySize(natural, transform)
        var crop = display
        if display.width / display.height > aspect {
            crop.width = display.height * aspect
        } else {
            crop.height = display.width / aspect
        }
        crop = evenSize(crop)
        let slackX = max(0, display.width - crop.width), slackY = max(0, display.height - crop.height)
        let upright = uprightTransform(natural, transform)

        var layer = AVVideoCompositionLayerInstruction.Configuration(trackID: track.trackID)
        if slackX < 2, slackY < 2 {
            layer.setTransform(upright, at: .zero)
        } else {
            let step = 0.25
            let times = Array(stride(from: range.start.seconds, through: range.end.seconds, by: step))
            let centers = smoothPath(await subjectCenters(asset, times: times), panX: slackX >= slackY)
            func cropTransform(_ center: Double) -> CGAffineTransform {
                let x = slackX >= 2 ? min(slackX, max(0, center * display.width - crop.width / 2)) : slackX / 2
                let y = slackY >= 2 ? min(slackY, max(0, center * display.height - crop.height / 2)) : slackY / 2
                return upright.concatenating(CGAffineTransform(translationX: -x.rounded(), y: -y.rounded()))
            }
            let transforms = centers.map(cropTransform)
            layer.setTransform(transforms[0], at: .zero)
            for index in transforms.indices.dropLast() {
                let span = CMTimeRange(start: time(times[index]), end: time(times[index + 1]))
                layer.addTransformRamp(.init(timeRange: span, start: transforms[index], end: transforms[index + 1]))
            }
            if let last = times.last, let final = transforms.last { layer.setTransform(final, at: time(last)) }
        }
        let videoComposition = AVVideoComposition(configuration: .init(
            frameDuration: frameDuration(fps(rate, minFrame)),
            instructions: [instruction([layer], CMTimeRange(start: .zero, duration: duration))],
            renderSize: crop
        ))
        return try await export(asset, videoComposition: videoComposition, timeRange: CMTimeRange(start: .zero, duration: duration))
    }

    @concurrent
    static func muxAudio(from source: URL, into video: URL) async throws -> URL {
        let videoAsset = AVURLAsset(url: video), sourceAsset = AVURLAsset(url: source)
        defer { withExtendedLifetime((videoAsset, sourceAsset)) {} }
        let track = try await videoTrack(of: videoAsset)
        let (videoRange, transform) = try await load { try await track.load(.timeRange, .preferredTransform) }
        guard let audio = try? await sourceAsset.loadTracks(withMediaType: .audio).first else { throw VideoMediaError.noAudio }
        let audioRange = try await load { try await audio.load(.timeRange) }

        let composition = AVMutableComposition()
        guard let videoLane = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioLane = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoMediaError.export(L("no video track"))
        }
        do {
            try videoLane.insertTimeRange(videoRange, of: track, at: .zero)
            videoLane.preferredTransform = transform
            let length = CMTimeMinimum(videoRange.duration, audioRange.duration)
            try audioLane.insertTimeRange(CMTimeRange(start: audioRange.start, duration: length), of: audio, at: .zero)
        } catch {
            throw VideoMediaError.export(error.localizedDescription)
        }
        let canCopy = await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetPassthrough, with: composition, outputFileType: .mp4)
        return try await export(composition, preset: canCopy ? AVAssetExportPresetPassthrough : AVAssetExportPresetHEVCHighestQuality)
    }

    @concurrent
    static func grade(_ url: URL, ciFilterChain: @escaping @Sendable (CIImage) -> CIImage) async throws -> URL {
        try await grade(url, timedFilter: { image, _ in ciFilterChain(image) })
    }

    @concurrent
    static func grade(_ url: URL, timedFilter: @escaping @Sendable (CIImage, Double) -> CIImage) async throws -> URL {
        let asset = AVURLAsset(url: url)
        _ = try await videoTrack(of: asset)
        let videoComposition: AVVideoComposition
        do {
            videoComposition = try await AVVideoComposition(applyingFiltersTo: asset) { parameters in
                let source = parameters.sourceImage
                let seconds = parameters.compositionTime.seconds
                return AVCIImageFilteringResult(resultImage: timedFilter(source, seconds.isFinite ? seconds : 0).cropped(to: source.extent))
            }
        } catch {
            throw VideoMediaError.export(error.localizedDescription)
        }
        return try await export(asset, videoComposition: videoComposition)
    }

    private static func export(
        _ asset: AVAsset, preset: String = AVAssetExportPresetHEVCHighestQuality,
        videoComposition: AVVideoComposition? = nil, audioMix: AVAudioMix? = nil, timeRange: CMTimeRange? = nil
    ) async throws -> URL {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw VideoMediaError.export(L("this Mac can't encode HEVC"))
        }
        session.videoComposition = videoComposition
        session.audioMix = audioMix
        if let timeRange { session.timeRange = timeRange }
        session.shouldOptimizeForNetworkUse = true
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        let output = workFolder.appendingPathComponent("\(UUID().uuidString).mp4")
        do {
            try await session.export(to: output, as: .mp4)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: output)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw VideoMediaError.export(error.localizedDescription)
        }
        return output
    }

    private struct Clip {
        let asset: AVURLAsset
        let video: AVAssetTrack
        let audio: AVAssetTrack?
        let audioRange: CMTimeRange
        let range: CMTimeRange
        let natural: CGSize
        let transform: CGAffineTransform
        let fps: Double

        var size: CGSize { VideoMedia.displaySize(natural, transform) }
    }

    private static func loadClips(_ urls: [URL], trimSeams: Bool, keepsEnds: Bool) async throws -> [Clip] {
        var clips: [Clip] = []
        for (index, url) in urls.enumerated() {
            let asset = AVURLAsset(url: url)
            let video = try await videoTrack(of: asset)
            let (range, natural, transform, rate, minFrame) = try await load {
                try await video.load(.timeRange, .naturalSize, .preferredTransform, .nominalFrameRate, .minFrameDuration)
            }
            let audio = try? await asset.loadTracks(withMediaType: .audio).first
            var audioRange = CMTimeRange.zero
            if let audio { audioRange = try await load { try await audio.load(.timeRange) } }
            let rateValue = fps(rate, minFrame)
            var start = range.start, end = range.end
            if trimSeams {
                let frame = frameDuration(rateValue)
                let trimmedStart = index > 0 ? start + frame : start
                let trimmedEnd = index < urls.count - 1 && !keepsEnds ? end - CMTimeMultiply(frame, multiplier: 6) : end
                if (trimmedEnd - trimmedStart).seconds >= 0.5 {
                    start = trimmedStart
                    end = trimmedEnd
                }
            }
            guard end > start else { throw VideoMediaError.tooShort }
            clips.append(Clip(asset: asset, video: video, audio: audio, audioRange: audioRange, range: CMTimeRange(start: start, end: end),
                              natural: natural, transform: transform, fps: rateValue))
        }
        return clips
    }

    private static func videoTrack(of asset: AVAsset) async throws -> AVAssetTrack {
        let tracks = try await load { try await asset.loadTracks(withMediaType: .video) }
        guard let track = tracks.first else { throw VideoMediaError.noVideo }
        return track
    }

    private static func videoRange(of asset: AVAsset) async throws -> CMTimeRange {
        let track = try await videoTrack(of: asset)
        return try await load { try await track.load(.timeRange) }
    }

    private static func load<Value>(_ body: () async throws -> Value) async throws -> Value {
        do {
            return try await body()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VideoMediaError.unreadable
        }
    }

    private static func jpeg(_ url: URL, at time: CMTime, maxPixel: Int?) async throws -> Data {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        if let maxPixel { generator.maximumSize = CGSize(width: maxPixel, height: maxPixel) }
        let image: CGImage
        do {
            image = try await generator.image(at: time).image
        } catch {
            throw VideoMediaError.frame
        }
        guard let data = encodeJPEG(image) else { throw VideoMediaError.frame }
        return data
    }

    private static func encodeJPEG(_ image: CGImage, quality: Double = 0.9) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func instruction(
        _ layers: [AVVideoCompositionLayerInstruction.Configuration], _ range: CMTimeRange
    ) -> AVVideoCompositionInstruction {
        AVVideoCompositionInstruction(configuration: .init(
            backgroundColor: CGColor(gray: 0, alpha: 1),
            layerInstructions: layers.map(AVVideoCompositionLayerInstruction.init(configuration:)),
            timeRange: range
        ))
    }

    private static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 6000) }

    private static func time(_ seconds: Double, timescale: CMTimeScale) -> CMTime {
        let scale = timescale > 0 ? timescale : 6000
        return CMTime(value: CMTimeValue((seconds * Double(scale)).rounded()), timescale: scale)
    }

    private static func clamped(_ time: CMTime, to range: CMTimeRange) -> CMTime {
        let latest = CMTimeMaximum(range.start, range.end - CMTime(value: 1, timescale: max(range.end.timescale, 1000)))
        return CMTimeMaximum(range.start, CMTimeMinimum(time, latest))
    }

    private static func fps(_ nominal: Float, _ minFrame: CMTime) -> Double {
        if nominal > 0 { return Double(nominal) }
        if minFrame.isValid, minFrame.seconds > 0 { return 1 / minFrame.seconds }
        return 24
    }

    private static func frameDuration(_ fps: Double) -> CMTime {
        CMTime(value: 1000, timescale: CMTimeScale(max(1, (fps * 1000).rounded())))
    }

    nonisolated static func displaySize(_ natural: CGSize, _ transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: natural).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    private static func uprightTransform(_ natural: CGSize, _ transform: CGAffineTransform) -> CGAffineTransform {
        let rect = CGRect(origin: .zero, size: natural).applying(transform)
        return transform.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    }

    private static func fillTransform(_ clip: Clip, in frame: CGSize) -> CGAffineTransform {
        let size = clip.size
        guard size.width > 0, size.height > 0 else { return .identity }
        let scale = max(frame.width / size.width, frame.height / size.height)
        let x = (frame.width - size.width * scale) / 2, y = (frame.height - size.height * scale) / 2
        return uprightTransform(clip.natural, clip.transform)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: x, y: y))
    }

    private static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(2, (size.width / 2).rounded(.down) * 2), height: max(2, (size.height / 2).rounded(.down) * 2))
    }

    private static func subjectCenters(_ asset: AVAsset, times: [Double]) async -> [CGPoint?] {
        let none = [CGPoint?](repeating: nil, count: times.count)
        guard let first = times.first, let last = times.last, let app = await AIChecks.app else { return none }
        let count = min(AIChecks.maxSubjectFrames, max(2, Int((last - first) / 0.5) + 1))
        let sampleTimes = (0..<count).map { first + (last - first) * Double($0) / Double(count - 1) }
        let frames = await subjectFrames(asset, times: sampleTimes)
        guard let centers = await app.subjectCenters(inFrames: frames.map(\.jpeg), times: frames.map(\.time)) else { return none }
        let known = zip(frames, centers).compactMap { frame, center in center.map { (time: frame.time, center: $0) } }
        return interpolated(known, at: times)
    }

    private static func subjectFrames(_ asset: AVAsset, times: [Double]) async -> [(time: Double, jpeg: Data)] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 384, height: 384)
        let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        var frames: [(time: Double, jpeg: Data)] = []
        for await result in generator.images(for: times.map(time)) {
            guard case .success(let requested, let image, _) = result, let jpeg = encodeJPEG(image, quality: 0.7) else { continue }
            frames.append((requested.seconds, jpeg))
        }
        return frames
    }

    private static func interpolated(_ known: [(time: Double, center: CGPoint)], at times: [Double]) -> [CGPoint?] {
        guard let firstKnown = known.first, let lastKnown = known.last else { return times.map { _ in nil } }
        return times.map { time in
            guard let upper = known.firstIndex(where: { $0.time >= time }) else { return lastKnown.center }
            guard upper > 0 else { return firstKnown.center }
            let a = known[upper - 1], b = known[upper]
            let t = b.time > a.time ? (time - a.time) / (b.time - a.time) : 0
            return CGPoint(x: a.center.x + (b.center.x - a.center.x) * t, y: a.center.y + (b.center.y - a.center.y) * t)
        }
    }

    private static func smoothPath(_ centers: [CGPoint?], panX: Bool) -> [Double] {
        var values = centers.map { $0.map { Double(panX ? $0.x : $0.y) } }
        if values.allSatisfy({ $0 == nil }) { return Array(repeating: 0.5, count: max(1, values.count)) }
        var last = values.first { $0 != nil } ?? 0.5
        for index in values.indices {
            if let value = values[index] { last = value } else { values[index] = last }
        }
        var path = values.map { $0 ?? 0.5 }
        let radius = 4
        for _ in 0..<2 {
            path = path.indices.map { index in
                let window = path[max(0, index - radius)...min(path.count - 1, index + radius)]
                return window.reduce(0, +) / Double(window.count)
            }
        }
        return path.map { min(1, max(0, $0)) }
    }
}
