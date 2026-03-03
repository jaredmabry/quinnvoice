/// AppStateTests.swift
/// Tests for the central observable state machine that drives QuinnVoice's UI and session lifecycle.
///
/// Covers valid and invalid state transitions, transcript management,
/// error handling, and continuous vs. non-continuous mode behavior.

import XCTest

@testable import QuinnVoice

@MainActor
final class AppStateTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState_isIdle() {
        let state = AppState()
        XCTAssertEqual(state.voiceState, .idle)
        XCTAssertFalse(state.isSessionActive)
        XCTAssertNil(state.errorMessage)
        XCTAssertTrue(state.transcript.isEmpty)
        XCTAssertEqual(state.micLevel, 0.0)
        XCTAssertEqual(state.outputLevel, 0.0)
    }

    // MARK: - Valid State Transitions

    /// Idle → Listening (user clicks mic / presses hotkey).
    func testTransition_idleToListening() {
        let state = AppState()
        state.transition(to: .listening)
        XCTAssertEqual(state.voiceState, .listening)
    }

    /// Listening → Thinking (speech detected and paused, waiting for Gemini).
    func testTransition_listeningToThinking() {
        let state = AppState()
        state.transition(to: .listening)
        state.transition(to: .thinking)
        XCTAssertEqual(state.voiceState, .thinking)
    }

    /// Thinking → Speaking (Gemini starts streaming audio response).
    func testTransition_thinkingToSpeaking() {
        let state = AppState()
        state.transition(to: .listening)
        state.transition(to: .thinking)
        state.transition(to: .speaking)
        XCTAssertEqual(state.voiceState, .speaking)
    }

    /// Speaking → Listening (turn complete in continuous mode).
    func testTransition_speakingToListening() {
        let state = AppState()
        state.transition(to: .speaking)
        state.transition(to: .listening)
        XCTAssertEqual(state.voiceState, .listening)
    }

    /// Speaking → Idle (turn complete in non-continuous mode or user stops).
    func testTransition_speakingToIdle() {
        let state = AppState()
        state.transition(to: .speaking)
        state.transition(to: .idle)
        XCTAssertEqual(state.voiceState, .idle)
    }

    /// Full happy-path cycle: idle → listening → thinking → speaking → listening → idle.
    func testTransition_fullCycle() {
        let state = AppState()

        state.transition(to: .listening)
        XCTAssertEqual(state.voiceState, .listening)

        state.transition(to: .thinking)
        XCTAssertEqual(state.voiceState, .thinking)

        state.transition(to: .speaking)
        XCTAssertEqual(state.voiceState, .speaking)

        // Continuous mode: back to listening
        state.transition(to: .listening)
        XCTAssertEqual(state.voiceState, .listening)

        // User stops
        state.transition(to: .idle)
        XCTAssertEqual(state.voiceState, .idle)
    }

    /// Barge-in: speaking → listening (user interrupts).
    func testTransition_bargeIn() {
        let state = AppState()
        state.transition(to: .speaking)
        state.transition(to: .listening)
        XCTAssertEqual(state.voiceState, .listening,
                       "Barge-in should transition from speaking back to listening")
    }

    // MARK: - Non-Standard Transitions (Handled Gracefully)

    /// The state machine uses a simple setter — any transition is accepted.
    /// This tests that unusual transitions don't crash.
    func testTransition_idleToSpeaking_doesNotCrash() {
        let state = AppState()
        state.transition(to: .speaking)
        XCTAssertEqual(state.voiceState, .speaking)
    }

    func testTransition_thinkingToIdle_doesNotCrash() {
        let state = AppState()
        state.transition(to: .thinking)
        state.transition(to: .idle)
        XCTAssertEqual(state.voiceState, .idle)
    }

    func testTransition_sameState_isNoOp() {
        let state = AppState()
        state.transition(to: .listening)
        state.transition(to: .listening)
        XCTAssertEqual(state.voiceState, .listening)
    }

    // MARK: - Transcript

    func testAddTranscriptLine_appendsToArray() {
        let state = AppState()
        let line = TranscriptLine(role: .user, text: "Hello Quinn")
        state.addTranscriptLine(line)
        XCTAssertEqual(state.transcript.count, 1)
        XCTAssertEqual(state.transcript.first?.text, "Hello Quinn")
        XCTAssertEqual(state.transcript.first?.role, .user)
    }

    func testAddMultipleTranscriptLines_preservesOrder() {
        let state = AppState()
        state.addTranscriptLine(TranscriptLine(role: .user, text: "What's the weather?"))
        state.addTranscriptLine(TranscriptLine(role: .assistant, text: "It's 72°F and sunny."))
        state.addTranscriptLine(TranscriptLine(role: .system, text: "Tool call: get_weather"))

        XCTAssertEqual(state.transcript.count, 3)
        XCTAssertEqual(state.transcript[0].role, .user)
        XCTAssertEqual(state.transcript[1].role, .assistant)
        XCTAssertEqual(state.transcript[2].role, .system)
    }

    func testClearTranscript_removesAll() {
        let state = AppState()
        state.addTranscriptLine(TranscriptLine(role: .user, text: "Hello"))
        state.addTranscriptLine(TranscriptLine(role: .assistant, text: "Hi"))
        XCTAssertEqual(state.transcript.count, 2)

        state.clearTranscript()
        XCTAssertTrue(state.transcript.isEmpty)
    }

    func testTranscriptLine_hasTimestamp() {
        let before = Date()
        let line = TranscriptLine(role: .assistant, text: "Test")
        let after = Date()

        XCTAssertGreaterThanOrEqual(line.timestamp, before)
        XCTAssertLessThanOrEqual(line.timestamp, after)
    }

    func testTranscriptLine_hasUniqueId() {
        let a = TranscriptLine(role: .user, text: "A")
        let b = TranscriptLine(role: .user, text: "B")
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: - Error Handling

    func testSetError_setsMessage() {
        let state = AppState()
        XCTAssertNil(state.errorMessage)
        state.setError("Connection lost")
        XCTAssertEqual(state.errorMessage, "Connection lost")
    }

    func testClearError_removesMessage() {
        let state = AppState()
        state.setError("Something broke")
        state.clearError()
        XCTAssertNil(state.errorMessage)
    }

    func testSetError_overwritesPrevious() {
        let state = AppState()
        state.setError("Error 1")
        state.setError("Error 2")
        XCTAssertEqual(state.errorMessage, "Error 2")
    }

    // MARK: - Continuous Mode Behavior

    /// In continuous mode, after speaking finishes, state should go back to listening.
    /// This simulates what SessionController does.
    func testContinuousMode_speakingReturnsToListening() {
        let state = AppState()
        let continuousMode = true

        state.transition(to: .speaking)

        // Simulate turn complete
        if continuousMode {
            state.transition(to: .listening)
        } else {
            state.transition(to: .idle)
        }

        XCTAssertEqual(state.voiceState, .listening)
    }

    /// In non-continuous mode, after speaking finishes, state should go to idle.
    func testNonContinuousMode_speakingReturnsToIdle() {
        let state = AppState()
        let continuousMode = false

        state.transition(to: .speaking)

        if continuousMode {
            state.transition(to: .listening)
        } else {
            state.transition(to: .idle)
        }

        XCTAssertEqual(state.voiceState, .idle)
    }

    // MARK: - Session Active Flag

    func testSessionActive_independentOfVoiceState() {
        let state = AppState()
        XCTAssertFalse(state.isSessionActive)

        state.isSessionActive = true
        state.transition(to: .listening)
        XCTAssertTrue(state.isSessionActive)

        state.transition(to: .idle)
        // isSessionActive is managed by SessionController, not by transition()
        XCTAssertTrue(state.isSessionActive)
    }

    // MARK: - VoiceState Enum

    func testVoiceState_rawValues() {
        XCTAssertEqual(VoiceState.idle.rawValue, "idle")
        XCTAssertEqual(VoiceState.listening.rawValue, "listening")
        XCTAssertEqual(VoiceState.thinking.rawValue, "thinking")
        XCTAssertEqual(VoiceState.speaking.rawValue, "speaking")
    }

    func testTranscriptLineRole_rawValues() {
        XCTAssertEqual(TranscriptLine.Role.user.rawValue, "user")
        XCTAssertEqual(TranscriptLine.Role.assistant.rawValue, "assistant")
        XCTAssertEqual(TranscriptLine.Role.system.rawValue, "system")
    }
}
