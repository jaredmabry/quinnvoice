import Foundation

// MARK: - Agent Action

/// Represents a discrete action the agent can take during autonomous computer use.
///
/// Each case maps to a specific computer interaction capability exposed
/// through Gemini function calls. All cases are `Sendable` for safe
/// cross-actor communication.
enum AgentAction: Sendable, Equatable {
    /// Type text into the currently focused application.
    case typeText(String)

    /// Press a key combination (e.g., ⌘S, Return, ⌘Z).
    /// - Parameters:
    ///   - modifiers: Modifier key names: "command", "option", "shift", "control".
    ///   - key: The key to press (e.g., "s", "z", "return", "tab", "escape").
    case pressKeys(modifiers: [String], key: String)

    /// Click at screen coordinates.
    /// - Parameters:
    ///   - x: Horizontal coordinate.
    ///   - y: Vertical coordinate.
    ///   - button: "left", "right", or "middle".
    ///   - clicks: Number of clicks (1 = single, 2 = double).
    case click(x: Double, y: Double, button: String, clicks: Int)

    /// Scroll in the focused window.
    /// - Parameters:
    ///   - direction: "up" or "down".
    ///   - amount: Number of scroll units.
    case scroll(direction: String, amount: Int)

    /// Read the text content of the focused window.
    case readScreen

    /// Execute a shell command.
    /// - Parameters:
    ///   - command: The shell command string.
    ///   - workdir: Optional working directory.
    case runCommand(String, workdir: String?)

    /// Bring an application to the foreground.
    case focusApp(String)

    /// Capture a screenshot of the focused window.
    case takeScreenshot

    /// Signal that the autonomous task is complete.
    case taskComplete(summary: String)

    /// Ask the user for confirmation before proceeding with a potentially destructive action.
    case askConfirmation(action: String, reason: String)

    /// Ask the user a question mid-task and wait for a response.
    case askUser(question: String)

    /// A human-readable description of this action.
    var displayDescription: String {
        switch self {
        case .typeText(let text):
            let preview = text.count > 40 ? String(text.prefix(40)) + "…" : text
            return "Type: \"\(preview)\""
        case .pressKeys(let modifiers, let key):
            let combo = (modifiers + [key]).joined(separator: "+")
            return "Press: \(combo)"
        case .click(let x, let y, let button, let clicks):
            let clickType = clicks > 1 ? "Double-click" : "Click"
            return "\(clickType) (\(button)) at (\(Int(x)), \(Int(y)))"
        case .scroll(let direction, let amount):
            return "Scroll \(direction) ×\(amount)"
        case .readScreen:
            return "Read screen content"
        case .runCommand(let cmd, _):
            let preview = cmd.count > 50 ? String(cmd.prefix(50)) + "…" : cmd
            return "Run: \(preview)"
        case .focusApp(let app):
            return "Focus: \(app)"
        case .takeScreenshot:
            return "Take screenshot"
        case .taskComplete(let summary):
            return "✅ Complete: \(summary)"
        case .askConfirmation(let action, _):
            return "⚠️ Confirm: \(action)"
        case .askUser(let question):
            return "❓ Ask: \(question)"
        }
    }

    /// Whether this action is potentially destructive and should require confirmation.
    var isDestructive: Bool {
        switch self {
        case .runCommand(let cmd, _):
            return Self.destructivePatterns.contains { cmd.contains($0) }
        default:
            return false
        }
    }

    /// Shell command patterns considered destructive.
    private static let destructivePatterns = [
        "rm ", "rm\t", "rmdir", "git push", "git reset --hard",
        "sudo ", "chmod ", "chown ", "mkfs", "dd ", "kill ",
        "killall ", "shutdown", "reboot", "mv /", "format",
        "> /dev/", "curl | sh", "curl | bash", "wget | sh"
    ]
}

// MARK: - Agent Log Entry

/// A single entry in the agent's action log, recording what was done and the result.
struct AgentLogEntry: Sendable, Identifiable {
    /// Unique identifier for this log entry.
    let id: UUID

    /// When this action was executed.
    let timestamp: Date

    /// The action that was taken.
    let action: AgentAction

    /// The observation or result text after the action completed.
    let observation: String?

    /// Whether the action succeeded.
    let success: Bool

    init(action: AgentAction, observation: String? = nil, success: Bool = true) {
        self.id = UUID()
        self.timestamp = Date()
        self.action = action
        self.observation = observation
        self.success = success
    }
}

// MARK: - Agent Status

/// The current status of the agent loop.
enum AgentStatus: Sendable, Equatable {
    /// Agent is not running.
    case inactive

    /// Agent is observing the screen state.
    case observing

    /// Agent is waiting for Gemini to decide the next action.
    case thinking

    /// Agent is executing an action.
    case acting(AgentAction)

    /// Agent is paused, waiting for user confirmation.
    case awaitingConfirmation(AgentAction)

    /// Agent is paused, waiting for user response to a question.
    case awaitingUserResponse(String)

    /// Agent has completed its task.
    case completed(String)

    /// Agent encountered an error and paused.
    case error(String)

    /// Human-readable status text.
    var displayText: String {
        switch self {
        case .inactive: return "Inactive"
        case .observing: return "Observing screen…"
        case .thinking: return "Thinking…"
        case .acting(let action): return action.displayDescription
        case .awaitingConfirmation(let action): return "Awaiting confirmation: \(action.displayDescription)"
        case .awaitingUserResponse(let q): return "Waiting for answer: \(q)"
        case .completed(let summary): return "Done: \(summary)"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
