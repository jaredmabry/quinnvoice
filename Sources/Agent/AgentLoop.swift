import Foundation

/// Autonomous observe-think-act-observe reasoning loop for computer use.
///
/// The `AgentLoop` manages a complete autonomous task execution session:
/// 1. **Observe** — Read the current screen state
/// 2. **Think** — Send the observation to Gemini, which decides the next action
/// 3. **Act** — Execute the action via `ComputerController`
/// 4. **Observe** — Read the result and loop back
///
/// The loop continues until:
/// - Gemini returns a `task_complete` function call
/// - The maximum iteration limit is reached
/// - The user interrupts via stop/cancel
/// - An unrecoverable error occurs
///
/// Safety features:
/// - Configurable maximum iteration limit (default: 20)
/// - Automatic pause on any error
/// - User can interrupt at any point
/// - Destructive commands always require confirmation
/// - Full action log maintained for audit trail
actor AgentLoop {

    // MARK: - Properties

    private let task: String
    private let computerController: ComputerController
    private let toolProxy: GeminiToolProxy
    private let maxIterations: Int
    private let confirmDestructive: Bool

    /// Whether the loop is currently running.
    private var isRunning = false

    /// Whether the user has requested a stop.
    private var stopRequested = false

    /// Whether the loop is paused (e.g., waiting for confirmation).
    private var isPaused = false

    /// Current iteration number (1-based).
    private var currentIteration = 0

    /// Continuation for confirmation responses.
    private var confirmationContinuation: CheckedContinuation<Bool, Never>?

    /// Continuation for user question responses.
    private var userResponseContinuation: CheckedContinuation<String, Never>?

    /// Callback to update the main-thread app state.
    private let stateUpdater: @Sendable (AgentStateUpdate) -> Void

    // MARK: - State Update Messages

    /// Messages sent from the agent loop to update UI state on the main actor.
    enum AgentStateUpdate: Sendable {
        case started(task: String, maxIterations: Int)
        case iterationChanged(Int)
        case statusChanged(AgentStatus)
        case logEntry(AgentLogEntry)
        case pendingConfirmation(AgentAction)
        case confirmationCleared
        case completed(String)
        case error(String)
        case stopped
    }

    // MARK: - Init

    /// Create a new agent loop.
    ///
    /// - Parameters:
    ///   - task: The user's task description (e.g., "fix the build error in main.swift").
    ///   - computerController: The computer interaction engine.
    ///   - toolProxy: The Gemini tool proxy for executing OpenClaw tools.
    ///   - maxIterations: Maximum number of observe-act cycles before stopping (default: 20).
    ///   - confirmDestructive: Whether to pause for confirmation on destructive commands.
    ///   - stateUpdater: Callback to send state updates to the UI.
    init(
        task: String,
        computerController: ComputerController,
        toolProxy: GeminiToolProxy,
        maxIterations: Int = 20,
        confirmDestructive: Bool = true,
        stateUpdater: @escaping @Sendable (AgentStateUpdate) -> Void
    ) {
        self.task = task
        self.computerController = computerController
        self.toolProxy = toolProxy
        self.maxIterations = maxIterations
        self.confirmDestructive = confirmDestructive
        self.stateUpdater = stateUpdater
    }

    // MARK: - Control

    /// Start the autonomous agent loop.
    ///
    /// This is the main entry point. It runs the observe-think-act cycle
    /// until the task is complete, the iteration limit is reached, or the
    /// user interrupts.
    func start() async {
        guard !isRunning else { return }

        isRunning = true
        stopRequested = false
        isPaused = false
        currentIteration = 0

        stateUpdater(.started(task: task, maxIterations: maxIterations))

        // Main agent loop
        while isRunning && !stopRequested && currentIteration < maxIterations {
            currentIteration += 1
            stateUpdater(.iterationChanged(currentIteration))

            do {
                // OBSERVE
                stateUpdater(.statusChanged(.observing))
                let observation = try await observe()

                // Check for stop after observe
                guard !stopRequested else { break }

                // THINK — send observation to Gemini via tool proxy
                stateUpdater(.statusChanged(.thinking))
                let action = try await think(observation: observation)

                // Check for stop after think
                guard !stopRequested else { break }

                // Handle task completion
                if case .taskComplete(let summary) = action {
                    let entry = AgentLogEntry(action: action, observation: nil, success: true)
                    stateUpdater(.logEntry(entry))
                    stateUpdater(.completed(summary))
                    isRunning = false
                    return
                }

                // SAFETY CHECK — destructive command confirmation
                if confirmDestructive && action.isDestructive {
                    stateUpdater(.statusChanged(.awaitingConfirmation(action)))
                    stateUpdater(.pendingConfirmation(action))

                    let allowed = await waitForConfirmation()
                    stateUpdater(.confirmationCleared)

                    if !allowed {
                        let entry = AgentLogEntry(
                            action: action,
                            observation: "User denied — action skipped",
                            success: false
                        )
                        stateUpdater(.logEntry(entry))
                        continue
                    }
                }

                // Handle user questions
                if case .askUser(let question) = action {
                    stateUpdater(.statusChanged(.awaitingUserResponse(question)))
                    let response = await waitForUserResponse()
                    let entry = AgentLogEntry(
                        action: action,
                        observation: "User responded: \(response)",
                        success: true
                    )
                    stateUpdater(.logEntry(entry))
                    continue
                }

                // ACT
                stateUpdater(.statusChanged(.acting(action)))
                let result = try await act(action)

                let entry = AgentLogEntry(action: action, observation: result, success: true)
                stateUpdater(.logEntry(entry))

            } catch {
                let errorEntry = AgentLogEntry(
                    action: .readScreen,
                    observation: "Error: \(error.localizedDescription)",
                    success: false
                )
                stateUpdater(.logEntry(errorEntry))
                stateUpdater(.error(error.localizedDescription))

                // Pause on error — don't continue blindly
                isPaused = true
                stateUpdater(.statusChanged(.error(error.localizedDescription)))

                // Wait for user to resume or stop
                let shouldContinue = await waitForConfirmation()
                isPaused = false

                if !shouldContinue {
                    break
                }
            }
        }

        // Loop ended
        if currentIteration >= maxIterations && isRunning {
            stateUpdater(.completed("Reached maximum iterations (\(maxIterations))"))
        }

        isRunning = false
        stateUpdater(.stopped)
    }

    /// Request the agent loop to stop.
    func stop() {
        stopRequested = true
        isPaused = false

        // Resume any waiting continuations
        confirmationContinuation?.resume(returning: false)
        confirmationContinuation = nil

        userResponseContinuation?.resume(returning: "")
        userResponseContinuation = nil
    }

    /// Respond to a pending confirmation request.
    ///
    /// - Parameter allowed: `true` to allow the action, `false` to deny it.
    func respondToConfirmation(allowed: Bool) {
        confirmationContinuation?.resume(returning: allowed)
        confirmationContinuation = nil
    }

    /// Respond to a user question.
    ///
    /// - Parameter response: The user's text response.
    func respondToQuestion(response: String) {
        userResponseContinuation?.resume(returning: response)
        userResponseContinuation = nil
    }

    /// Whether the agent loop is currently running.
    var running: Bool { isRunning }

    // MARK: - Core Loop Phases

    /// Observe the current screen state.
    private func observe() async throws -> String {
        return try await computerController.readScreenContent()
    }

    /// Think about the next action by analyzing the observation.
    ///
    /// Constructs a prompt with the task context and current observation,
    /// then parses the response into an `AgentAction`.
    private func think(observation: String) async throws -> AgentAction {
        // Build the agent prompt
        let prompt = buildAgentPrompt(observation: observation)

        // Execute through tool proxy as a run_command that calls the OpenClaw gateway
        // The Gemini session will process this as a function call and return the action
        let result = await toolProxy.execute(
            functionName: "agent_think",
            arguments: [
                "task": task,
                "observation": observation,
                "iteration": "\(currentIteration)",
                "max_iterations": "\(maxIterations)",
                "prompt": prompt
            ]
        )

        // Parse the result into an AgentAction
        return parseAction(from: result)
    }

    /// Execute an action via the computer controller.
    private func act(_ action: AgentAction) async throws -> String {
        switch action {
        case .typeText(let text):
            try await computerController.typeText(text)
            return "Typed \(text.count) characters"

        case .pressKeys(let modifiers, let key):
            try await computerController.pressKeys(modifiers: modifiers, key: key)
            return "Pressed \((modifiers + [key]).joined(separator: "+"))"

        case .click(let x, let y, let button, let clicks):
            try await computerController.click(x: x, y: y, button: button, clicks: clicks)
            return "Clicked at (\(Int(x)), \(Int(y)))"

        case .scroll(let direction, let amount):
            try await computerController.scroll(direction: direction, amount: amount)
            return "Scrolled \(direction) \(amount) units"

        case .readScreen:
            return try await computerController.readScreenContent()

        case .runCommand(let command, let workdir):
            return try await computerController.runCommand(command, workdir: workdir)

        case .focusApp(let appName):
            try await computerController.focusApp(appName)
            return "Focused \(appName)"

        case .takeScreenshot:
            let data = try await computerController.takeScreenshot()
            return "Screenshot captured (\(data.count) bytes)"

        case .taskComplete(let summary):
            return summary

        case .askConfirmation, .askUser:
            return "Waiting for user"
        }
    }

    // MARK: - Prompt Building

    /// Build the agent reasoning prompt with task context and current observation.
    private func buildAgentPrompt(observation: String) -> String {
        """
        You are Quinn, an autonomous computer-use agent. You are controlling the user's Mac to complete a task.

        TASK: \(task)
        ITERATION: \(currentIteration)/\(maxIterations)

        CURRENT SCREEN STATE:
        \(observation)

        Choose ONE action to take next. Respond with a single function call:
        - type_text(text) — Type text into the focused application
        - press_keys(modifiers, key) — Press a key combo (e.g., ["command"], "s")
        - click_at(x, y, button, clicks) — Click at coordinates
        - scroll(direction, amount) — Scroll up/down
        - read_screen() — Read the current screen content again
        - run_command(command, workdir) — Run a shell command
        - focus_app(app_name) — Bring an app to the foreground
        - take_screenshot() — Capture a screenshot
        - task_complete(summary) — Signal the task is done
        - ask_user(question) — Ask the user a question

        Think step by step about what action will make progress toward the task.
        If the task appears complete, call task_complete.
        """
    }

    /// Parse a tool result string into an `AgentAction`.
    private func parseAction(from result: String) -> AgentAction {
        // Try to parse as JSON function call response
        if let data = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            if let functionName = json["function"] as? String {
                let args = json["arguments"] as? [String: Any] ?? [:]
                return actionFromFunctionCall(name: functionName, arguments: args)
            }
        }

        // Fallback: if we can't parse, treat as a read_screen to re-observe
        return .readScreen
    }

    /// Convert a parsed function call into an `AgentAction`.
    private func actionFromFunctionCall(name: String, arguments: [String: Any]) -> AgentAction {
        switch name {
        case "type_text":
            let text = arguments["text"] as? String ?? ""
            return .typeText(text)

        case "press_keys":
            let modifiers = arguments["modifiers"] as? [String] ?? []
            let key = arguments["key"] as? String ?? "return"
            return .pressKeys(modifiers: modifiers, key: key)

        case "click_at":
            let x = (arguments["x"] as? Double) ?? 0
            let y = (arguments["y"] as? Double) ?? 0
            let button = arguments["button"] as? String ?? "left"
            let clicks = (arguments["clicks"] as? Int) ?? 1
            return .click(x: x, y: y, button: button, clicks: clicks)

        case "scroll":
            let direction = arguments["direction"] as? String ?? "down"
            let amount = (arguments["amount"] as? Int) ?? 3
            return .scroll(direction: direction, amount: amount)

        case "read_screen":
            return .readScreen

        case "run_command":
            let command = arguments["command"] as? String ?? ""
            let workdir = arguments["workdir"] as? String
            return .runCommand(command, workdir: workdir)

        case "focus_app":
            let appName = arguments["app_name"] as? String ?? ""
            return .focusApp(appName)

        case "take_screenshot":
            return .takeScreenshot

        case "task_complete":
            let summary = arguments["summary"] as? String ?? "Task completed"
            return .taskComplete(summary: summary)

        case "ask_user":
            let question = arguments["question"] as? String ?? ""
            return .askUser(question: question)

        default:
            return .readScreen
        }
    }

    // MARK: - Waiting Helpers

    /// Wait for the user to confirm or deny an action.
    private func waitForConfirmation() async -> Bool {
        await withCheckedContinuation { continuation in
            confirmationContinuation = continuation
        }
    }

    /// Wait for the user to respond to a question.
    private func waitForUserResponse() async -> String {
        await withCheckedContinuation { continuation in
            userResponseContinuation = continuation
        }
    }
}
