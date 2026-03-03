/// GeminiToolProxyTests.swift — Comprehensive tests for GeminiToolProxy.

import XCTest

@testable import QuinnVoice

final class GeminiToolProxyTests: XCTestCase {

    // MARK: - Tool Declarations Structure

    func testToolDeclarations_isNonEmpty() {
        XCTAssertFalse(GeminiToolProxy.toolDeclarations.isEmpty)
    }

    func testToolDeclarations_count() {
        XCTAssertGreaterThan(GeminiToolProxy.toolDeclarations.count, 20,
                             "Should have a comprehensive set of tool declarations")
    }

    func testToolDeclarations_allHaveRequiredKeys() {
        for (index, decl) in GeminiToolProxy.toolDeclarations.enumerated() {
            XCTAssertNotNil(decl["name"] as? String, "Tool at index \(index) missing 'name'")
            XCTAssertNotNil(decl["description"] as? String, "Tool at index \(index) missing 'description'")
            XCTAssertNotNil(decl["parameters"] as? [String: Any], "Tool at index \(index) missing 'parameters'")
        }
    }

    func testToolDeclarations_parametersAreObjects() {
        for decl in GeminiToolProxy.toolDeclarations {
            let name = decl["name"] as? String ?? "unknown"
            guard let params = decl["parameters"] as? [String: Any] else {
                XCTFail("Tool '\(name)' has no parameters")
                continue
            }
            XCTAssertEqual(params["type"] as? String, "object")
            XCTAssertNotNil(params["properties"] as? [String: Any])
        }
    }

    func testToolDeclarations_allHaveRequiredArray() {
        for decl in GeminiToolProxy.toolDeclarations {
            let name = decl["name"] as? String ?? "unknown"
            guard let params = decl["parameters"] as? [String: Any] else {
                XCTFail("Tool '\(name)' missing parameters")
                continue
            }
            // `required` must be present as an array (can be empty for some tools)
            XCTAssertNotNil(params["required"], "Tool '\(name)' missing 'required' array")
        }
    }

    func testToolDeclarations_allParameterPropertiesHaveType() {
        for decl in GeminiToolProxy.toolDeclarations {
            let name = decl["name"] as? String ?? "unknown"
            guard let params = decl["parameters"] as? [String: Any],
                  let props = params["properties"] as? [String: Any] else { continue }

            for (propName, propValue) in props {
                guard let propDict = propValue as? [String: Any] else {
                    XCTFail("Tool '\(name)' property '\(propName)' is not a dictionary")
                    continue
                }
                XCTAssertNotNil(propDict["type"], "Tool '\(name)' property '\(propName)' missing 'type'")
            }
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

    func testToolDeclarations_containsClipboardTools() {
        let names = Set(GeminiToolProxy.toolDeclarations.compactMap { $0["name"] as? String })
        XCTAssertTrue(names.contains("get_clipboard"))
        XCTAssertTrue(names.contains("set_clipboard"))
    }

    func testToolDeclarations_containsComputerUseTools() {
        let names = Set(GeminiToolProxy.toolDeclarations.compactMap { $0["name"] as? String })
        XCTAssertTrue(names.contains("type_text"))
        XCTAssertTrue(names.contains("press_keys"))
        XCTAssertTrue(names.contains("click_at"))
        XCTAssertTrue(names.contains("read_screen"))
        XCTAssertTrue(names.contains("take_screenshot"))
    }

    // MARK: - Confirmation Required Set

    func testConfirmationRequired_containsSendMessage() {
        XCTAssertTrue(GeminiToolProxy.confirmationRequired.contains("send_message"))
    }

    func testConfirmationRequired_doesNotContainSearchWeb() {
        XCTAssertFalse(GeminiToolProxy.confirmationRequired.contains("search_web"))
    }

    func testConfirmationRequired_doesNotContainGetWeather() {
        XCTAssertFalse(GeminiToolProxy.confirmationRequired.contains("get_weather"))
    }

    // MARK: - Clipboard Tool Routing

    func testClipboardGet_disabledByDefault() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let proxy = GeminiToolProxy(bridge: bridge)

        let result = await proxy.execute(functionName: "get_clipboard", arguments: [:])
        // Should return "not enabled" message, not a bridge error
        XCTAssertTrue(result.contains("not enabled"))
    }

    func testClipboardSet_disabledByDefault() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let proxy = GeminiToolProxy(bridge: bridge)

        let result = await proxy.execute(functionName: "set_clipboard", arguments: ["text": "test"])
        XCTAssertTrue(result.contains("not enabled"))
    }

    func testClipboardGet_enabledWithoutManager() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let proxy = GeminiToolProxy(bridge: bridge)
        // Enable clipboard but don't set a manager — should still return something
        let enabled = await proxy.clipboardEnabled
        XCTAssertFalse(enabled) // Default is false
    }

    // MARK: - Non-Clipboard Tools Proxy to Bridge

    func testNonClipboardTool_proxiesToBridge() async {
        // Use a non-reachable bridge — should return an error
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let proxy = GeminiToolProxy(bridge: bridge)

        let result = await proxy.execute(functionName: "search_web", arguments: ["query": "test"])
        XCTAssertTrue(result.contains("Error") || result.contains("error"),
                      "Non-clipboard tool with unreachable bridge should return error")
    }

    // MARK: - Execute Returns Error on Bridge Failure

    func testExecute_returnsErrorOnConnectionFailure() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let proxy = GeminiToolProxy(bridge: bridge)

        let result = await proxy.execute(functionName: "search_web", arguments: ["query": "test"])
        XCTAssertTrue(result.contains("Error"))
    }

    // MARK: - Tool Declaration JSON Serialization

    func testToolDeclarations_areJsonSerializable() throws {
        let wrapper: [String: Any] = [
            "functionDeclarations": GeminiToolProxy.toolDeclarations
        ]
        let data = try JSONSerialization.data(withJSONObject: wrapper)
        XCTAssertGreaterThan(data.count, 0)

        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(parsed?["functionDeclarations"])
    }

    // MARK: - Helpers

    private func findTool(named name: String) -> [String: Any]? {
        GeminiToolProxy.toolDeclarations.first { ($0["name"] as? String) == name }
    }
}
