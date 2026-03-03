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
