import Foundation
import Network

public struct HTTPRequest: Sendable {
    public let method: String
    /// Path without the query string.
    public let path: String
    /// Header names are lowercased.
    public let headers: [String: String]
    public let body: Data
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var contentType: String
    public var body: Data

    public static func json(_ status: Int, _ object: [String: Any]) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return HTTPResponse(status: status, contentType: "application/json", body: body)
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 100: return "Continue"
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 411: return "Length Required"
        case 413: return "Payload Too Large"
        case 422: return "Unprocessable Content"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        default: return "Status"
        }
    }
}

/// Minimal HTTP/1.1 server: one request per connection, Content-Length bodies only.
public final class HTTPServer {
    public typealias Handler = (HTTPRequest, @escaping (HTTPResponse) -> Void) -> Void

    public var onStateChange: ((NWListener.State) -> Void)?

    private let port: UInt16
    private let maxBodyBytes: Int
    private let handler: Handler
    private let queue = DispatchQueue(label: "macclip.http")
    private var listener: NWListener?
    /// Accessed on `queue` only.
    private var connections: [ObjectIdentifier: HTTPConnection] = [:]

    public init(port: UInt16, maxBodyBytes: Int, handler: @escaping Handler) {
        self.port = port
        self.maxBodyBytes = maxBodyBytes
        self.handler = handler
    }

    public func start(service: NWListener.Service?) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw NWError.posix(.EINVAL) }
        let listener = try NWListener(using: params, on: nwPort)
        listener.service = service
        listener.stateUpdateHandler = { [weak self] state in self?.onStateChange?(state) }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ nwConnection: NWConnection) {
        let connection = HTTPConnection(connection: nwConnection, queue: queue, maxBodyBytes: maxBodyBytes, handler: handler)
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.onClose = { [weak self] in self?.connections[key] = nil }
        connection.start()
    }
}

final class HTTPConnection {
    private static let headerTerminator = Data("\r\n\r\n".utf8)
    private static let maxHeaderBytes = 16 * 1024
    private static let timeout: TimeInterval = 60

    var onClose: (() -> Void)?

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let maxBodyBytes: Int
    private let handler: HTTPServer.Handler

    private var buffer = Data()
    private var head: (method: String, path: String, headers: [String: String], bodyStart: Int, length: Int)?
    private var finished = false

    init(connection: NWConnection, queue: DispatchQueue, maxBodyBytes: Int, handler: @escaping HTTPServer.Handler) {
        self.connection = connection
        self.queue = queue
        self.maxBodyBytes = maxBodyBytes
        self.handler = handler
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
            guard let self, !self.finished else { return }
            self.respond(.json(408, ["error": "timeout"]))
        }
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self, !self.finished else { return }
            if let data { self.buffer.append(data) }
            if error != nil { self.close(); return }
            if self.process() { return }
            if isComplete { self.close(); return }
            self.receive()
        }
    }

    /// Returns true once a response is on its way.
    private func process() -> Bool {
        if head == nil {
            guard let end = buffer.range(of: Self.headerTerminator) else {
                if buffer.count > Self.maxHeaderBytes {
                    respond(.json(431, ["error": "headers too large"]))
                    return true
                }
                return false
            }
            guard let text = String(data: buffer[buffer.startIndex..<end.lowerBound], encoding: .utf8) else {
                respond(.json(400, ["error": "malformed"]))
                return true
            }
            var lines = text.components(separatedBy: "\r\n")
            let requestLine = lines.removeFirst().split(separator: " ")
            guard requestLine.count == 3 else {
                respond(.json(400, ["error": "malformed"]))
                return true
            }
            var headers: [String: String] = [:]
            for line in lines {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            if headers["transfer-encoding"] != nil {
                respond(.json(411, ["error": "chunked bodies are not supported"]))
                return true
            }
            let length = Int(headers["content-length"] ?? "0") ?? -1
            if length < 0 {
                respond(.json(400, ["error": "bad content-length"]))
                return true
            }
            if length > maxBodyBytes {
                respond(.json(413, ["error": "too large"]))
                return true
            }
            let target = String(requestLine[1])
            let path = String(target.split(separator: "?", maxSplits: 1).first ?? "")
            head = (String(requestLine[0]), path, headers, end.upperBound - buffer.startIndex, length)
            // curl sends this for large bodies and waits a moment for permission.
            if headers["expect"]?.lowercased() == "100-continue" {
                connection.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .idempotent)
            }
        }

        guard let head, buffer.count - head.bodyStart >= head.length else { return false }
        let start = buffer.startIndex + head.bodyStart
        let request = HTTPRequest(method: head.method, path: head.path, headers: head.headers,
                                  body: Data(buffer[start..<(start + head.length)]))
        finished = true
        buffer = Data()
        handler(request) { [weak self] response in
            self?.queue.async { self?.send(response) }
        }
        return true
    }

    private func respond(_ response: HTTPResponse) {
        finished = true
        send(response)
    }

    private func send(_ response: HTTPResponse) {
        var head = "HTTP/1.1 \(response.status) \(HTTPResponse.reason(response.status))\r\n"
        head += "Content-Type: \(response.contentType)\r\n"
        head += "Content-Length: \(response.body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(response.body)
        connection.send(content: data, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.close()
        })
    }

    private func close() {
        finished = true
        connection.cancel()
        let callback = onClose
        onClose = nil
        callback?()
    }
}
