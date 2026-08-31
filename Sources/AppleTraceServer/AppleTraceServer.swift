import AppleTrace
import AppleTraceProtocol
import CryptoKit
import Darwin
import Foundation
import Network
import Security

public struct AppleTraceServerConfiguration: Sendable {
    public var port: UInt16
    public var bindToLoopback: Bool
    public var token: String

    public init(port: UInt16 = 0, bindToLoopback: Bool = true, token: String? = nil) {
        self.port = port
        self.bindToLoopback = bindToLoopback
        self.token = token ?? Self.randomToken()
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

public final class AppleTraceControlServer: @unchecked Sendable {
    public enum ServerError: Error {
        case invalidPort
    }

    public let configuration: AppleTraceServerConfiguration
    public private(set) var listeningPort: UInt16?

    private let queue = DispatchQueue(label: "com.everettjf.appletrace.server")
    private var listener: NWListener?

    public init(configuration: AppleTraceServerConfiguration = .init()) {
        self.configuration = configuration
    }

    public func start() throws {
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: configuration.port) else {
            throw ServerError.invalidPort
        }
        let parameters = NWParameters.tcp
        if configuration.bindToLoopback {
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        }
        let listener = try NWListener(using: parameters, on: port)
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else { return }
            if case .ready = state {
                self.listeningPort = listener?.port?.rawValue
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        listeningPort = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, complete, error in
            guard let self else { return }
            var next = buffer
            if let data { next.append(data) }
            if let request = HTTPParser.parse(next) {
                self.respond(to: request, on: connection)
            } else if complete || error != nil || next.count >= (1 << 20) {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: next)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        guard authorized(request) else {
            send(json: APIErrorPayload("unauthorized"), status: 401, reason: "Unauthorized", on: connection)
            return
        }

        if request.path == "/api/v1/stream",
           request.headers["upgrade"]?.lowercased() == "websocket",
           let key = request.headers["sec-websocket-key"] {
            upgradeWebSocket(key: key, on: connection)
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/api/v1/status"):
            send(json: statusPayload(), on: connection)
        case ("POST", "/api/v1/capture/start"):
            _ = startCapture()
            send(json: statusPayload(), on: connection)
        case ("POST", "/api/v1/capture/stop"):
            stopCapture()
            send(json: statusPayload(), on: connection)
        case ("POST", "/api/v1/filters"):
            do {
                let filters = try JSONDecoder().decode(FilterConfigurationPayload.self, from: request.body)
                apply(filters: filters)
                send(json: filters, on: connection)
            } catch {
                send(json: APIErrorPayload("invalid filter configuration"), status: 400, reason: "Bad Request", on: connection)
            }
        case ("GET", "/api/v1/artifacts"):
            send(json: artifacts(), on: connection)
        default:
            if request.method == "GET", request.path.hasPrefix("/api/v1/artifacts/") {
                sendArtifact(path: request.path, on: connection)
            } else {
                send(json: APIErrorPayload("not found"), status: 404, reason: "Not Found", on: connection)
            }
        }
    }

    private func authorized(_ request: HTTPRequest) -> Bool {
        request.headers["authorization"] == "Bearer \(configuration.token)" ||
            request.headers["x-appletrace-token"] == configuration.token
    }

    private func statusPayload() -> AgentStatusPayload {
        let metrics = traceMetrics
        return AgentStatusPayload(
            processId: getpid(),
            processName: ProcessInfo.processInfo.processName,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            architecture: Self.architecture,
            captureState: String(describing: captureState),
            objcHookInstalled: Self.isObjcHookInstalled(),
            traceDirectory: traceDirectory,
            metrics: .init(
                acceptedEvents: metrics.acceptedEvents,
                pendingBytes: metrics.pendingBytes,
                writeFailures: metrics.writeFailures
            )
        )
    }

    private func artifacts() -> [ArtifactPayload] {
        let directory = URL(fileURLWithPath: traceDirectory, isDirectory: true)
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { url in
            guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }
            return ArtifactPayload(
                name: url.lastPathComponent,
                size: UInt64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func apply(filters: FilterConfigurationPayload) {
        typealias FilterFunction = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "APTSetObjcTraceClassFilters") else {
            return
        }
        let function = unsafeBitCast(symbol, to: FilterFunction.self)
        let allow = filters.allowClassPrefixes.joined(separator: ",")
        let deny = filters.denyClassPrefixes.joined(separator: ",")
        allow.withCString { allowPointer in
            deny.withCString { denyPointer in
                function(allow.isEmpty ? nil : allowPointer, deny.isEmpty ? nil : denyPointer)
            }
        }
    }

    private func sendArtifact(path: String, on connection: NWConnection) {
        let encodedName = String(path.dropFirst("/api/v1/artifacts/".count))
        guard let name = encodedName.removingPercentEncoding,
              !name.isEmpty,
              name == URL(fileURLWithPath: name).lastPathComponent else {
            send(json: APIErrorPayload("invalid artifact name"), status: 400, reason: "Bad Request", on: connection)
            return
        }
        let directory = URL(fileURLWithPath: traceDirectory, isDirectory: true).standardizedFileURL
        let file = directory.appendingPathComponent(name, isDirectory: false).standardizedFileURL
        guard file.deletingLastPathComponent() == directory,
              let body = try? Data(contentsOf: file, options: [.mappedIfSafe]) else {
            send(json: APIErrorPayload("artifact not found"), status: 404, reason: "Not Found", on: connection)
            return
        }
        let response = HTTPResponse(
            status: 200,
            reason: "OK",
            headers: [
                "Content-Type": "application/octet-stream",
                "Content-Disposition": "attachment; filename=\"\(name.replacingOccurrences(of: "\"", with: ""))\"",
            ],
            body: body
        )
        connection.send(content: response.encoded(), completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func isObjcHookInstalled() -> Bool {
        typealias HookStatusFunction = @convention(c) () -> Bool
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "APTIsObjcMsgSendHookInstalled") else {
            return false
        }
        return unsafeBitCast(symbol, to: HookStatusFunction.self)()
    }

    private func send<T: Encodable>(json value: T, status: Int = 200, reason: String = "OK", on connection: NWConnection) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = (try? encoder.encode(value)) ?? Data("{}".utf8)
        let response = HTTPResponse(
            status: status,
            reason: reason,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: body
        )
        connection.send(content: response.encoded(), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func upgradeWebSocket(key: String, on connection: NWConnection) {
        let source = Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8)
        let accept = Data(Insecure.SHA1.hash(data: source)).base64EncodedString()
        let response = HTTPResponse(
            status: 101,
            reason: "Switching Protocols",
            headers: [
                "Connection": "Upgrade",
                "Upgrade": "websocket",
                "Sec-WebSocket-Accept": accept,
            ]
        )
        var bytes = response.encoded()
        let encoder = JSONEncoder()
        if let payload = try? encoder.encode(statusPayload()) {
            bytes.append(Self.webSocketTextFrame(payload))
        }
        connection.send(content: bytes, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func webSocketTextFrame(_ payload: Data) -> Data {
        var frame = Data([0x81])
        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else if payload.count <= Int(UInt16.max) {
            frame.append(126)
            var length = UInt16(payload.count).bigEndian
            withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        } else {
            frame.append(127)
            var length = UInt64(payload.count).bigEndian
            withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        }
        frame.append(payload)
        return frame
    }

    private static var architecture: String {
#if arch(arm64)
        return "arm64"
#elseif arch(x86_64)
        return "x86_64"
#else
        return "unknown"
#endif
    }
}
