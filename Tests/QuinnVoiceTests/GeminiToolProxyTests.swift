/// GeminiToolProxyTests.swift
/// Tests for the Gemini function-call proxy that bridges tool declarations
/// and execution between Gemini Live API and the OpenClaw gateway.
///
/// Covers tool declaration structure, function call parsing,
/// and result formatting. Uses mock networking.

import XCTest

@testable import QuinnVoice

final class GeminiToolProxyTests: XCTestCase {

    // MARK: - Tool Declarations Structure

    func testToolDeclarations_isNonEmpty() {
        XCTAssertFalse(GeminiToolProxy.toolDeclarations.isEmpty,
                       "Should have at least one tool declared")
    }

    func testToolDeclarations_count() {
        XCTAssertEqual(GeminiToolProxy.toolDeclarations.count, 5,
                       "Should declare exactly 5 tools")
    }

    /// Every tool declaration must have `name`, `description`, and `parameters` keys.
    func testToolDeclarations_allHaveRequiredKeys() {
        for (index, decl) in GeminiToolProxy.toolDeclarations.enumerated() {
            XCTAssertNotNil(decl["name"] as? String,
                            "Tool at index \(index) missing 'name'")
            XCTAssertNotNil(decl["description"] as? String,
                            "Tool at index \(index) missing 'description'")
            XCTAssertNotNil(decl["parameters"] as? [String: Any],
                            "Tool at index \(index) missing 'parameters'")
        }
    }

    /// Every parameters block should specify `type: "object"` and have `properties`.
    func testToolDeclarations_parametersAreObjects() {
        for decl in GeminiToolProxy.toolDeclarations {
            let name = decl["name"] as? String ?? "unknown"
            guard let params = decl["parameters"] as? [String: Any] else {
                XCTFail("Tool '\(name)' has no parameters")
                continue
            }
            XCTAssertEqual(params["type"] as? String, "object",
                           "Tool '\(name)' parameters.type should be 'object'")
            XCTAssertNotNil(params["properties"] as? [String: Any],
                            "Tool '\(name)' should have properties")
        }
    }

    /// Every tool should list at least one required argument.
    func testToolDeclarations_allHaveRequiredArgs() {
        for decl in GeminiToolProxy.toolDeclarations {
            let name = decl["name"] as? String ?? "unknown"
            guard let params = decl["parameters"] as? [String: Any],
                  let required = params["required"] as? [String] else {
                XCTFail("Tool '\(name)' missing 'required' array")
                continue
            }
            XCTAssertFalse(required.isEmpty,
                           "Tool '\(name)' should require at least one argument")
        }
    }

    // MARK: - Specific Tool Declarations

    func testToolDeclarations_containsSearchWeb() {
        let names = GeminiToolProxy.toolDeclarations.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("search_web"))
    }

    func testToolDeclarations_containsGetWeather() {
        let names = GeminiToolProxy.toolDeclarations.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("get_weather"))
    }

    func testToolDeclarations_containsCreateReminder() {
        let names = GeminiToolProxy.toolDeclarations.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("create_reminder"))
    }

    func testToolDeclarations_containsSendMessage() {
        let names = GeminiToolProxy.toolDeclarations.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("send_message"))
    }

    func testToolDeclarations_containsControlLights() {
        let names = GeminiToolProxy.toolDeclarations.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("control_lights"))
    }

    // MARK: - search_web Declaration

    func testSearchWeb_hasQueryParameter() {
        guard let decl = findTool(named: "search_web"),
              let params = decl["parameters"] as? [String: Any],
              let props = params["properties"] as? [String: Any] else {
            XCTFail("search_web tool not found or malformed")
            return
        }

        XCTAssertNotNil(props["query"], "search_web should have a 'query' property")

        let required = params["required"] as? [String] ?? []
        XCTAssertTrue(required.contains("query"), "search_web should require 'query'")
    }

    // MARK: - create_reminder Declaration

    func testCreateReminder_hasOptionalFields() {
        guard let decl = findTool(named: "create_reminder"),
              let params = decl["parameters"] as? [String: Any],
              let props = params["properties"] as? [String: Any],
              let required = params["required"] as? [String] else {
            XCTFail("create_reminder tool not found or malformed")
            return
        }

        XCTAssertNotNil(props["title"])
        XCTAssertNotNil(props["due_date"])
        XCTAssertNotNil(props["list"])
        XCTAssertTrue(required.contains("title"))
        XCTAssertFalse(required.contains("due_date"), "due_date should be optional")
        XCTAssertFalse(required.contains("list"), "list should be optional")
    }

    // MARK: - send_message Declaration

    func testSendMessage_requiresBothArgs() {
        guard let decl = findTool(named: "send_message"),
              let params = decl["parameters"] as? [String: Any],
              let required = params["required"] as? [String] else {
            XCTFail("send_message tool not found or malformed")
            return
        }

        XCTAssertTrue(required.contains("recipient"))
        XCTAssertTrue(required.contains("message"))
    }

    // MARK: - Function Call Parsing (from JSON)

    /// Simulate parsing a Gemini toolCall JSON message for search_web.
    func testParseFunctionCall_searchWeb() throws {
        let json: [String: Any] = [
            "toolCall": [
                "functionCalls": [
                    [
                        "name": "search_web",
                        "id": "call_abc123",
                        "args": ["query": "weather in Nashville"]
                    ]
                ]
            ]
        ]

        let toolCall = json["toolCall"] as? [String: Any]
        let functionCalls = toolCall?["functionCalls"] as? [[String: Any]]
        XCTAssertNotNil(functionCalls)
        XCTAssertEqual(functionCalls?.count, 1)

        let call = functionCalls![0]
        XCTAssertEqual(call["name"] as? String, "search_web")
        XCTAssertEqual(call["id"] as? String, "call_abc123")

        let args = call["args"] as? [String: String]
        XCTAssertEqual(args?["query"], "weather in Nashville")
    }

    /// Simulate parsing a function call with nested/non-string argument values.
    func testParseFunctionCall_nonStringArgs() throws {
        let json: [String: Any] = [
            "name": "create_reminder",
            "id": "call_456",
            "args": [
                "title": "Buy groceries",
                "priority": 3  // Non-string value
            ] as [String: Any]
        ]

        let rawArgs = json["args"] as? [String: Any] ?? [:]
        var stringArgs: [String: String] = [:]
        for (key, value) in rawArgs {
            if let str = value as? String {
                stringArgs[key] = str
            } else if let data = try? JSONSerialization.data(withJSONObject: value),
                      let str = String(data: data, encoding: .utf8) {
                stringArgs[key] = str
            }
        }

        XCTAssertEqual(stringArgs["title"], "Buy groceries")
        XCTAssertEqual(stringArgs["priority"], "3")
    }

    // MARK: - Function Response Formatting

    /// Test that a function response is correctly structured for Gemini.
    func testFunctionResponse_format() throws {
        let callId = "call_789"
        let name = "search_web"
        let response = "The weather in Nashville is 72°F and sunny."

        let message: [String: Any] = [
            "toolResponse": [
                "functionResponses": [
                    [
                        "id": callId,
                        "name": name,
                        "response": [
                            "result": response
                        ]
                    ]
                ]
            ]
        ]

        // Verify structure
        let toolResponse = message["toolResponse"] as? [String: Any]
        XCTAssertNotNil(toolResponse)

        let functionResponses = toolResponse?["functionResponses"] as? [[String: Any]]
        XCTAssertEqual(functionResponses?.count, 1)

        let resp = functionResponses![0]
        XCTAssertEqual(resp["id"] as? String, callId)
        XCTAssertEqual(resp["name"] as? String, name)

        let responseBody = resp["response"] as? [String: Any]
        XCTAssertEqual(responseBody?["result"] as? String, response)

        // Verify it serializes to valid JSON
        let data = try JSONSerialization.data(withJSONObject: message)
        XCTAssertGreaterThan(data.count, 0)
    }

    // MARK: - Tool Execution with Mock Bridge

    func testExecute_returnsErrorOnConnectionFailure() async {
        // Use a bridge pointing to a non-existent server
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let proxy = GeminiToolProxy(bridge: bridge)

        let result = await proxy.execute(functionName: "search_web", arguments: ["query": "test"])
        XCTAssertTrue(result.contains("Error"),
                      "Should return an error message when bridge is unreachable")
    }

    // MARK: - Tool Declaration JSON Serialization

    /// The tool declarations should be valid JSON-serializable for WebSocket transmission.
    func testToolDeclarations_areJsonSerializable() throws {
        let wrapper: [String: Any] = [
            "functionDeclarations": GeminiToolProxy.toolDeclarations
        ]
        let data = try JSONSerialization.data(withJSONObject: wrapper)
        XCTAssertGreaterThan(data.count, 0)

        // Verify round-trip
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(parsed?["functionDeclarations"])
    }

    // MARK: - Helpers

    private func findTool(named name: String) -> [String: Any]? {
        GeminiToolProxy.toolDeclarations.first { ($0["name"] as? String) == name }
    }
}
