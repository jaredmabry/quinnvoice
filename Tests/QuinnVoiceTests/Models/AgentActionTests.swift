/// AgentActionTests.swift — Tests for AgentAction enum, AgentLogEntry, and AgentStatus.

import XCTest

@testable import QuinnVoice

final class AgentActionTests: XCTestCase {

    // MARK: - All AgentAction Cases

    func testTypeText_displayDescription() {
        let action = AgentAction.typeText("Hello world")
        XCTAssertTrue(action.displayDescription.contains("Type:"))
        XCTAssertTrue(action.displayDescription.contains("Hello world"))
    }

    func testTypeText_longText_isTruncated() {
        let longText = String(repeating: "A", count: 60)
        let action = AgentAction.typeText(longText)
        XCTAssertTrue(action.displayDescription.contains("…"))
    }

    func testPressKeys_displayDescription() {
        let action = AgentAction.pressKeys(modifiers: ["command"], key: "s")
        XCTAssertTrue(action.displayDescription.contains("Press:"))
        XCTAssertTrue(action.displayDescription.contains("command+s"))
    }

    func testPressKeys_noModifiers() {
        let action = AgentAction.pressKeys(modifiers: [], key: "return")
        XCTAssertTrue(action.displayDescription.contains("return"))
    }

    func testClick_singleClick_displayDescription() {
        let action = AgentAction.click(x: 100.0, y: 200.0, button: "left", clicks: 1)
        XCTAssertTrue(action.displayDescription.contains("Click"))
        XCTAssertTrue(action.displayDescription.contains("100"))
        XCTAssertTrue(action.displayDescription.contains("200"))
    }

    func testClick_doubleClick_displayDescription() {
        let action = AgentAction.click(x: 50.0, y: 75.0, button: "left", clicks: 2)
        XCTAssertTrue(action.displayDescription.contains("Double-click"))
    }

    func testScroll_displayDescription() {
        let action = AgentAction.scroll(direction: "down", amount: 3)
        XCTAssertTrue(action.displayDescription.contains("Scroll"))
        XCTAssertTrue(action.displayDescription.contains("down"))
    }

    func testReadScreen_displayDescription() {
        XCTAssertTrue(AgentAction.readScreen.displayDescription.contains("Read screen"))
    }

    func testRunCommand_displayDescription() {
        let action = AgentAction.runCommand("ls -la", workdir: nil)
        XCTAssertTrue(action.displayDescription.contains("Run:"))
        XCTAssertTrue(action.displayDescription.contains("ls -la"))
    }

    func testRunCommand_longCommand_isTruncated() {
        let longCmd = String(repeating: "x", count: 80)
        let action = AgentAction.runCommand(longCmd, workdir: nil)
        XCTAssertTrue(action.displayDescription.contains("…"))
    }

    func testFocusApp_displayDescription() {
        let action = AgentAction.focusApp("Safari")
        XCTAssertTrue(action.displayDescription.contains("Focus:"))
        XCTAssertTrue(action.displayDescription.contains("Safari"))
    }

    func testTakeScreenshot_displayDescription() {
        XCTAssertTrue(AgentAction.takeScreenshot.displayDescription.contains("screenshot"))
    }

    func testTaskComplete_displayDescription() {
        let action = AgentAction.taskComplete(summary: "All done")
        XCTAssertTrue(action.displayDescription.contains("Complete"))
        XCTAssertTrue(action.displayDescription.contains("All done"))
    }

    func testAskConfirmation_displayDescription() {
        let action = AgentAction.askConfirmation(action: "delete files", reason: "might lose data")
        XCTAssertTrue(action.displayDescription.contains("Confirm"))
    }

    func testAskUser_displayDescription() {
        let action = AgentAction.askUser(question: "Which file?")
        XCTAssertTrue(action.displayDescription.contains("Ask"))
        XCTAssertTrue(action.displayDescription.contains("Which file?"))
    }

    // MARK: - Destructive Detection

    func testIsDestructive_rmCommand() {
        let action = AgentAction.runCommand("rm -rf /tmp/test", workdir: nil)
        XCTAssertTrue(action.isDestructive)
    }

    func testIsDestructive_sudoCommand() {
        let action = AgentAction.runCommand("sudo reboot", workdir: nil)
        XCTAssertTrue(action.isDestructive)
    }

    func testIsDestructive_gitPushCommand() {
        let action = AgentAction.runCommand("git push origin main", workdir: nil)
        XCTAssertTrue(action.isDestructive)
    }

    func testIsDestructive_killCommand() {
        let action = AgentAction.runCommand("kill -9 1234", workdir: nil)
        XCTAssertTrue(action.isDestructive)
    }

    func testIsDestructive_safeCommand() {
        let action = AgentAction.runCommand("ls -la", workdir: nil)
        XCTAssertFalse(action.isDestructive)
    }

    func testIsDestructive_nonCommandAction() {
        XCTAssertFalse(AgentAction.readScreen.isDestructive)
        XCTAssertFalse(AgentAction.typeText("hello").isDestructive)
        XCTAssertFalse(AgentAction.click(x: 0, y: 0, button: "left", clicks: 1).isDestructive)
        XCTAssertFalse(AgentAction.takeScreenshot.isDestructive)
    }

    // MARK: - Equatable

    func testEquatable_sameAction() {
        let a = AgentAction.typeText("hello")
        let b = AgentAction.typeText("hello")
        XCTAssertEqual(a, b)
    }

    func testEquatable_differentAction() {
        let a = AgentAction.typeText("hello")
        let b = AgentAction.typeText("world")
        XCTAssertNotEqual(a, b)
    }

    func testEquatable_differentCases() {
        let a = AgentAction.readScreen
        let b = AgentAction.takeScreenshot
        XCTAssertNotEqual(a, b)
    }

    // MARK: - AgentLogEntry

    func testLogEntry_creation() {
        let action = AgentAction.readScreen
        let entry = AgentLogEntry(action: action, observation: "Screen content", success: true)

        XCTAssertEqual(entry.action, .readScreen)
        XCTAssertEqual(entry.observation, "Screen content")
        XCTAssertTrue(entry.success)
    }

    func testLogEntry_hasTimestamp() {
        let before = Date()
        let entry = AgentLogEntry(action: .readScreen)
        let after = Date()

        XCTAssertGreaterThanOrEqual(entry.timestamp, before)
        XCTAssertLessThanOrEqual(entry.timestamp, after)
    }

    func testLogEntry_identifiable_uniqueIds() {
        let a = AgentLogEntry(action: .readScreen)
        let b = AgentLogEntry(action: .readScreen)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testLogEntry_defaultSuccess() {
        let entry = AgentLogEntry(action: .readScreen)
        XCTAssertTrue(entry.success)
    }

    func testLogEntry_failedEntry() {
        let entry = AgentLogEntry(action: .readScreen, observation: "Error", success: false)
        XCTAssertFalse(entry.success)
    }

    func testLogEntry_nilObservation() {
        let entry = AgentLogEntry(action: .takeScreenshot)
        XCTAssertNil(entry.observation)
    }

    // MARK: - AgentStatus

    func testAgentStatus_displayText_inactive() {
        XCTAssertEqual(AgentStatus.inactive.displayText, "Inactive")
    }

    func testAgentStatus_displayText_observing() {
        XCTAssertTrue(AgentStatus.observing.displayText.contains("Observing"))
    }

    func testAgentStatus_displayText_thinking() {
        XCTAssertTrue(AgentStatus.thinking.displayText.contains("Thinking"))
    }

    func testAgentStatus_displayText_acting() {
        let status = AgentStatus.acting(.readScreen)
        XCTAssertTrue(status.displayText.contains("Read screen"))
    }

    func testAgentStatus_displayText_completed() {
        let status = AgentStatus.completed("All done")
        XCTAssertTrue(status.displayText.contains("Done"))
        XCTAssertTrue(status.displayText.contains("All done"))
    }

    func testAgentStatus_displayText_error() {
        let status = AgentStatus.error("Something failed")
        XCTAssertTrue(status.displayText.contains("Error"))
    }

    func testAgentStatus_equatable() {
        XCTAssertEqual(AgentStatus.inactive, AgentStatus.inactive)
        XCTAssertEqual(AgentStatus.observing, AgentStatus.observing)
        XCTAssertEqual(AgentStatus.thinking, AgentStatus.thinking)
        XCTAssertNotEqual(AgentStatus.inactive, AgentStatus.observing)
    }
}
