import Foundation
import Network
import Synchronization
import UniformTypeIdentifiers

public final class LocalFileServer: Sendable {
    public let fileURL: URL
    public let path: String
    public let mimeType: String
    public let size: Int64

    private let queue = DispatchQueue(label: "app.freefield.LocalFileServer")
    private let state = Mutex(State())

    private struct State {
        var listener: NWListener?
        var port: UInt16 = 0
        var connections: [ObjectIdentifier: NWConnection] = [:]
        var stopped = false
        var requests = 0
        var coverage: [Range<Int64>] = []
        var completedDownloads = 0
        var lastRequest: Date?
    }

    static let portRange: ClosedRange<UInt16> = 49152...65535
    static let randomAttempts = 20
    static let maxConnections = 16
    static let chunkSize = 256 * 1024
    static let requestTimeout: TimeInterval = 20
    static let bindTimeout: TimeInterval = 3

    public static func start(serving file: URL, mimeType: String? = nil) async throws -> LocalFileServer {
        try await start(serving: file, mimeType: mimeType, ports: nil)
    }

    static func start(serving file: URL, mimeType: String?, ports: [UInt16]?) async throws -> LocalFileServer {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        guard let size = (attributes?[.size] as? NSNumber)?.int64Value, size > 0,
              FileManager.default.isReadableFile(atPath: file.path) else {
            throw LocalFileServerError.unreadable
        }
        let server = LocalFileServer(file: file, size: size, mimeType: mimeType ?? Self.mimeType(for: file))
        let ports = ports ?? ((0..<randomAttempts).map { _ in UInt16.random(in: portRange) } + [0])
        var lastError: (any Error)?
        for port in ports {
            try Task.checkCancellation()
            do {
                try await server.listen(on: port)
                return server
            } catch {
                lastError = error
            }
        }
        throw LocalFileServerError.noPort(lastError.map { String(describing: $0) } ?? "")
    }

    private init(file: URL, size: Int64, mimeType: String) {
        fileURL = file
        self.size = size
        self.mimeType = mimeType
        let ext = file.pathExtension.lowercased()
        path = "/" + UUID().uuidString.lowercased() + (ext.isEmpty ? "" : ".\(ext)")
    }

    deinit {
        stop()
    }

    public var port: UInt16 { state.withLock { $0.port } }

    public var origin: URL { URL(string: "http://127.0.0.1:\(port)")! }

    public var localURL: URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }

    public var completedDownloads: Int { state.withLock { $0.completedDownloads } }

    public var requestCount: Int { state.withLock { $0.requests } }

    public var lastRequest: Date? { state.withLock { $0.lastRequest } }

    public var isRunning: Bool { state.withLock { !$0.stopped && $0.listener != nil } }

    public func stop() {
        let (listener, connections) = state.withLock { state in
            state.stopped = true
            defer {
                state.listener = nil
                state.connections = [:]
            }
            return (state.listener, Array(state.connections.values))
        }
        listener?.cancel()
        connections.forEach { $0.cancel() }
    }

    public static func mimeType(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "mp4", "m4v": "video/mp4"
        case "mov": "video/quicktime"
        case "webm": "video/webm"
        case "m4a", "aac": "audio/mp4"
        case "mp3": "audio/mpeg"
        case "wav": "audio/wav"
        case let ext: UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        }
    }

    private func listen(on port: UInt16) async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = false
        parameters.acceptLocalOnly = true
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port) ?? .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            self.accept(connection)
        }
        let resumed = OnceFlag()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                listener.stateUpdateHandler = { [weak self] newState in
                    func finish(_ result: Result<Void, any Error>) {
                        guard resumed.set() else { return }
                        continuation.resume(with: result)
                    }
                    switch newState {
                    case .ready:
                        let bound = listener.port?.rawValue ?? 0
                        guard let self, bound != 0 else {
                            listener.cancel()
                            finish(.failure(LocalFileServerError.noPort("")))
                            return
                        }
                        self.state.withLock { state in
                            state.listener = listener
                            state.port = bound
                        }
                        finish(.success(()))
                    case .failed(let error), .waiting(let error):
                        listener.cancel()
                        finish(.failure(error))
                    case .cancelled:
                        finish(.failure(CancellationError()))
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
                queue.asyncAfter(deadline: .now() + Self.bindTimeout) {
                    if !resumed.isSet { listener.cancel() }
                }
            }
        } onCancel: {
            listener.cancel()
        }
        if state.withLock({ $0.stopped }) {
            listener.cancel()
            throw CancellationError()
        }
    }

    private func accept(_ connection: NWConnection) {
        let accepted = state.withLock { state -> Bool in
            guard !state.stopped, state.connections.count < Self.maxConnections else { return false }
            state.connections[ObjectIdentifier(connection)] = connection
            return true
        }
        guard accepted else {
            connection.cancel()
            return
        }
        let id = ObjectIdentifier(connection)
        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .failed, .cancelled:
                _ = self?.state.withLock { $0.connections.removeValue(forKey: id) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        let answered = OnceFlag()
        queue.asyncAfter(deadline: .now() + Self.requestTimeout) {
            if answered.set() { connection.cancel() }
        }
        receiveRequest(on: connection, buffer: Data()) { _ = answered.set() }
    }

    private static let headEnd = Data("\r\n\r\n".utf8)
    private static let maxHeadBytes = 16 * 1024

    private func receiveRequest(on connection: NWConnection, buffer: Data, received: @escaping @Sendable () -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxHeadBytes) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Self.headEnd) {
                received()
                self.answer(String(decoding: buffer[..<end.lowerBound], as: UTF8.self), on: connection)
            } else if buffer.count > Self.maxHeadBytes {
                received()
                self.send(status: "431 Request Header Fields Too Large", on: connection)
            } else if error != nil || isComplete {
                connection.cancel()
            } else {
                self.receiveRequest(on: connection, buffer: buffer, received: received)
            }
        }
    }

    private func answer(_ head: String, on connection: NWConnection) {
        state.withLock { state in
            state.requests += 1
            state.lastRequest = .now
        }
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            send(status: "400 Bad Request", on: connection)
            return
        }
        let method = String(parts[0])
        var target = String(parts[1])
        if let query = target.firstIndex(where: { $0 == "?" || $0 == "#" }) { target = String(target[..<query]) }
        if target.hasPrefix("http://") || target.hasPrefix("https://"), let url = URL(string: target) {
            target = url.path
        }
        guard target == path else {
            send(status: "404 Not Found", on: connection)
            return
        }
        guard method == "GET" || method == "HEAD" else {
            send(status: "405 Method Not Allowed", extraHeaders: ["Allow: GET, HEAD"], on: connection)
            return
        }
        var rangeHeader: String?
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            if line[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == "range" {
                rangeHeader = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        let current = Self.fileSize(fileURL)
        guard current > 0 else {
            send(status: "404 Not Found", on: connection)
            return
        }
        switch Self.byteRange(rangeHeader, size: current) {
        case .whole:
            sendFile(range: 0..<current, size: current, partial: false, includeBody: method == "GET", on: connection)
        case .part(let range):
            sendFile(range: range, size: current, partial: true, includeBody: method == "GET", on: connection)
        case .unsatisfiable:
            send(status: "416 Range Not Satisfiable", extraHeaders: ["Content-Range: bytes */\(current)"], on: connection)
        }
    }

    enum ByteRange: Equatable {
        case whole
        case part(Range<Int64>)
        case unsatisfiable
    }

    static func byteRange(_ header: String?, size: Int64) -> ByteRange {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else { return .whole }
        guard header.lowercased().hasPrefix("bytes=") else { return .whole }
        let spec = header.dropFirst(6).trimmingCharacters(in: .whitespaces)
        guard !spec.contains(","), let dash = spec.firstIndex(of: "-") else { return .whole }
        let first = spec[..<dash].trimmingCharacters(in: .whitespaces)
        let last = spec[spec.index(after: dash)...].trimmingCharacters(in: .whitespaces)
        if first.isEmpty {
            guard let suffix = Int64(last), suffix >= 0 else { return .whole }
            guard suffix > 0 else { return .unsatisfiable }
            return .part(max(0, size - suffix)..<size)
        }
        guard let start = Int64(first), start >= 0 else { return .whole }
        guard start < size else { return .unsatisfiable }
        if last.isEmpty { return .part(start..<size) }
        guard let end = Int64(last), end >= start else { return .whole }
        return .part(start..<(min(end, size - 1) + 1))
    }

    private func send(status: String, extraHeaders: [String] = [], on connection: NWConnection) {
        var head = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nCache-Control: no-store\r\nConnection: close\r\n"
        extraHeaders.forEach { head += $0 + "\r\n" }
        head += "\r\n"
        connection.send(content: Data(head.utf8), isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func sendFile(range: Range<Int64>, size: Int64, partial: Bool, includeBody: Bool, on connection: NWConnection) {
        var head = partial ? "HTTP/1.1 206 Partial Content\r\n" : "HTTP/1.1 200 OK\r\n"
        head += "Content-Type: \(mimeType)\r\n"
        head += "Content-Length: \(range.count)\r\n"
        if partial { head += "Content-Range: bytes \(range.lowerBound)-\(range.upperBound - 1)/\(size)\r\n" }
        head += "Accept-Ranges: bytes\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        guard includeBody, !range.isEmpty, let handle = try? FileHandle(forReadingFrom: fileURL) else {
            connection.send(content: Data(head.utf8), isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        let file = SendableFileHandle(handle)
        connection.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil, let self else {
                file.close()
                connection.cancel()
                return
            }
            self.sendBody(file, from: range.lowerBound, range: range, size: size, on: connection)
        })
    }

    private func sendBody(_ file: SendableFileHandle, from offset: Int64, range: Range<Int64>, size: Int64, on connection: NWConnection) {
        let count = Int(min(Int64(Self.chunkSize), range.upperBound - offset))
        guard count > 0, let chunk = file.read(at: offset, count: count), !chunk.isEmpty else {
            file.close()
            connection.cancel()
            return
        }
        let next = offset + Int64(chunk.count)
        let isLast = next >= range.upperBound
        connection.send(content: chunk, isComplete: isLast, completion: .contentProcessed { [weak self] error in
            guard error == nil, let self else {
                file.close()
                connection.cancel()
                return
            }
            if isLast {
                file.close()
                self.recordSent(range, size: size)
                connection.cancel()
            } else {
                self.sendBody(file, from: next, range: range, size: size, on: connection)
            }
        })
    }

    private func recordSent(_ range: Range<Int64>, size: Int64) {
        state.withLock { state in
            var merged: [Range<Int64>] = []
            for item in (state.coverage + [range]).sorted(by: { $0.lowerBound < $1.lowerBound }) {
                if let last = merged.last, item.lowerBound <= last.upperBound {
                    merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, item.upperBound)
                } else {
                    merged.append(item)
                }
            }
            if merged.count == 1, merged[0].lowerBound <= 0, merged[0].upperBound >= size {
                state.completedDownloads += 1
                state.coverage = []
            } else {
                state.coverage = merged
            }
        }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

final class OnceFlag: Sendable {
    private let value = Mutex(false)

    init() {}

    func set() -> Bool {
        value.withLock { value in
            defer { value = true }
            return !value
        }
    }

    var isSet: Bool { value.withLock { $0 } }
}

private final class SendableFileHandle: @unchecked Sendable {
    private let handle: FileHandle

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    func read(at offset: Int64, count: Int) -> Data? {
        do {
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: count)
        } catch {
            return nil
        }
    }

    func close() {
        try? handle.close()
    }
}

public enum LocalFileServerError: LocalizedError, Sendable, Equatable {
    case unreadable
    case noPort(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable:
            L("Couldn't open this file. It may have been moved or deleted.")
        case .noPort(let detail):
            detail.isEmpty
                ? L("Couldn't open a local port to share the file from this Mac.")
                : L("Couldn't open a local port to share the file from this Mac (%@).", detail)
        }
    }
}
