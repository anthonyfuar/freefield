import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VideoToolbox

struct Options {
    var input: URL
    var output: URL
    var audio = false
    var maxSeconds = 6.0
    var longSide = 960.0
    var kbps: Int?
    var poster: URL?
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("compress-videos: \(message)\n".utf8))
    exit(1)
}

func parseOptions() -> Options {
    let usage = "usage: swift scripts/assets/compress-videos.swift <in.mp4> <out.mp4> [--audio] [--max-seconds 6] [--long-side 960] [--kbps 350] [--poster <out.heic>]"
    var positional: [String] = []
    var flags: [String: String] = [:]
    var audio = false
    var arguments = CommandLine.arguments.dropFirst().makeIterator()
    while let argument = arguments.next() {
        switch argument {
        case "--audio": audio = true
        case "--max-seconds", "--long-side", "--kbps", "--poster":
            guard let value = arguments.next() else { fail("\(argument) needs a value\n\(usage)") }
            flags[argument] = value
        case "-h", "--help":
            print(usage)
            exit(0)
        default:
            if argument.hasPrefix("--") { fail("unknown option \(argument)\n\(usage)") }
            positional.append(argument)
        }
    }
    guard positional.count == 2 else { fail(usage) }
    var options = Options(input: URL(fileURLWithPath: positional[0]), output: URL(fileURLWithPath: positional[1]), audio: audio)
    if let value = flags["--max-seconds"] {
        guard let seconds = Double(value), seconds >= 0 else { fail("--max-seconds must be a number ≥ 0") }
        options.maxSeconds = seconds
    }
    if let value = flags["--long-side"] {
        guard let side = Double(value), side >= 16 else { fail("--long-side must be a number ≥ 16") }
        options.longSide = side
    }
    if let value = flags["--kbps"] {
        guard let kbps = Int(value), kbps > 0 else { fail("--kbps must be a positive integer") }
        options.kbps = kbps
    }
    options.poster = flags["--poster"].map { URL(fileURLWithPath: $0) }
    return options
}

func even(_ value: Double) -> Int { max(2, Int((value / 2).rounded()) * 2) }

final class Lane: @unchecked Sendable {
    let output: AVAssetReaderTrackOutput
    let input: AVAssetWriterInput

    init(_ output: AVAssetReaderTrackOutput, _ input: AVAssetWriterInput) {
        self.output = output
        self.input = input
    }
}

func pump(_ output: AVAssetReaderTrackOutput, into input: AVAssetWriterInput, label: String) async {
    let lane = Lane(output, input)
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        lane.input.requestMediaDataWhenReady(on: DispatchQueue(label: "compress-videos.\(label)")) {
            let output = lane.output, input = lane.input
            while input.isReadyForMoreMediaData {
                guard let sample = output.copyNextSampleBuffer() else {
                    input.markAsFinished()
                    continuation.resume()
                    return
                }
                if !input.append(sample) {
                    input.markAsFinished()
                    continuation.resume()
                    return
                }
            }
        }
    }
}

func compress(_ options: Options) async throws {
    let asset = AVURLAsset(url: options.input)
    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { fail("no video track in \(options.input.path)") }
    let (natural, transform, frameRate) = try await videoTrack.load(.naturalSize, .preferredTransform, .nominalFrameRate)
    let duration = try await asset.load(.duration)
    let fps = frameRate > 0 ? Double(frameRate) : 24

    let scale = min(1, options.longSide / max(natural.width, natural.height))
    let width = even(natural.width * scale), height = even(natural.height * scale)
    let kbps = options.kbps ?? (max(width, height) <= 540 ? 250 : 350)
    let end = options.maxSeconds > 0 ? CMTimeMinimum(duration, CMTime(seconds: options.maxSeconds, preferredTimescale: 600)) : duration

    try? FileManager.default.removeItem(at: options.output)
    try FileManager.default.createDirectory(at: options.output.deletingLastPathComponent(), withIntermediateDirectories: true)
    let reader = try AVAssetReader(asset: asset)
    reader.timeRange = CMTimeRange(start: .zero, end: end)
    let writer = try AVAssetWriter(outputURL: options.output, fileType: .mp4)
    writer.shouldOptimizeForNetworkUse = true

    let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    ])
    videoOutput.alwaysCopiesSampleData = false
    reader.add(videoOutput)
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.hevc,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: kbps * 1000,
            AVVideoExpectedSourceFrameRateKey: Int(fps.rounded()),
            AVVideoMaxKeyFrameIntervalKey: 48,
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String,
        ] as [String: Any],
    ])
    videoInput.expectsMediaDataInRealTime = false
    videoInput.transform = transform
    writer.add(videoInput)

    var audioPair: (AVAssetReaderTrackOutput, AVAssetWriterInput)?
    if options.audio {
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            reader.add(audioOutput)
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 48_000,
            ])
            audioInput.expectsMediaDataInRealTime = false
            writer.add(audioInput)
            audioPair = (audioOutput, audioInput)
        } else {
            print("note: \(options.input.lastPathComponent) has no audio track; writing video only")
        }
    }

    guard reader.startReading() else { fail("can't read \(options.input.path): \(reader.error?.localizedDescription ?? "unknown error")") }
    guard writer.startWriting() else { fail("can't write \(options.output.path): \(writer.error?.localizedDescription ?? "unknown error")") }
    writer.startSession(atSourceTime: .zero)
    async let video: Void = pump(videoOutput, into: videoInput, label: "video")
    if let (audioOutput, audioInput) = audioPair { await pump(audioOutput, into: audioInput, label: "audio") }
    await video
    if reader.status == .failed { fail("reading failed: \(reader.error?.localizedDescription ?? "unknown error")") }
    writer.endSession(atSourceTime: end)
    await writer.finishWriting()
    guard writer.status == .completed else { fail("writing failed: \(writer.error?.localizedDescription ?? "unknown error")") }

    let bytes = (try FileManager.default.attributesOfItem(atPath: options.output.path)[.size] as? Int) ?? 0
    let seconds = end.seconds
    print(String(format: "%@: %d×%d HEVC %.0f fps %.2f s%@ → %.0f KB (%.0f kbps actual, target %d)",
                 options.output.lastPathComponent, width, height, fps, seconds, audioPair == nil ? "" : " +AAC",
                 Double(bytes) / 1024, Double(bytes) * 8 / 1000 / max(seconds, 0.01), kbps))

    if let poster = options.poster {
        try await writePoster(asset, at: min(0.5, seconds / 2), to: poster)
    }
}

func writePoster(_ asset: AVAsset, at seconds: Double, to destination: URL) async throws {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 900, height: 900)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image

    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("poster-\(UUID().uuidString).jpg")
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard let jpeg = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
        fail("can't create \(temporary.path)")
    }
    CGImageDestinationAddImage(jpeg, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
    guard CGImageDestinationFinalize(jpeg) else { fail("can't write the poster JPEG") }

    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    let sips = Process()
    sips.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    sips.arguments = ["-s", "format", "heic", "-s", "formatOptions", "55", temporary.path, "--out", destination.path]
    sips.standardOutput = FileHandle.nullDevice
    try sips.run()
    sips.waitUntilExit()
    guard sips.terminationStatus == 0 else { fail("sips failed for \(destination.path)") }
    let bytes = (try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
    print(String(format: "%@: poster %d×%d at %.2f s → %.0f KB", destination.lastPathComponent, image.width, image.height, seconds, Double(bytes) / 1024))
}

do {
    try await compress(parseOptions())
} catch {
    fail(error.localizedDescription)
}
