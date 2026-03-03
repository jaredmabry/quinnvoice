/// ToolExecutionFlowTests.swift — Integration tests for tool call routing and confirmation gates.

import XCTest

@testable import QuinnVoice

final class ToolExecutionFlowTests: XCTestCase {

    // MARK: - End-to-End Tool Routing

    func testToolCall_searchWeb_routesToBridge() async {
        // With an unreachable bridge, should return an error
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let proxy = GeminiToolProxy(bridge: bridge)

        let result = await proxy.execute(
            functionName: "search_web",
            arguments: ["query": "Nashville weather"]
        )

        // The result should indicate an error (unreachable bridge)
        XCTAssertTrue(result.contains("Error") || result.contains("error"))
    }

    func testToolCall_getWeather_routesToBridge() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let proxy = GeminiToolProxy(bridge: bridge)

        let result = await proxy.execute(
            functionName: "get_weather",
            arguments: ["location": "Nashville, TN"]
        )

        XCTAssertTrue(result.contains("Error") || result.contains("error"))
    }

    // MARK: - Confirmation Gate

    func testConfirmationGate_sendMessageRequiresConfirmation() {
        XCTAssertTrue(GeminiToolProxy.confirmationRequired.contains("send_message"),
                      "send_message should require confirmation")
    }

    func testConfirmationGate_searchWebDoesNotRequireConfirmation() {
        XCTAssertFalse(GeminiToolProxy.confirmationRequired.contains("search_web"))
    }

    func testConfirmationGate_runCommandRequiresConfirmation() {
        XCTAssertTrue(GeminiToolProxy.confirmationRequired.contains("run_command"))
    }

    // MARK: - Destructive Agent Actions

    func testDestructiveAction_rmCommand_isDestructive() {
        let action = AgentAction.runCommand("rm -rf /tmp/test", workdir: nil)
        XCTAssertTrue(action.isDestructive)
    }

    func testDestructiveAction_gitPush_isDestructive() {
        let action = AgentAction.runCommand("git push origin main", workdir: nil)
        XCTAssertTrue(action.isDestructive)
    }

    func testDestructiveAction_lsCommand_isNotDestructive() {
        let action = AgentAction.runCommand("ls -la", workdir: nil)
        XCTAssertFalse(action.isDestructive)
    }

    // MARK: - Tool Declaration Validity

    func testAllToolDeclarations_haveValidJsonSchema() throws {
        for decl in GeminiToolProxy.toolDeclarations {
            let name = decl["name"] as? String ?? "unknown"

            // Must be JSON-serializable
            XCTAssertNoThrow(
                try JSONSerialization.data(withJSONObject: decl),
                "Tool '\(name)' must be JSON-serializable"
            )

            // Must have required fields
            XCTAssertNotNil(decl["name"] as? String)
            XCTAssertNotNil(decl["description"] as? String)
            XCTAssertNotNil(decl["parameters"] as? [String: Any])
        }
    }

    // MARK: - Tool Execution with Unknown Function

    func testUnknownFunction_returnsError() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let proxy = GeminiToolProxy(bridge: bridge)

        let result = await proxy.execute(
            functionName: "nonexistent_tool",
            arguments: [:]
        )

        // Should either error or proxy to bridge (which will fail)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Model Router Integration

    func testModelRouter_flashForToolProcessing() {
        let router = GeminiModelRouter(preference: .auto)
        XCTAssertEqual(router.route(task: .toolResultProcessing), .flash)
    }

    func testModelRouter_proForAgentReasoning() {
        let router = GeminiModelRouter(preference: .auto)
        XCTAssertEqual(router.route(task: .agentReasoning), .pro)
    }

    func testModelRouter_flashOverride() {
        let router = GeminiModelRouter(preference: .flash)
        XCTAssertEqual(router.route(task: .agentReasoning), .flash)
        XCTAssertEqual(router.route(task: .codeAnalysis), .flash)
    }

    func testModelRouter_proOverride() {
        let router = GeminiModelRouter(preference: .pro)
        XCTAssertEqual(router.route(task: .simpleQA), .pro)
        XCTAssertEqual(router.route(task: .toolResultProcessing), .pro)
    }
}
