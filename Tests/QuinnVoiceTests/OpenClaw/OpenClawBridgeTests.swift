/// OpenClawBridgeTests.swift — Tests for OpenClawBridge URL construction and error handling.

import XCTest

@testable import QuinnVoice

final class OpenClawBridgeTests: XCTestCase {

    // MARK: - URL Construction

    func testDefaultBaseURL() async {
        let bridge = OpenClawBridge()
        let url = await bridge.baseURL
        XCTAssertEqual(url.absoluteString, "http://127.0.0.1:18789")
    }

    func testCustomBaseURL() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://192.168.1.100:18789")!)
        let url = await bridge.baseURL
        XCTAssertEqual(url.absoluteString, "http://192.168.1.100:18789")
    }

    // MARK: - File Read URL

    func testFetchFileContent_failsWithUnreachableServer() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)

        do {
            _ = try await bridge.fetchFileContent(path: "/test/file.md")
            XCTFail("Should have thrown for unreachable server")
        } catch {
            // Expected — connection refused
            XCTAssertTrue(true)
        }
    }

    // MARK: - Tool Execution URL

    func testExecuteTool_failsWithUnreachableServer() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)

        do {
            _ = try await bridge.executeTool(name: "search_web", arguments: ["query": "test"])
            XCTFail("Should have thrown for unreachable server")
        } catch {
            XCTAssertTrue(true)
        }
    }

    // MARK: - Health Check

    func testHealthCheck_unreachableServer_returnsFalse() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let healthy = await bridge.healthCheck()
        XCTAssertFalse(healthy)
    }

    // MARK: - OpenClawError

    func testOpenClawError_requestFailed_hasDescription() {
        let error = OpenClawError.requestFailed(statusCode: 404)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("404"))
    }

    func testOpenClawError_invalidResponse_hasDescription() {
        let error = OpenClawError.invalidResponse
        XCTAssertNotNil(error.errorDescription)
    }
}
