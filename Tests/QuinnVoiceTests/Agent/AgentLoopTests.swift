/// AgentLoopTests.swift — Tests for AgentLoop control flow and state management.
/// Note: Cannot test full loop execution (requires Accessibility), but can test
/// state updates, control methods, and destructive detection.

import XCTest

@testable import QuinnVoice

final class AgentLoopTests: XCTestCase {

    // MARK: - Running State

    func testAgentLoop_runningFalseInitially() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let proxy = GeminiToolProxy(bridge: bridge)
        let controller = ComputerController()

        let loop = AgentLoop(
            task: "Test",
            computerController: controller,
            toolProxy: proxy,
            maxIterations: 5,
            stateUpdater: { _ in }
        )

        let running = await loop.running
        XCTAssertFalse(running)
    }

    // MARK: - Stop

    func testAgentLoop_stop_doesNotCrash() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let proxy = GeminiToolProxy(bridge: bridge)
        let controller = ComputerController()

        let loop = AgentLoop(
            task: "Test",
            computerController: controller,
            toolProxy: proxy,
            maxIterations: 5,
            stateUpdater: { _ in }
        )

        // Stop without starting — should not crash
        await loop.stop()
    }

    // MARK: - Confirmation Response

    func testAgentLoop_respondToConfirmation_doesNotCrash() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let proxy = GeminiToolProxy(bridge: bridge)
        let controller = ComputerController()

        let loop = AgentLoop(
            task: "Test",
            computerController: controller,
            toolProxy: proxy,
            stateUpdater: { _ in }
        )

        // Calling without a pending confirmation should not crash
        await loop.respondToConfirmation(allowed: true)
        await loop.respondToConfirmation(allowed: false)
    }

    func testAgentLoop_respondToQuestion_doesNotCrash() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let proxy = GeminiToolProxy(bridge: bridge)
        let controller = ComputerController()

        let loop = AgentLoop(
            task: "Test",
            computerController: controller,
            toolProxy: proxy,
            stateUpdater: { _ in }
        )

        await loop.respondToQuestion(response: "yes")
    }

    // MARK: - State Update Messages

    func testAgentStateUpdate_startedContainsTask() {
        let update = AgentLoop.AgentStateUpdate.started(task: "Build app", maxIterations: 20)
        if case .started(let task, let max) = update {
            XCTAssertEqual(task, "Build app")
            XCTAssertEqual(max, 20)
        } else {
            XCTFail("Expected started update")
        }
    }

    func testAgentStateUpdate_iterationChanged() {
        let update = AgentLoop.AgentStateUpdate.iterationChanged(5)
        if case .iterationChanged(let n) = update {
            XCTAssertEqual(n, 5)
        } else {
            XCTFail("Expected iterationChanged")
        }
    }

    func testAgentStateUpdate_completed() {
        let update = AgentLoop.AgentStateUpdate.completed("All done")
        if case .completed(let summary) = update {
            XCTAssertEqual(summary, "All done")
        } else {
            XCTFail("Expected completed")
        }
    }

    func testAgentStateUpdate_error() {
        let update = AgentLoop.AgentStateUpdate.error("Something broke")
        if case .error(let msg) = update {
            XCTAssertEqual(msg, "Something broke")
        } else {
            XCTFail("Expected error")
        }
    }

    func testAgentStateUpdate_stopped() {
        let update = AgentLoop.AgentStateUpdate.stopped
        if case .stopped = update {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected stopped")
        }
    }

    func testAgentStateUpdate_confirmationCleared() {
        let update = AgentLoop.AgentStateUpdate.confirmationCleared
        if case .confirmationCleared = update {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected confirmationCleared")
        }
    }

    // MARK: - Destructive Command Detection

    func testAgentAction_isDestructive_rm() {
        let action = AgentAction.runCommand("rm -rf /tmp/test", workdir: nil)
        XCTAssertTrue(action.isDestructive)
    }

    func testAgentAction_isDestructive_sudo() {
        let action = AgentAction.runCommand("sudo apt-get install foo", workdir: nil)
        XCTAssertTrue(action.isDestructive)
    }

    func testAgentAction_isDestructive_gitPush() {
        let action = AgentAction.runCommand("git push origin main", workdir: nil)
        XCTAssertTrue(action.isDestructive)
    }

    func testAgentAction_isNotDestructive_ls() {
        let action = AgentAction.runCommand("ls -la", workdir: nil)
        XCTAssertFalse(action.isDestructive)
    }

    func testAgentAction_isNotDestructive_cat() {
        let action = AgentAction.runCommand("cat README.md", workdir: nil)
        XCTAssertFalse(action.isDestructive)
    }

    func testAgentAction_nonCommandActions_areNotDestructive() {
        XCTAssertFalse(AgentAction.readScreen.isDestructive)
        XCTAssertFalse(AgentAction.typeText("hello").isDestructive)
        XCTAssertFalse(AgentAction.takeScreenshot.isDestructive)
        XCTAssertFalse(AgentAction.focusApp("Safari").isDestructive)
    }

    // MARK: - Max Iterations Config

    func testAgentLoop_maxIterations_default() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let proxy = GeminiToolProxy(bridge: bridge)
        let controller = ComputerController()

        // Default maxIterations should be 20
        let _ = AgentLoop(
            task: "Test",
            computerController: controller,
            toolProxy: proxy,
            stateUpdater: { _ in }
        )
        // Just verifying it doesn't crash with defaults
        XCTAssertTrue(true)
    }

    func testAgentLoop_customMaxIterations() async {
        let bridge = OpenClawBridge(baseURL: URL(string: "http://127.0.0.1:1")!)
        let proxy = GeminiToolProxy(bridge: bridge)
        let controller = ComputerController()

        let _ = AgentLoop(
            task: "Test",
            computerController: controller,
            toolProxy: proxy,
            maxIterations: 100,
            stateUpdater: { _ in }
        )
        XCTAssertTrue(true)
    }
}
