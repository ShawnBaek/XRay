import Foundation

enum MCPEnvelope {
    static func result(from data: Data, id: Int) throws -> [String: Any]? {
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DesignError("Desktop MCP returned an invalid JSON response.")
        }
        guard envelope["id"] as? Int == id else { return nil }
        if let error = envelope["error"] as? [String: Any] {
            let message = (error["message"] as? String ?? "Unknown protocol failure.").prefix(500)
            throw DesignError("Desktop MCP protocol error \(error["code"] as? Int ?? 0): \(message)")
        }
        guard let result = envelope["result"] as? [String: Any] else {
            throw DesignError("Desktop MCP response has no result.")
        }
        if result["isError"] as? Bool == true {
            let text = (result["content"] as? [[String: Any]])?
                .compactMap { $0["text"] as? String }.first ?? "Unknown tool failure."
            throw DesignError("Desktop MCP could not read the reference: \(text.prefix(500))")
        }
        return result
    }

    static func xml(from result: [String: Any]) throws -> String {
        let candidates = (result["content"] as? [[String: Any]] ?? []).compactMap { block -> String? in
            guard block["type"] as? String == "text", let text = block["text"] as? String,
                  text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") else { return nil }
            return text
        }
        guard candidates.count == 1 else { throw DesignError("Desktop MCP did not return one metadata XML document.") }
        return candidates[0]
    }

    static func png(from result: [String: Any]) throws -> Data {
        let images = (result["content"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "image" }
        guard images.count == 1, images[0]["mimeType"] as? String == "image/png",
              let base64 = images[0]["data"] as? String, base64.utf8.count <= 86_000_000,
              let data = Data(base64Encoded: base64) else {
            throw DesignError("Desktop MCP did not return one inline PNG. This tool never falls back to remote Figma or downloads arbitrary URLs.")
        }
        return data
    }
}

@MainActor
final class DesktopMCP {
    static let endpoint = URL(string: "http://127.0.0.1:3845/mcp")!
    private let session: URLSession
    private var sessionID: String?
    private var protocolVersion = "2025-06-18"
    private var nextID = 0
    private(set) var serverVersion = ""

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func connect() async throws {
        let initialized = try await request(method: "initialize", params: [
            "protocolVersion": protocolVersion, "capabilities": [:],
            "clientInfo": ["name": "xray-design", "version": "1.0.0"],
        ])
        guard let negotiated = initialized["protocolVersion"] as? String,
              ["2025-03-26", "2025-06-18"].contains(negotiated),
              let info = initialized["serverInfo"] as? [String: Any],
              let version = info["version"] as? String, !version.isEmpty else {
            throw DesignError("Desktop MCP uses an unsupported initialization response or protocol version.")
        }
        protocolVersion = negotiated
        serverVersion = version
        _ = try await request(method: "notifications/initialized", params: nil, notification: true)
        var tools: [[String: Any]] = []
        var cursor: String?
        for _ in 0..<4 {
            let listed = try await request(method: "tools/list", params: cursor.map { ["cursor": $0] } ?? [:])
            tools += listed["tools"] as? [[String: Any]] ?? []
            cursor = listed["nextCursor"] as? String
            if cursor == nil { break }
        }
        guard cursor == nil else { throw DesignError("Desktop MCP tool listing exceeded the supported page limit.") }
        for name in ["get_metadata", "get_screenshot"] {
            guard let tool = tools.first(where: { $0["name"] as? String == name }),
                  let schema = tool["inputSchema"] as? [String: Any],
                  let properties = schema["properties"] as? [String: Any], properties["nodeId"] != nil else {
                throw DesignError("Figma Desktop MCP is missing the supported \(name) tool.")
            }
            let known = Set(name == "get_metadata" ? ["nodeId", "clientLanguages", "clientFrameworks"] : ["nodeId", "contentsOnly"])
            guard Set(schema["required"] as? [String] ?? []).isSubset(of: known),
                  name != "get_screenshot" || properties["contentsOnly"] != nil else {
                throw DesignError("Figma Desktop MCP changed the \(name) input contract. Update xray before importing.")
            }
        }
    }

    func capture(source: DesignSource) async throws -> (Data, ReferenceMetadata) {
        let arguments: [String: Any] = ["nodeId": source.nodeID, "clientLanguages": "swift", "clientFrameworks": "uikit,swiftui"]
        let before = try MCPEnvelope.xml(from: await call("get_metadata", arguments: arguments))
        let geometry = try NodeGeometry.parse(xml: before, expectedNodeID: source.nodeID)
        let screenshot = try await call("get_screenshot", arguments: ["nodeId": source.nodeID, "contentsOnly": true])
        let png = try MCPEnvelope.png(from: screenshot)
        let after = try MCPEnvelope.xml(from: await call("get_metadata", arguments: arguments))
        guard before == after else { throw DesignError("The design metadata changed during capture. Keep the source unchanged and retry.") }
        return (png, try ReferenceMetadata(source: source, geometry: geometry, png: png, serverVersion: serverVersion))
    }

    private func call(_ name: String, arguments: [String: Any]) async throws -> [String: Any] {
        try await request(method: "tools/call", params: ["name": name, "arguments": arguments])
    }

    private func request(method: String, params: [String: Any]?, notification: Bool = false) async throws -> [String: Any] {
        nextID += 1
        let id = nextID
        var body: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if !notification { body["id"] = id }
        if let params { body["params"] = params }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if method != "initialize" { request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version") }
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do { (bytes, response) = try await session.bytes(for: request) }
        catch { throw DesignError("Cannot reach Figma Desktop MCP at 127.0.0.1:3845. Open Figma Desktop and enable its MCP server in Dev Mode.") }
        guard let http = response as? HTTPURLResponse else { throw DesignError("Invalid desktop HTTP response.") }
        if http.statusCode == 404, sessionID != nil {
            sessionID = nil
            throw DesignError("Figma Desktop MCP session expired. Check the open file and run the command again.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DesignError("Figma Desktop MCP returned HTTP \(http.statusCode). No reference files were changed.")
        }
        if let value = http.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionID = value }
        if notification {
            guard http.statusCode == 202 else { throw DesignError("Desktop MCP did not accept initialization.") }
            return [:]
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        let limit = 90_000_000
        if contentType.contains("text/event-stream") {
            var parser = MCPEventStream(limit: limit)
            for try await byte in bytes {
                if let event = try parser.append(byte),
                   let result = try MCPEnvelope.result(from: event, id: id) { return result }
            }
        } else if contentType.contains("application/json") {
            var data = Data()
            for try await byte in bytes {
                guard data.count < limit else { throw DesignError("Desktop MCP response exceeds the supported size limit.") }
                data.append(byte)
            }
            if let result = try MCPEnvelope.result(from: data, id: id) { return result }
        } else { throw DesignError("Desktop MCP returned an unsupported content type.") }
        throw DesignError("Desktop MCP closed without a matching response.")
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
