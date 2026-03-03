/// AppStateTests.swift — Comprehensive tests for AppState and related types.

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
        XCTAssertFalse(state.showSettings)
        XCTAssertFalse(state.showTranscript)
        XCTAssertFalse(state.hotkeyActive)
        XCTAssertFalse(state.showTranscriptPanel)
        XCTAssertFalse(state.isWakeWordListening)
        XCTAssertFalse(state.isSharingCamera)
        XCTAssertFalse(state.isSharingScreen)
    }

    // MARK: - Valid State Transitions

    func testTransition_idleToListening() {
        let state = AppState()
        state.transition(to: .listening)
        XCTAssertEqual(state.voiceState, .listening)
    }

    func testTransition_listeningToThinking() {
        let state = AppState()
        state.transition(to: .listening)
        state.transition(to: .thinking)
        XCTAssertEqual(state.voiceState, .thinking)
    }

    func testTransition_thinkingToSpeaking() {
        let state = AppState()
        state.transition(to: .thinking)
        state.transition(to: .speaking)
        XCTAssertEqual(state.voiceState, .speaking)
    }

    func testTransition_speakingToListening() {
        let state = AppState()
        state.transition(to: .speaking)
        state.transition(to: .listening)
        XCTAssertEqual(state.voiceState, .listening)
    }

    func testTransition_speakingToIdle() {
        let state = AppState()
        state.transition(to: .speaking)
        state.transition(to: .idle)
        XCTAssertEqual(state.voiceState, .idle)
    }

    func testTransition_fullCycle() {
        let state = AppState()
        state.transition(to: .listening)
        XCTAssertEqual(state.voiceState, .listening)
        state.transition(to: .thinking)
        XCTAssertEqual(state.voiceState, .thinking)
        state.transition(to: .speaking)
        XCTAssertEqual(state.voiceState, .speaking)
        state.transition(to: .listening)
        XCTAssertEqual(state.voiceState, .listening)
        state.transition(to: .idle)
        XCTAssertEqual(state.voiceState, .idle)
    }

    // MARK: - Invalid/Non-Standard Transitions (Don't Crash)

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

    func testTransition_idleToThinking_doesNotCrash() {
        let state = AppState()
        state.transition(to: .thinking)
        XCTAssertEqual(state.voiceState, .thinking)
    }

    func testTransition_listeningToSpeaking_doesNotCrash() {
        let state = AppState()
        state.transition(to: .listening)
        state.transition(to: .speaking)
        XCTAssertEqual(state.voiceState, .speaking)
    }

    // MARK: - Transcript Management

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

    func testTranscriptLine_identicalTextHasUniqueIds() {
        let a = TranscriptLine(role: .user, text: "Same")
        let b = TranscriptLine(role: .user, text: "Same")
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

    func testClearError_whenNoError_doesNotCrash() {
        let state = AppState()
        XCTAssertNil(state.errorMessage)
        state.clearError()
        XCTAssertNil(state.errorMessage)
    }

    // MARK: - Agent Mode State

    func testAgentMode_initialState() {
        let state = AppState()
        XCTAssertFalse(state.isAgentMode)
        XCTAssertNil(state.agentTask)
        XCTAssertEqual(state.agentIteration, 0)
        XCTAssertEqual(state.agentMaxIterations, 20)
        XCTAssertTrue(state.agentLog.isEmpty)
        XCTAssertNil(state.agentPendingConfirmation)
        XCTAssertNil(state.agentStatus)
    }

    func testStartAgentMode_setsState() {
        let state = AppState()
        state.startAgentMode(task: "Fix the build", maxIterations: 10)

        XCTAssertTrue(state.isAgentMode)
        XCTAssertEqual(state.agentTask, "Fix the build")
        XCTAssertEqual(state.agentIteration, 0)
        XCTAssertEqual(state.agentMaxIterations, 10)
        XCTAssertTrue(state.agentLog.isEmpty)
        XCTAssertNil(state.agentPendingConfirmation)
        XCTAssertEqual(state.agentStatus, "Starting…")
    }

    func testStopAgentMode_resetsState() {
        let state = AppState()
        state.startAgentMode(task: "Fix the build", maxIterations: 10)
        state.agentIteration = 5
        state.appendAgentLog(AgentLogEntry(action: .readScreen, observation: "test"))

        state.stopAgentMode()

        XCTAssertFalse(state.isAgentMode)
        XCTAssertNil(state.agentTask)
        XCTAssertEqual(state.agentIteration, 0)
        XCTAssertTrue(state.agentLog.isEmpty)
        XCTAssertNil(state.agentPendingConfirmation)
        XCTAssertNil(state.agentStatus)
    }

    func testAppendAgentLog_addsEntry() {
        let state = AppState()
        let entry = AgentLogEntry(action: .readScreen, observation: "Hello")
        state.appendAgentLog(entry)

        XCTAssertEqual(state.agentLog.count, 1)
        XCTAssertEqual(state.agentLog.first?.observation, "Hello")
    }

    func testAgentPendingConfirmation_canBeSet() {
        let state = AppState()
        let action = AgentAction.runCommand("rm -rf /tmp/test", workdir: nil)
        state.agentPendingConfirmation = action

        XCTAssertNotNil(state.agentPendingConfirmation)
        if case .runCommand(let cmd, _) = state.agentPendingConfirmation {
            XCTAssertEqual(cmd, "rm -rf /tmp/test")
        } else {
            XCTFail("Expected runCommand")
        }
    }

    // MARK: - Session Active Flag

    func testSessionActive_independentOfVoiceState() {
        let state = AppState()
        XCTAssertFalse(state.isSessionActive)

        state.isSessionActive = true
        state.transition(to: .listening)
        XCTAssertTrue(state.isSessionActive)

        state.transition(to: .idle)
        XCTAssertTrue(state.isSessionActive, "isSessionActive should not be affected by transitions")
    }

    // MARK: - Mic/Output Level Updates

    func testMicLevel_canBeUpdated() {
        let state = AppState()
        XCTAssertEqual(state.micLevel, 0.0)
        state.micLevel = 0.75
        XCTAssertEqual(state.micLevel, 0.75)
    }

    func testOutputLevel_canBeUpdated() {
        let state = AppState()
        XCTAssertEqual(state.outputLevel, 0.0)
        state.outputLevel = 0.5
        XCTAssertEqual(state.outputLevel, 0.5)
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
