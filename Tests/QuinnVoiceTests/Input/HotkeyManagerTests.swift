/// HotkeyManagerTests.swift — Tests for HotkeyManager state and mode transitions.
/// Note: Global event monitors cannot be tested directly in unit tests,
/// but we can test the state management and mode logic.

import XCTest

@testable import QuinnVoice

@MainActor
final class HotkeyManagerTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState_isNotActive() {
        let manager = HotkeyManager()
        XCTAssertFalse(manager.isActive)
    }

    func testInitialState_defaultModeIsHold() {
        let manager = HotkeyManager()
        XCTAssertEqual(manager.mode, .hold)
    }

    // MARK: - Mode Setting

    func testSetMode_toggle() {
        let manager = HotkeyManager()
        manager.mode = .toggle
        XCTAssertEqual(manager.mode, .toggle)
    }

    func testSetMode_hold() {
        let manager = HotkeyManager()
        manager.mode = .toggle
        manager.mode = .hold
        XCTAssertEqual(manager.mode, .hold)
    }

    // MARK: - HotkeyMode Enum

    func testHotkeyMode_rawValues() {
        XCTAssertEqual(HotkeyMode.hold.rawValue, "hold")
        XCTAssertEqual(HotkeyMode.toggle.rawValue, "toggle")
    }

    func testHotkeyMode_allCases() {
        XCTAssertEqual(HotkeyMode.allCases.count, 2)
        XCTAssertTrue(HotkeyMode.allCases.contains(.hold))
        XCTAssertTrue(HotkeyMode.allCases.contains(.toggle))
    }

    func testHotkeyMode_codableRoundTrip() throws {
        for mode in HotkeyMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(HotkeyMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    // MARK: - Callback Setup

    func testCallbacks_canBeSet() {
        let manager = HotkeyManager()
        var activateCalled = false
        var deactivateCalled = false

        manager.onActivate = { activateCalled = true }
        manager.onDeactivate = { deactivateCalled = true }

        // Just verify we can set them without crash
        XCTAssertFalse(activateCalled)
        XCTAssertFalse(deactivateCalled)
    }

    // MARK: - Start/Stop

    func testStart_doesNotCrash() {
        let manager = HotkeyManager()
        manager.start()
        // Clean up
        manager.stop()
    }

    func testStop_doesNotCrash() {
        let manager = HotkeyManager()
        manager.stop() // Stop without starting
    }

    func testStartStop_cycle() {
        let manager = HotkeyManager()
        manager.start()
        manager.stop()
        manager.start()
        manager.stop()
    }

    func testStop_deactivatesIfActive() {
        let manager = HotkeyManager()
        // We can't easily activate without a real event, but we can verify
        // stop doesn't crash regardless of state
        manager.start()
        manager.stop()
        XCTAssertFalse(manager.isActive)
    }

    // MARK: - Accessibility Check

    func testCheckAccessibilityPermissions_doesNotCrash() {
        // Don't prompt in tests
        _ = HotkeyManager.checkAccessibilityPermissions(prompt: false)
    }
}
