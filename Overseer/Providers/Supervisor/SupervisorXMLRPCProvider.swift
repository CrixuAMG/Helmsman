import Foundation

final class SupervisorXMLRPCProvider: ServiceManagerProvider, @unchecked Sendable {
    private let endpoint: URL
    private let username: String?
    private let password: String?
    private let timeout: TimeInterval

    init(
        endpoint: URL,
        username: String?,
        password: String?,
        timeout: TimeInterval
    ) {
        self.endpoint = endpoint
        self.username = username
        self.password = password
        self.timeout = timeout
    }

    nonisolated func getAllProcesses() async throws -> [SupervisorProcess] {
        let response = try await callMethod("supervisor.getAllProcessInfo", params: [])
        return try parseProcessList(from: response)
    }

    nonisolated func startProcess(_ name: String) async throws {
        print("[DEBUG] XMLRPCProvider.startProcess() name: \(name), endpoint: \(endpoint)")
        _ = try await callMethod("supervisor.startProcess", params: [.string(name), .bool(true)])
        print("[DEBUG] XMLRPCProvider.startProcess() SUCCESS")
    }

    nonisolated func stopProcess(_ name: String) async throws {
        print("[DEBUG] XMLRPCProvider.stopProcess() name: \(name), endpoint: \(endpoint)")
        _ = try await callMethod("supervisor.stopProcess", params: [.string(name), .bool(true)])
        print("[DEBUG] XMLRPCProvider.stopProcess() SUCCESS")
    }

    nonisolated func restartProcess(_ name: String) async throws {
        print("[DEBUG] XMLRPCProvider.restartProcess() name: \(name), endpoint: \(endpoint)")
        try await stopProcess(name)
        try await startProcess(name)
        print("[DEBUG] XMLRPCProvider.restartProcess() SUCCESS")
    }

    // MARK: - XML-RPC Call

    private nonisolated func callMethod(_ method: String, params: [XMLRPCValue]) async throws -> XMLRPCValue {
        let requestXML = buildRequest(method: method, params: params)

        print("[DEBUG] XMLRPCProvider.callMethod: \(method), endpoint: \(endpoint)")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("text/xml", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        if let username = username, let password = password {
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                let base64 = data.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }

        request.httpBody = requestXML.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.actionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw ServiceError.actionFailed("HTTP \(httpResponse.statusCode)")
        }

        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw ServiceError.actionFailed("Invalid response encoding")
        }

        return try parseResponse(xmlString)
    }

    // MARK: - Request Building

    private nonisolated func buildRequest(method: String, params: [XMLRPCValue]) -> String {
        var xml = """
        <?xml version="1.0"?>
        <methodCall>
          <methodName>\(escapeXML(method))</methodName>
          <params>
        """

        for param in params {
            xml += "    <param>\n      <value>\(param.toXML())</value>\n    </param>\n"
        }

        xml += """
          </params>
        </methodCall>
        """

        return xml
    }

    // MARK: - Response Parsing

    private nonisolated func parseResponse(_ xml: String) throws -> XMLRPCValue {
        let parser = XMLRPCResponseParser(xml: xml)
        return try parser.parse()
    }

    private nonisolated func parseProcessList(from value: XMLRPCValue) throws -> [SupervisorProcess] {
        guard case .array(let items) = value else {
            throw ServiceError.actionFailed("Expected array response")
        }

        return items.compactMap { item -> SupervisorProcess? in
            guard case .struct(let fields) = item else { return nil }

            let name = extractString(from: fields["name"]) ?? ""
            let group = extractString(from: fields["group"]) ?? name
            let statusStr = extractString(from: fields["statename"]) ?? "UNKNOWN"
            let description = extractString(from: fields["description"]) ?? ""
            let pid = extractInt(from: fields["pid"]) ?? 0

            let status: ServiceStatus
            switch statusStr.uppercased() {
            case "RUNNING": status = .running
            case "STOPPED": status = .stopped
            case "STARTING": status = .starting
            case "BACKOFF": status = .backingoff
            case "STOPPING": status = .stopping
            case "EXITED": status = .exited
            case "FATAL": status = .fatal
            default: status = .unknown
            }

            return SupervisorProcess(
                name: name,
                group: group,
                status: status,
                description: description,
                pid: pid,
                uptime: nil,
                exitStatus: nil
            )
        }
    }

    private nonisolated func extractString(from value: XMLRPCValue?) -> String? {
        guard case .string(let str) = value else { return nil }
        return str
    }

    private nonisolated func extractInt(from value: XMLRPCValue?) -> Int? {
        switch value {
        case .int(let i): return i
        case .string(let s): return Int(s)
        default: return nil
        }
    }

    private nonisolated func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - XML-RPC Value Types

enum XMLRPCValue: Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([XMLRPCValue])
    case `struct`([String: XMLRPCValue])

    nonisolated func toXML() -> String {
        switch self {
        case .string(let str):
            return "<string>\(str)</string>"
        case .int(let i):
            return "<int>\(i)</int>"
        case .bool(let b):
            return "<boolean>\(b ? "1" : "0")</boolean>"
        case .array(let items):
            var xml = "<array><data>\n"
            for item in items {
                xml += "  <value>\(item.toXML())</value>\n"
            }
            xml += "</data></array>"
            return xml
        case .struct(let fields):
            var xml = "<struct>\n"
            for (key, value) in fields {
                xml += "  <member>\n    <name>\(key)</name>\n    <value>\(value.toXML())</value>\n  </member>\n"
            }
            xml += "</struct>"
            return xml
        }
    }
}
