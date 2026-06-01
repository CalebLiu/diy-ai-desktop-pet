import Foundation
import Network

/// 极简 HTTP server,只接 localhost:7777,支持桌宠状态和 agent hooks:
///   POST /state    body: {"state": "thinking" | "done" | "idle" | "resting"}
///   POST /task     body: {"task": "任务描述文本"}
///   POST /prompt   body: {"prompt": "用户输入", "session_id": "...", "source": "Claude|Codex"}
///   POST /session_done body: {"session_id": "...", "source": "Claude|Codex"}
///
/// 用 Network.framework 的 NWListener,无第三方依赖。
final class HTTPServer {
    private var listener: NWListener?
    private let port: NWEndpoint.Port = 7777
    private let queue = DispatchQueue(label: "pet.http")

    var onState: ((String) -> Void)?
    var onTask: ((String) -> Void)?
    var onPrompt: ((String, String?, String?) -> Void)?    // (prompt, sessionId, source)
    var onSessionDone: ((String, String?) -> Void)?         // (sessionId, source)

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: port)
        } catch {
            NSLog("HTTPServer failed to bind on port \(port): \(error)")
            return
        }
        listener?.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener?.start(queue: queue)
        NSLog("HTTPServer listening on 127.0.0.1:\(port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    /// 持续接收直到读到完整 header(以 \r\n\r\n 结尾)+ Content-Length 指定的 body 字节
    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, _ in
            guard let self = self else { return }
            var newBuffer = buffer
            if let data = data {
                newBuffer.append(data)
            }
            if self.isComplete(newBuffer) {
                self.process(newBuffer, conn: conn)
            } else if isComplete {
                conn.cancel()
            } else {
                self.receive(conn, buffer: newBuffer)
            }
        }
    }

    private func isComplete(_ buffer: Data) -> Bool {
        guard let str = String(data: buffer, encoding: .utf8) else { return false }
        guard let headerEnd = str.range(of: "\r\n\r\n") else { return false }
        // 找 Content-Length
        let headers = String(str[..<headerEnd.lowerBound])
        var contentLength = 0
        for line in headers.split(separator: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.split(separator: ":", maxSplits: 1).last ?? ""
                contentLength = Int(value.trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyStart = str.distance(from: str.startIndex, to: headerEnd.upperBound)
        let bodyBytes = buffer.count - bodyStart
        return bodyBytes >= contentLength
    }

    private func process(_ buffer: Data, conn: NWConnection) {
        guard let request = String(data: buffer, encoding: .utf8) else {
            respond(conn, status: 400, body: "bad request")
            return
        }
        let lines = request.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let firstLine = lines.first else {
            respond(conn, status: 400, body: "bad request")
            return
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            respond(conn, status: 400, body: "bad request")
            return
        }
        let method = String(parts[0])
        let path = String(parts[1])

        let body: String
        if let bodyRange = request.range(of: "\r\n\r\n") {
            body = String(request[bodyRange.upperBound...])
        } else {
            body = ""
        }

        if method == "POST" && path == "/state" {
            if let state = parseJSONValue(body, key: "state") {
                DispatchQueue.main.async { [weak self] in
                    self?.onState?(state)
                }
                respond(conn, status: 200, body: "ok")
                return
            }
        } else if method == "POST" && path == "/task" {
            if let task = parseJSONValue(body, key: "task") {
                DispatchQueue.main.async { [weak self] in
                    self?.onTask?(task)
                }
                respond(conn, status: 200, body: "ok")
                return
            }
        } else if method == "POST" && path == "/prompt" {
            if let prompt = parseJSONValue(body, key: "prompt") {
                let sessionId = parseJSONValue(body, key: "session_id")
                let source = parseJSONValue(body, key: "source")
                DispatchQueue.main.async { [weak self] in
                    self?.onPrompt?(prompt, sessionId, source)
                }
                respond(conn, status: 200, body: "ok")
                return
            }
        } else if method == "POST" && path == "/session_done" {
            if let sessionId = parseJSONValue(body, key: "session_id") {
                let source = parseJSONValue(body, key: "source")
                DispatchQueue.main.async { [weak self] in
                    self?.onSessionDone?(sessionId, source)
                }
                respond(conn, status: 200, body: "ok")
                return
            }
        } else if method == "GET" && path == "/health" {
            respond(conn, status: 200, body: "ok")
            return
        }

        respond(conn, status: 404, body: "not found")
    }

    /// 简易 JSON 取值:{"state":"thinking"} → "thinking"
    /// 只支持顶层单字段、值是字符串、没有嵌套
    private func parseJSONValue(_ body: String, key: String) -> String? {
        guard let data = body.data(using: .utf8) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json[key] as? String
    }

    private func respond(_ conn: NWConnection, status: Int, body: String) {
        let statusText = (status == 200) ? "OK" : (status == 404 ? "Not Found" : "Bad Request")
        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
