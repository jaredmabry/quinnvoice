import Foundation

/// REST client to the OpenClaw gateway for context and tool execution.
actor OpenClawBridge {
    let baseURL: URL

    init(baseURL: URL = URL(string: "http://127.0.0.1:18789")!) {
        self.baseURL = baseURL
    }

    // MARK: - Context Loading

    /// Fetch a file's content from the OpenClaw workspace.
    func fetchFileContent(path: String) async throws -> String {
        let url = baseURL.appendingPathComponent("api/files/read")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["path": path]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OpenClawError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        // Try to parse as JSON with a "content" field, fall back to raw string
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let content = json["content"] as? String {
            return content
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Tool Execution

    /// Execute a tool call through the OpenClaw gateway.
    func executeTool(name: String, arguments: [String: Any]) async throws -> String {
        let url = baseURL.appendingPathComponent("api/tools/execute")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "tool": name,
            "arguments": arguments
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OpenClawError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = json["result"] as? String {
            return result
        }

        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Check if the OpenClaw gateway is reachable.
    func healthCheck() async -> Bool {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

enum OpenClawError: Error, LocalizedError {
    case requestFailed(statusCode: Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .requestFailed(let code):
            return "OpenClaw request failed with status \(code)"
        case .invalidResponse:
            return "Invalid response from OpenClaw"
        }
    }
}
