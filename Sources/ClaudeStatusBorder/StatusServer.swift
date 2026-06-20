import Foundation
import Network

/// Tiny localhost HTTP server. Accepts `POST /status` with a JSON `StatusUpdate`
/// body and forwards it to the model. Zero dependencies (Network framework).
final class StatusServer {
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private let onUpdate: (StatusUpdate) -> Void

    init(port: UInt16, onUpdate: @escaping (StatusUpdate) -> Void) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.onUpdate = onUpdate
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            // Bind to loopback only — never exposed off the machine.
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            listener.start(queue: .global(qos: .userInitiated))
            self.listener = listener
            NSLog("ClaudeStatusBorder: listening on 127.0.0.1:\(port)")
        } catch {
            NSLog("ClaudeStatusBorder: failed to start server: \(error)")
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let complete = self.tryParse(buffer) {
                self.onUpdate(complete)
                self.respond(conn)
                return
            }
            if error != nil || isComplete {
                self.respond(conn)
                return
            }
            self.receive(conn, buffer: buffer)
        }
    }

    /// Returns a parsed update once the full HTTP body has arrived, else nil.
    private func tryParse(_ buffer: Data) -> StatusUpdate? {
        guard let separator = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer[..<separator.lowerBound]
        let body = buffer[separator.upperBound...]

        guard let header = String(data: headerData, encoding: .utf8) else { return nil }
        let contentLength = Self.contentLength(header) ?? 0
        guard body.count >= contentLength, contentLength > 0 else { return nil }

        let jsonData = body.prefix(contentLength)
        return try? JSONDecoder().decode(StatusUpdate.self, from: Data(jsonData))
    }

    private static func contentLength(_ header: String) -> Int? {
        for line in header.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    private func respond(_ conn: NWConnection) {
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
        conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
