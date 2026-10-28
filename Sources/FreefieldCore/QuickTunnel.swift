import CryptoKit
import Darwin
import Foundation
import Synchronization

public struct TunnelSetup: Sendable {
    public var archive: URL?
    public var installFolder: URL
    public var processFile: URL

    public init(archive: URL?, installFolder: URL, processFile: URL? = nil) {
        self.archive = archive
        self.installFolder = installFolder
        self.processFile = processFile ?? installFolder.appendingPathComponent("tunnels.json")
    }

    public static var standard: TunnelSetup {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let archive = Bundle.main.resourceURL?.appendingPathComponent("Helpers/\(Cloudflared.archiveName)")
        return TunnelSetup(archive: archive.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil },
                           installFolder: support.appendingPathComponent("Freefield/bin", isDirectory: true))
    }
}

public enum Cloudflared {
    public static let version = "2026.10.3"
    public static let archiveName = "cloudflared-darwin-arm64.tgz"
    static let archiveSHA256 = "1165d14b6f6360a3b8c283d7d1100024d6ec7cd9bc9e32519e96150645f3ec55"
    static let binarySHA256 = "f249139e0541fa589c987397d867cc16c83ab1236d31eb6782f2e4552ee9cf80"

    public static func install(_ setup: TunnelSetup) async throws -> URL {
        try await Installer.shared.install(setup)
    }

    private actor Installer {
        static let shared = Installer()
        private var verified: (path: String, size: Int64, modified: Date)?

        func install(_ setup: TunnelSetup) async throws -> URL {
            let fileManager = FileManager.default
            let binary = setup.installFolder.appendingPathComponent("cloudflared")
            if isIntact(binary) { return binary }
            guard let archive = setup.archive, fileManager.fileExists(atPath: archive.path) else {
                throw QuickTunnelError.helperMissing
            }
            guard sha256(of: archive) == archiveSHA256 else { throw QuickTunnelError.helperDamaged }
            try? fileManager.createDirectory(at: setup.installFolder, withIntermediateDirectories: true)
            let scratch = setup.installFolder.appendingPathComponent(".extract-\(UUID().uuidString)", isDirectory: true)
            defer { try? fileManager.removeItem(at: scratch) }
            do {
                try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
            } catch {
                throw QuickTunnelError.helperFailed(error.localizedDescription)
            }
            let status = try await run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xzf", archive.path, "-C", scratch.path, "cloudflared"])
            let extracted = scratch.appendingPathComponent("cloudflared")
            guard status == 0, fileManager.fileExists(atPath: extracted.path) else {
                throw QuickTunnelError.helperFailed(L("couldn't unpack it (tar exited with %ld)", Int(status)))
            }
            guard sha256(of: extracted) == binarySHA256 else { throw QuickTunnelError.helperDamaged }
            chmod(extracted.path, 0o755)
            removexattr(extracted.path, "com.apple.quarantine", 0)
            do {
                if fileManager.fileExists(atPath: binary.path) {
                    _ = try fileManager.replaceItemAt(binary, withItemAt: extracted)
                } else {
                    try fileManager.moveItem(at: extracted, to: binary)
                }
            } catch {
                throw QuickTunnelError.helperFailed(error.localizedDescription)
            }
            guard isIntact(binary) else { throw QuickTunnelError.helperDamaged }
            return binary
        }

        private func isIntact(_ binary: URL) -> Bool {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: binary.path),
                  let size = (attributes[.size] as? NSNumber)?.int64Value,
                  let modified = attributes[.modificationDate] as? Date else { return false }
            if let verified, verified.path == binary.path, verified.size == size, verified.modified == modified {
                return FileManager.default.isExecutableFile(atPath: binary.path)
            }
            guard sha256(of: binary) == binarySHA256 else { return false }
            if !FileManager.default.isExecutableFile(atPath: binary.path) { chmod(binary.path, 0o755) }
            verified = (binary.path, size, modified)
            return FileManager.default.isExecutableFile(atPath: binary.path)
        }
    }

    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func runCapturing(_ executable: URL, _ arguments: [String], timeout: TimeInterval = 8) async throws -> (Int32, String) {
        let fileManager = FileManager.default
        let outputURL = fileManager.temporaryDirectory.appendingPathComponent("Freefield-\(UUID().uuidString).out")
        guard fileManager.createFile(atPath: outputURL.path, contents: nil),
              let output = try? FileHandle(forWritingTo: outputURL) else {
            throw QuickTunnelError.helperFailed(L("couldn't write a scratch file"))
        }
        defer {
            try? output.close()
            try? fileManager.removeItem(at: outputURL)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
                return
            }
            let box = ProcessBox(process)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                if box.isRunning { kill(box.processID, SIGKILL) }
            }
        }
        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        return (status, String(decoding: data, as: UTF8.self))
    }

    static func run(_ executable: URL, _ arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: QuickTunnelError.helperFailed(error.localizedDescription))
            }
        }
    }
}

public final class QuickTunnel: Sendable {
    public let publicURL: URL
    public let addresses: [String]
    private let child: TunnelProcess

    public static let connectTimeout: Duration = .seconds(45)
    public static let dnsTimeout: Duration = .seconds(75)

    public static func start(binary: URL, originPort port: UInt16, processFile: URL?) async throws -> QuickTunnel {
        let child = try TunnelProcess.launch(binary: binary, port: port, processFile: processFile)
        do {
            let url = try await child.waitForConnection(timeout: connectTimeout)
            let addresses = try await PublicDNS.waitUntilResolvable(url.host() ?? "", timeout: dnsTimeout) { child.isRunning }
            guard child.isRunning else { throw child.failure(fallback: .stopped("")) }
            return QuickTunnel(publicURL: url, addresses: addresses, child: child)
        } catch {
            child.close()
            if error is CancellationError { throw error }
            throw error as? QuickTunnelError ?? .noConnection(error.localizedDescription)
        }
    }

    private init(publicURL: URL, addresses: [String], child: TunnelProcess) {
        self.publicURL = publicURL
        self.addresses = addresses
        self.child = child
    }

    public var processID: Int32 { child.processID }

    public var isRunning: Bool { child.isRunning }

    public func close() {
        child.close()
    }

    public static func closeAll() {
        TunnelProcess.closeAll()
    }

    public static func stopLeftovers(processFile: URL) {
        TunnelProcess.stopLeftovers(processFile)
    }
}

private final class TunnelProcess: Sendable {
    private let process: ProcessBox
    private let watchdog: ProcessBox?
    private let pipe: Pipe
    private let output: TunnelOutput
    private let home: URL
    private let processFile: URL?
    private let closed = OnceFlag()
    let processID: Int32

    private static let live = Mutex<[ObjectIdentifier: TunnelProcess]>([:])

    private init(process: Process, watchdog: Process?, pipe: Pipe, output: TunnelOutput, home: URL, processFile: URL?) {
        self.process = ProcessBox(process)
        self.watchdog = watchdog.map(ProcessBox.init)
        self.pipe = pipe
        self.output = output
        self.home = home
        self.processFile = processFile
        processID = process.processIdentifier
    }

    static func launch(binary: URL, port: UInt16, processFile: URL?) throws -> TunnelProcess {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory.appendingPathComponent("Freefield-tunnel-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try Data("no-autoupdate: true\n".utf8).write(to: home.appendingPathComponent("config.yml"))
        } catch {
            throw QuickTunnelError.helperFailed(error.localizedDescription)
        }
        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "tunnel", "--no-autoupdate",
            "--config", home.appendingPathComponent("config.yml").path,
            "--url", "http://127.0.0.1:\(port)",
            "--metrics", "127.0.0.1:0",
            "--label", "freefield",
            "--management-diagnostics=false",
            "--grace-period", "1s",
            "--loglevel", "info",
        ]
        process.environment = ["HOME": home.path, "TMPDIR": home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]
        process.currentDirectoryURL = home
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardError = pipe
        let output = TunnelOutput()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                output.append(data)
            }
        }
        process.terminationHandler = { output.exited($0.terminationStatus) }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? fileManager.removeItem(at: home)
            throw QuickTunnelError.helperFailed(error.localizedDescription)
        }
        let child = TunnelProcess(process: process, watchdog: startWatchdog(for: process.processIdentifier),
                                  pipe: pipe, output: output, home: home, processFile: processFile)
        if let processFile { ProcessFile.add(child.processID, path: binary.path, home: home.path, to: processFile) }
        live.withLock { $0[ObjectIdentifier(child)] = child }
        return child
    }

    var isRunning: Bool { !closed.isSet && process.isRunning }

    func waitForConnection(timeout: Duration) async throws -> URL {
        let deadline = ContinuousClock.now + timeout
        while true {
            let snapshot = output.snapshot
            if let url = snapshot.url, snapshot.registered { return url }
            if snapshot.rateLimited { throw QuickTunnelError.rateLimited }
            if snapshot.exitStatus != nil || !process.isRunning {
                throw failure(fallback: .stopped(snapshot.lastError ?? ""))
            }
            if ContinuousClock.now >= deadline {
                throw snapshot.url == nil ? failure(fallback: .timedOut) : QuickTunnelError.timedOut
            }
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    func failure(fallback: QuickTunnelError) -> QuickTunnelError {
        let snapshot = output.snapshot
        if snapshot.rateLimited { return .rateLimited }
        if let request = snapshot.requestError { return .noConnection(request) }
        if case .stopped = fallback, let error = snapshot.lastError { return .stopped(error) }
        return fallback
    }

    func close(force: Bool = false) {
        guard closed.set() else { return }
        pipe.fileHandleForReading.readabilityHandler = nil
        let pid = processID
        if process.isRunning { kill(pid, force ? SIGKILL : SIGTERM) }
        if let watchdog, watchdog.isRunning { kill(watchdog.processID, SIGKILL) }
        if let processFile { ProcessFile.remove(pid, from: processFile) }
        Self.live.withLock { _ = $0.removeValue(forKey: ObjectIdentifier(self)) }
        let process = process
        let home = home
        if force || !process.isRunning {
            try? FileManager.default.removeItem(at: home)
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
            if process.isRunning { kill(pid, SIGKILL) }
            try? FileManager.default.removeItem(at: home)
        }
    }

    static func closeAll() {
        let all = live.withLock { Array($0.values) }
        all.forEach { $0.close(force: true) }
    }

    static func stopLeftovers(_ processFile: URL) {
        let me = ProcessInfo.processInfo.processIdentifier
        ProcessFile.update(processFile) { entries in
            entries.filter { entry in
                if entry.owner == me || (entry.owner > 0 && kill(entry.owner, 0) == 0) { return true }
                let recorded = URL(fileURLWithPath: entry.path).resolvingSymlinksInPath().path
                if let running = executablePath(of: entry.pid),
                   URL(fileURLWithPath: running).resolvingSymlinksInPath().path == recorded {
                    kill(entry.pid, SIGKILL)
                }
                if let home = entry.home, URL(fileURLWithPath: home).lastPathComponent.hasPrefix("Freefield-tunnel-") {
                    try? FileManager.default.removeItem(atPath: home)
                }
                return false
            }
        }
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory
        let names = (try? fileManager.contentsOfDirectory(atPath: temporary.path)) ?? []
        for name in names where name.hasPrefix("Freefield-tunnel-") {
            let folder = temporary.appendingPathComponent(name)
            let modified = (try? fileManager.attributesOfItem(atPath: folder.path))?[.modificationDate] as? Date ?? .distantPast
            if Date().timeIntervalSince(modified) > 30 * 60 { try? fileManager.removeItem(at: folder) }
        }
    }

    private static func startWatchdog(for pid: Int32) -> Process? {
        let watchdog = Process()
        watchdog.executableURL = URL(fileURLWithPath: "/bin/sh")
        watchdog.arguments = [
            "-c",
            #"while kill -0 "$1" 2>/dev/null && kill -0 "$2" 2>/dev/null; do sleep 1; done; kill -0 "$1" 2>/dev/null || kill -9 "$2" 2>/dev/null"#,
            "freefield-watchdog", "\(ProcessInfo.processInfo.processIdentifier)", "\(pid)",
        ]
        watchdog.environment = ["PATH": "/usr/bin:/bin"]
        watchdog.standardInput = FileHandle.nullDevice
        watchdog.standardOutput = FileHandle.nullDevice
        watchdog.standardError = FileHandle.nullDevice
        do {
            try watchdog.run()
            return watchdog
        } catch {
            return nil
        }
    }

    private static func executablePath(of pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    var isRunning: Bool { process.isRunning }
    var processID: Int32 { process.processIdentifier }
}

private final class TunnelOutput: Sendable {
    struct Snapshot {
        var url: URL?
        var registered = false
        var rateLimited = false
        var requestError: String?
        var lastError: String?
        var exitStatus: Int32?
    }

    private struct State {
        var snapshot = Snapshot()
        var partial = Data()
    }

    private let state = Mutex(State())

    var snapshot: Snapshot { state.withLock { $0.snapshot } }

    func append(_ data: Data) {
        state.withLock { state in
            state.partial.append(data)
            while let newline = state.partial.firstIndex(of: 0x0A) {
                let line = String(decoding: state.partial[state.partial.startIndex..<newline], as: UTF8.self)
                state.partial.removeSubrange(state.partial.startIndex...newline)
                Self.read(line, into: &state.snapshot)
            }
            if state.partial.count > 64 * 1024 { state.partial.removeAll() }
        }
    }

    func exited(_ status: Int32) {
        state.withLock { $0.snapshot.exitStatus = status }
    }

    nonisolated(unsafe) private static let address = /https:\/\/([a-z0-9]+(?:-[a-z0-9]+)+)\.trycloudflare\.com/

    private static func read(_ line: String, into snapshot: inout Snapshot) {
        let lower = line.lowercased()
        if snapshot.url == nil, let match = lower.firstMatch(of: address) {
            snapshot.url = URL(string: "https://\(match.1).trycloudflare.com")
        }
        if lower.contains("registered tunnel connection") { snapshot.registered = true }
        if lower.contains("too many requests") || (lower.contains("quick tunnel") && lower.range(of: #"\b429\b"#, options: .regularExpression) != nil) {
            snapshot.rateLimited = true
        }
        let message = message(of: line)
        if lower.contains("failed to request quick tunnel") || lower.contains("quick tunnel provisioning failed")
            || lower.contains("failed to unmarshal quick tunnel") {
            snapshot.requestError = String(message.prefix(200))
        }
        if (lower.contains(" err ") || lower.contains(" ftl ")) && !lower.contains("configuration file") {
            snapshot.lastError = String(message.prefix(200))
        }
    }

    private static func message(of line: String) -> String {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3, ["INF", "ERR", "WRN", "FTL", "DBG"].contains(parts[1]) else {
            return line.trimmingCharacters(in: .whitespaces)
        }
        return String(parts[2]).trimmingCharacters(in: .whitespaces)
    }
}

private enum ProcessFile {
    struct Entry: Codable {
        var pid: Int32
        var path: String
        var owner: Int32
        var home: String?
    }

    private static let lock = Mutex(())

    static func add(_ pid: Int32, path: String, home: String, to file: URL) {
        update(file) { $0 + [Entry(pid: pid, path: path, owner: ProcessInfo.processInfo.processIdentifier, home: home)] }
    }

    static func remove(_ pid: Int32, from file: URL) {
        update(file) { entries in
            entries.filter { !($0.pid == pid && $0.owner == ProcessInfo.processInfo.processIdentifier) }
        }
    }

    @discardableResult
    static func update(_ file: URL, _ change: ([Entry]) -> [Entry]) -> [Entry] {
        lock.withLock { _ in
            let current = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
            let updated = change(current)
            if updated.isEmpty {
                try? FileManager.default.removeItem(at: file)
            } else if let data = try? JSONEncoder().encode(updated) {
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)
            }
            return updated
        }
    }
}

enum PublicDNS {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    static let knownNameServers = ["kevin.ns.cloudflare.com", "marjory.ns.cloudflare.com"]
    static let resolvers = ["https://cloudflare-dns.com/dns-query", "https://dns.google/resolve"]

    static func waitUntilResolvable(_ host: String, timeout: Duration, isAlive: () -> Bool) async throws -> [String] {
        guard !host.isEmpty else { throw QuickTunnelError.notReachable }
        let started = ContinuousClock.now
        func expired() -> Bool { ContinuousClock.now - started >= timeout }

        var authoritative: [String] = []
        let servers = await nameServers(of: zone(of: host))
        var failures = 0
        var attempt = 0
        while authoritative.isEmpty, failures < 3, !expired() {
            guard isAlive() else { throw QuickTunnelError.stopped("") }
            switch await authoritativeLookup(host, server: servers[attempt % servers.count]) {
            case .addresses(let addresses) where !addresses.isEmpty: authoritative = addresses
            case .addresses: failures = 0
            case .unreachable: failures += 1
            }
            attempt += 1
            if authoritative.isEmpty { try await Task.sleep(for: .milliseconds(700)) }
        }
        if expired() { throw QuickTunnelError.notReachable }
        if authoritative.isEmpty { try await Task.sleep(for: .seconds(5)) }

        var unreachable = 0
        attempt = 0
        while true {
            guard isAlive() else { throw QuickTunnelError.stopped("") }
            switch await lookup(host, resolver: resolvers[attempt % resolvers.count]) {
            case .addresses(let addresses) where !addresses.isEmpty:
                return addresses
            case .addresses:
                break
            case .unreachable:
                unreachable += 1
                if unreachable >= resolvers.count * 2 { return authoritative }
            }
            attempt += 1
            if expired() { throw QuickTunnelError.notReachable }
            try await Task.sleep(for: .seconds(2))
        }
    }

    enum Answer {
        case addresses([String])
        case unreachable
    }

    static func zone(of host: String) -> String {
        host.split(separator: ".").suffix(2).joined(separator: ".")
    }

    static func nameServers(of zone: String) async -> [String] {
        guard !zone.isEmpty else { return knownNameServers }
        for resolver in resolvers {
            if let names = await query(zone, type: "NS", resolver: resolver), !names.isEmpty {
                return names.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
            }
        }
        return knownNameServers
    }

    static func authoritativeLookup(_ host: String, server: String) async -> Answer {
        let dig = URL(fileURLWithPath: "/usr/bin/dig")
        guard FileManager.default.isExecutableFile(atPath: dig.path),
              let (status, output) = try? await Cloudflared.runCapturing(
                  dig, ["+short", "+norecurse", "+time=2", "+tries=1", "@\(server)", host, "A"]
              ), status == 0 else {
            return .unreachable
        }
        let addresses = output.split(whereSeparator: \.isNewline).map(String.init).filter { line in
            let parts = line.split(separator: ".")
            return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
        }
        return .addresses(addresses)
    }

    static func lookup(_ host: String, resolver: String) async -> Answer {
        guard let records = await query(host, type: "A", resolver: resolver) else { return .unreachable }
        return .addresses(records)
    }

    static func query(_ name: String, type: String, resolver: String) async -> [String]? {
        guard var components = URLComponents(string: resolver) else { return nil }
        components.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "type", value: type)]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard (object["Status"] as? Int) == 0 else { return [] }
        let code = ["A": 1, "NS": 2][type] ?? -1
        return ((object["Answer"] as? [[String: Any]]) ?? []).compactMap { answer in
            (answer["type"] as? Int) == code ? answer["data"] as? String : nil
        }
    }
}

public final class TunnelSession: Sendable {
    public let id = UUID()
    public let fileURL: URL
    public let publicURL: URL
    public let openedAt: Date
    public let server: LocalFileServer
    public let tunnel: QuickTunnel
    private let closed = OnceFlag()

    public static let defaultLifetime: Duration = .seconds(15 * 60)
    static let rateLimitPause: Duration = .seconds(20)

    public static func open(serving file: URL, mimeType: String? = nil, setup: TunnelSetup = .standard,
                            maxLifetime: Duration = defaultLifetime) async throws -> TunnelSession {
        let binary = try await Cloudflared.install(setup)
        try Task.checkCancellation()
        let server = try await LocalFileServer.start(serving: file, mimeType: mimeType)
        do {
            let tunnel: QuickTunnel
            do {
                tunnel = try await QuickTunnel.start(binary: binary, originPort: server.port, processFile: setup.processFile)
            } catch QuickTunnelError.rateLimited {
                try await Task.sleep(for: rateLimitPause)
                tunnel = try await QuickTunnel.start(binary: binary, originPort: server.port, processFile: setup.processFile)
            }
            let session = TunnelSession(file: file, server: server, tunnel: tunnel)
            if Task.isCancelled {
                session.close()
                throw CancellationError()
            }
            Task.detached { [weak session] in
                try? await Task.sleep(for: maxLifetime)
                session?.close()
            }
            return session
        } catch {
            server.stop()
            throw error
        }
    }

    private init(file: URL, server: LocalFileServer, tunnel: QuickTunnel) {
        fileURL = file
        self.server = server
        self.tunnel = tunnel
        openedAt = .now
        publicURL = tunnel.publicURL.appendingPathComponent(String(server.path.dropFirst()))
    }

    deinit {
        close()
    }

    public var isOpen: Bool { !closed.isSet && tunnel.isRunning && server.isRunning }

    public var completedDownloads: Int { server.completedDownloads }

    public var requestCount: Int { server.requestCount }

    public func close() {
        guard closed.set() else { return }
        tunnel.close()
        server.stop()
    }
}

public enum QuickTunnelError: LocalizedError, Sendable, Equatable {
    case helperMissing
    case helperDamaged
    case helperFailed(String)
    case rateLimited
    case noConnection(String)
    case timedOut
    case notReachable
    case stopped(String)

    public var errorDescription: String? {
        switch self {
        case .helperMissing:
            L("This copy of Freefield doesn't include its sharing helper (cloudflared). Reinstall Freefield.")
        case .helperDamaged:
            L("Freefield's sharing helper (cloudflared) doesn't match Cloudflare's release, so it wasn't used. Reinstall Freefield.")
        case .helperFailed(let detail):
            L("Freefield's sharing helper (cloudflared) couldn't start (%@).", detail)
        case .rateLimited:
            L("Cloudflare isn't giving out temporary links right now (too many requests). Try again in a few minutes.")
        case .noConnection(let detail):
            detail.isEmpty
                ? L("Couldn't reach Cloudflare to open a temporary link. Check your internet connection.")
                : L("Couldn't reach Cloudflare to open a temporary link (%@). Check your internet connection.", detail)
        case .timedOut:
            L("Cloudflare took too long to open a temporary link. Check your internet connection and try again.")
        case .notReachable:
            L("The temporary link didn't come online in time. Try again in a moment.")
        case .stopped(let detail):
            detail.isEmpty
                ? L("Freefield's sharing helper (cloudflared) stopped unexpectedly.")
                : L("Freefield's sharing helper (cloudflared) stopped unexpectedly (%@).", detail)
        }
    }
}

public enum InputLink {
    public static func checked(_ string: String) throws -> String {
        try OpenRouterClient.httpsURL(string)
    }
}
