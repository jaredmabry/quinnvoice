import Foundation
import SwiftUI

/// The four states of the voice assistant lifecycle.
enum VoiceState: String, Sendable {
    case idle
    case listening
    case thinking
    case speaking
}

/// Central observable state for the entire app.
@Observable
@MainActor
final class AppState {
    var voiceState: VoiceState = .idle
    var isSessionActive: Bool = false
    var errorMessage: String?
    var showSettings: Bool = false
    var showTranscript: Bool = false

    /// Audio level from mic (0…1), drives waveform animation.
    var micLevel: Float = 0.0

    /// Audio level from playback (0…1), drives speaking animation.
    var outputLevel: Float = 0.0

    /// Transcript lines for the current session.
    var transcript: [TranscriptLine] = []

    /// Whether the global hotkey is currently active (held or toggled on).
    var hotkeyActive: Bool = false

    /// Whether the transcript panel is visible.
    var showTranscriptPanel: Bool = false

    /// Whether the wake word detector is actively listening.
    var isWakeWordListening: Bool = false

    /// Whether the camera is currently being shared with Gemini.
    var isSharingCamera: Bool = false

    /// Whether the screen is currently being shared with Gemini.
    var isSharingScreen: Bool = false

    // MARK: - Agent Mode State

    /// Whether Quinn is currently in autonomous agent/computer-use mode.
    var isAgentMode: Bool = false

    /// The current task the agent is working on.
    var agentTask: String?

    /// Current step number in the agent loop (1-based).
    var agentIteration: Int = 0

    /// Maximum steps the agent will take before stopping.
    var agentMaxIterations: Int = 20

    /// Full action log for the current agent session.
    var agentLog: [AgentLogEntry] = []

    /// Action currently awaiting user confirmation (destructive command, etc.).
    var agentPendingConfirmation: AgentAction?

    /// Human-readable status text for the current agent activity.
    var agentStatus: String?

    func transition(to newState: VoiceState) {
        voiceState = newState
    }

    func addTranscriptLine(_ line: TranscriptLine) {
        transcript.append(line)
    }

    func clearTranscript() {
        transcript.removeAll()
    }

    func setError(_ message: String) {
        errorMessage = message
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Agent Mode Methods

    /// Enter agent mode with a task.
    func startAgentMode(task: String, maxIterations: Int) {
        isAgentMode = true
        agentTask = task
        agentIteration = 0
        agentMaxIterations = maxIterations
        agentLog = []
        agentPendingConfirmation = nil
        agentStatus = "Starting…"
    }

    /// Exit agent mode and reset all agent state.
    func stopAgentMode() {
        isAgentMode = false
        agentTask = nil
        agentIteration = 0
        agentLog = []
        agentPendingConfirmation = nil
        agentStatus = nil
    }

    /// Add an entry to the agent action log.
    func appendAgentLog(_ entry: AgentLogEntry) {
        agentLog.append(entry)
    }
}

/// A single line in the conversation transcript.
struct TranscriptLine: Identifiable, Sendable {
    let id = UUID()
    let role: Role
    let text: String
    let timestamp: Date

    enum Role: String, Sendable {
        case user
        case assistant
        case system
    }

    init(role: Role, text: String) {
        self.role = role
        self.text = text
        self.timestamp = Date()
    }
}
