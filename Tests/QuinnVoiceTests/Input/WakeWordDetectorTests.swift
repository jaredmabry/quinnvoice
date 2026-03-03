/// WakeWordDetectorTests.swift — Tests for WakeWordDetector state management.
/// Note: Actual speech recognition cannot be tested in unit tests,
/// so we only test state and configuration.

import XCTest

@testable import QuinnVoice

@MainActor
final class WakeWordDetectorTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState_notListening() {
        let detector = WakeWordDetector()
        XCTAssertFalse(detector.isListening)
    }

    func testInitialState_defaultWakePhrase() {
        let detector = WakeWordDetector()
        XCTAssertEqual(detector.wakePhrase, "Hey Quinn")
    }

    // MARK: - State Transitions

    func testStop_transitionsToNotListening() {
        let detector = WakeWordDetector()
        detector.stop()
        XCTAssertFalse(detector.isListening)
    }

    func testStop_idempotent() {
        let detector = WakeWordDetector()
        detector.stop()
        detector.stop()
        XCTAssertFalse(detector.isListening)
    }

    // MARK: - Configuration

    func testWakePhrase_canBeChanged() {
        let detector = WakeWordDetector()
        detector.wakePhrase = "Hey Computer"
        XCTAssertEqual(detector.wakePhrase, "Hey Computer")
    }

    func testWakePhrase_canBeEmpty() {
        let detector = WakeWordDetector()
        detector.wakePhrase = ""
        XCTAssertEqual(detector.wakePhrase, "")
    }

    func testCallback_canBeSet() {
        let detector = WakeWordDetector()
        var called = false
        detector.onWakeWordDetected = { called = true }
        XCTAssertFalse(called)
    }

    func testCallback_canBeSetToNil() {
        let detector = WakeWordDetector()
        detector.onWakeWordDetected = { }
        detector.onWakeWordDetected = nil
        // Should not crash
    }
}
