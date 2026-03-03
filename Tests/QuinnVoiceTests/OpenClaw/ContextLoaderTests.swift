/// ContextLoaderTests.swift — Tests for ContextLoader system instruction building.

import XCTest

@testable import QuinnVoice

final class ContextLoaderTests: XCTestCase {

    // MARK: - System Instruction Building

    func testLoadSystemInstructions_containsCoreIdentity() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let loader = ContextLoader(bridge: bridge, workspacePath: "/nonexistent")

        let instructions = await loader.loadSystemInstructions()
        XCTAssertTrue(instructions.contains("Quinn"))
        XCTAssertTrue(instructions.contains("personal voice assistant"))
    }

    func testLoadSystemInstructions_containsVoiceGuidelines() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let loader = ContextLoader(bridge: bridge, workspacePath: "/nonexistent")

        let instructions = await loader.loadSystemInstructions()
        XCTAssertTrue(instructions.contains("Voice Interaction Guidelines"))
        XCTAssertTrue(instructions.contains("concise"))
    }

    // MARK: - Missing Files (Graceful Degradation)

    func testLoadSystemInstructions_missingFiles_doesNotCrash() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let loader = ContextLoader(bridge: bridge, workspacePath: "/totally/nonexistent/path")

        let instructions = await loader.loadSystemInstructions()
        // Should still produce valid instructions with at least the core identity
        XCTAssertFalse(instructions.isEmpty)
        XCTAssertTrue(instructions.contains("Quinn"))
    }

    // MARK: - Screen Context Inclusion

    func testLoadSystemInstructions_withScreenContext() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let loader = ContextLoader(bridge: bridge, workspacePath: "/nonexistent")

        let instructions = await loader.loadSystemInstructions(
            screenContext: "User is viewing: Xcode - main.swift"
        )

        XCTAssertTrue(instructions.contains("Current Screen Context"))
        XCTAssertTrue(instructions.contains("Xcode - main.swift"))
    }

    func testLoadSystemInstructions_emptyScreenContext_notIncluded() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let loader = ContextLoader(bridge: bridge, workspacePath: "/nonexistent")

        let instructions = await loader.loadSystemInstructions(screenContext: "")
        XCTAssertFalse(instructions.contains("Current Screen Context"))
    }

    func testLoadSystemInstructions_nilScreenContext_notIncluded() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let loader = ContextLoader(bridge: bridge, workspacePath: "/nonexistent")

        let instructions = await loader.loadSystemInstructions(screenContext: nil)
        XCTAssertFalse(instructions.contains("Current Screen Context"))
    }

    // MARK: - Instruction Concatenation

    func testLoadSystemInstructions_sectionsAreSeparated() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let loader = ContextLoader(bridge: bridge, workspacePath: "/nonexistent")

        let instructions = await loader.loadSystemInstructions()
        // Sections should be separated by double newlines
        XCTAssertTrue(instructions.contains("\n\n"))
    }

    // MARK: - Context Summarization Properties

    func testContextSummarizationEnabled_defaultTrue() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let loader = ContextLoader(bridge: bridge)

        let enabled = await loader.contextSummarizationEnabled
        XCTAssertTrue(enabled)
    }

    func testGeminiClient_defaultNil() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let loader = ContextLoader(bridge: bridge)

        let client = await loader.geminiClient
        XCTAssertNil(client)
    }
}
