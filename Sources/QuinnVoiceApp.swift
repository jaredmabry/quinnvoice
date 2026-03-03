import SwiftUI

@main
struct QuinnVoiceApp: App {
    @State private var appState = AppState()
    @State private var configManager = ConfigManager()
    @State private var sessionController: SessionController?
    @State private var hotkeyManager = HotkeyManager()
    @State private var wakeWordDetector = WakeWordDetector()
    @State private var notificationManager = NotificationManager()
    @State private var clipboardManager = ClipboardManager()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("QuinnVoice", systemImage: menuBarIcon) {
            if configManager.config.isConfigured {
                VoicePanelView(
                    appState: appState,
                    onToggleSession: { startSession() },
                    onStopSession: { stopSession() },
                    onOpenSettings: { openSettings() },
                    onToggleCamera: { toggleCamera() },
                    onToggleScreen: { toggleScreen() }
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Welcome to QuinnVoice")
                        .font(.headline)
                    Text("Add your Gemini API key to get started.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Open Settings") {
                        openSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
                .frame(width: 280)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(configManager: configManager)
        }
    }

    private var menuBarIcon: String {
        if appState.isWakeWordListening && appState.voiceState == .idle {
            return "ear.fill"
        }
        switch appState.voiceState {
        case .idle: return "waveform.circle"
        case .listening: return "waveform.circle.fill"
        case .thinking: return "ellipsis.circle.fill"
        case .speaking: return "speaker.wave.2.circle.fill"
        }
    }

    @MainActor
    private func openSettings() {
        appState.showSettings = true
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func startSession() {
        guard configManager.config.isConfigured else {
            openSettings()
            return
        }
        let controller = SessionController(
            appState: appState,
            config: configManager.config,
            clipboardManager: clipboardManager,
            notificationManager: notificationManager
        )
        self.sessionController = controller

        Task {
            await controller.start()
        }
    }

    private func stopSession() {
        Task {
            await sessionController?.stop()
            sessionController = nil
        }
    }

    private func toggleCamera() {
        Task {
            await sessionController?.toggleCamera()
        }
    }

    private func toggleScreen() {
        Task {
            await sessionController?.toggleScreen()
        }
    }

    // MARK: - Lifecycle Setup

    /// Called to set up global services (hotkey, wake word, notifications, clipboard).
    private func setupServices() {
        // Set up hotkey manager
        if configManager.config.hotkeyEnabled {
            hotkeyManager.mode = configManager.config.hotkeyMode

            hotkeyManager.onActivate = { [self] in
                appState.hotkeyActive = true
                if appState.voiceState == .idle {
                    startSession()
                }
            }

            hotkeyManager.onDeactivate = { [self] in
                appState.hotkeyActive = false
                if configManager.config.hotkeyMode == .hold && appState.isSessionActive {
                    stopSession()
                }
            }

            hotkeyManager.start()
        }

        // Set up wake word detector
        if configManager.config.wakeWordEnabled {
            wakeWordDetector.wakePhrase = configManager.config.wakePhrase
            wakeWordDetector.onWakeWordDetected = { [self] in
                if appState.voiceState == .idle {
                    startSession()
                }
            }

            Task {
                do {
                    try await wakeWordDetector.start()
                    appState.isWakeWordListening = true
                } catch {
                    print("[QuinnVoiceApp] Wake word detector failed to start: \(error)")
                }
            }
        }

        // Set up notifications
        if configManager.config.notificationsEnabled {
            Task {
                await notificationManager.requestPermission()
            }
        }

        // Set up clipboard monitoring
        if configManager.config.clipboardAccess {
            clipboardManager.startMonitoring()
        }
    }
}

// MARK: - Session Controller

/// Coordinates the audio engine, Gemini session, OpenClaw bridge, and multi-modal providers
/// for a single voice session.
///
/// Manages the lifecycle of audio capture, Gemini Live WebSocket connection,
/// screen context capture, clipboard tools, notification relay, and camera/screen sharing.
@MainActor
final class SessionController {
    private let appState: AppState
    private let config: AppConfig

    private let audioManager = AudioManager()
    private var geminiSession: GeminiLiveSession?
    private let toolProxy: GeminiToolProxy
    private let contextLoader: ContextLoader
    private let screenContextProvider = ScreenContextProvider()
    private let multiModalProvider = MultiModalProvider()
    private let clipboardManager: ClipboardManager?
    private let notificationManager: NotificationManager?

    // MARK: - Agent / Computer Use
    private let computerController = ComputerController()
    private var agentLoop: AgentLoop?
    private let agentOverlayController = AgentOverlayWindowController()

    init(appState: AppState, config: AppConfig, clipboardManager: ClipboardManager? = nil, notificationManager: NotificationManager? = nil) {
        self.appState = appState
        self.config = config
        self.clipboardManager = clipboardManager
        self.notificationManager = notificationManager

        let bridge = OpenClawBridge(baseURL: URL(string: config.openclawUrl)!)
        self.toolProxy = GeminiToolProxy(bridge: bridge)
        self.contextLoader = ContextLoader(bridge: bridge, includeScreenContext: config.includeScreenContext)
    }

    func start() async {
        appState.clearError()
        appState.clearTranscript()
        appState.transition(to: .listening)
        appState.isSessionActive = true

        // Configure tool proxy with clipboard, notification, and computer-use managers
        await toolProxy.configure(
            clipboardManager: clipboardManager,
            notificationManager: notificationManager,
            clipboardEnabled: config.clipboardAccess,
            notificationsEnabled: config.notificationsEnabled
        )

        // Configure computer use if enabled
        if config.agentModeEnabled {
            await toolProxy.configureComputerUse(
                controller: computerController,
                enabled: true
            )
            await computerController.setAllowedApps(config.agentAllowedApps)
        }

        // Capture screen context if enabled
        var screenContext: String? = nil
        if config.includeScreenContext {
            if let context = screenContextProvider.captureContext() {
                screenContext = context.description
            }
        }

        // Load system instructions from OpenClaw (with screen context)
        let systemInstructions = await contextLoader.loadSystemInstructions(screenContext: screenContext)

        // Create Gemini Live session
        let session = GeminiLiveSession(
            apiKey: config.geminiApiKey,
            model: config.geminiModel
        )
        self.geminiSession = session

        // Set up event handling
        await session.setHandler({ [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleGeminiEvent(event)
            }
        })

        // Set up audio capture → Gemini streaming
        audioManager.onMicData = { [weak session] data in
            Task {
                try? await session?.sendAudio(data)
            }
        }

        audioManager.onMicLevel = { [weak self] level in
            self?.appState.micLevel = level
        }

        // Set up multi-modal frame sending
        multiModalProvider.onFrameCaptured = { [weak session] frame in
            Task {
                try? await session?.sendImage(frame.imageData, mimeType: frame.mimeType)
            }
        }

        // Connect to Gemini
        do {
            try await session.connect(
                systemInstruction: systemInstructions,
                voiceConfig: config.voiceConfig
            )
        } catch {
            appState.setError("Connection failed: \(error.localizedDescription)")
            appState.transition(to: .idle)
            appState.isSessionActive = false
            return
        }

        // Start mic capture
        do {
            try audioManager.startCapture()
        } catch {
            appState.setError("Microphone error: \(error.localizedDescription)")
            await session.disconnect()
            appState.transition(to: .idle)
            appState.isSessionActive = false
        }
    }

    func stop() async {
        audioManager.stopPlayback()
        audioManager.stopCapture()
        audioManager.teardown()
        await geminiSession?.disconnect()
        geminiSession = nil

        // Stop multi-modal captures
        multiModalProvider.stopCamera()
        await multiModalProvider.stopScreenCapture()
        appState.isSharingCamera = false
        appState.isSharingScreen = false

        appState.transition(to: .idle)
        appState.isSessionActive = false
    }

    // MARK: - Multi-Modal Controls

    /// Toggle camera sharing on/off during an active session.
    func toggleCamera() async {
        if multiModalProvider.isCameraActive {
            multiModalProvider.stopCamera()
            appState.isSharingCamera = false
        } else {
            do {
                try multiModalProvider.startCamera()
                appState.isSharingCamera = true
            } catch {
                appState.setError("Camera error: \(error.localizedDescription)")
            }
        }
    }

    /// Toggle screen sharing on/off during an active session.
    func toggleScreen() async {
        if multiModalProvider.isScreenActive {
            await multiModalProvider.stopScreenCapture()
            appState.isSharingScreen = false
        } else {
            do {
                try await multiModalProvider.startScreenCapture()
                appState.isSharingScreen = true
            } catch {
                appState.setError("Screen capture error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Gemini Event Handling

    private func handleGeminiEvent(_ event: GeminiLiveSession.Event) {
        switch event {
        case .setupComplete:
            appState.transition(to: .listening)

        case .audioData(let data):
            appState.transition(to: .speaking)
            audioManager.playAudioData(data)

        case .text(let text):
            appState.addTranscriptLine(TranscriptLine(role: .assistant, text: text))

        case .turnComplete:
            if config.continuousMode {
                appState.transition(to: .listening)
            } else {
                Task { await stop() }
            }

        case .interrupted:
            // Barge-in: stop playback and go back to listening
            audioManager.stopPlayback()
            appState.transition(to: .listening)

        case .functionCall(let name, let id, let args):
            appState.transition(to: .thinking)
            handleFunctionCall(name: name, id: id, arguments: args)

        case .error(let message):
            appState.setError(message)

        case .disconnected:
            if appState.isSessionActive {
                appState.setError("Disconnected from Gemini")
                Task { await stop() }
            }
        }
    }

    private func handleFunctionCall(name: String, id: String, arguments: [String: String]) {
        Task {
            // Handle task_complete — ends agent mode
            if name == "task_complete" {
                let summary = arguments["summary"] ?? "Task completed"
                await stopAgentMode()
                try? await geminiSession?.sendFunctionResponse(callId: id, name: name, response: "Task complete: \(summary)")
                return
            }

            let result = await toolProxy.execute(functionName: name, arguments: arguments)
            try? await geminiSession?.sendFunctionResponse(callId: id, name: name, response: result)
        }
    }

    // MARK: - Agent Mode

    /// Start the autonomous agent loop for a given task.
    func startAgentMode(task: String) async {
        guard config.agentModeEnabled else { return }

        appState.startAgentMode(task: task, maxIterations: config.agentMaxIterations)

        let loop = AgentLoop(
            task: task,
            computerController: computerController,
            toolProxy: toolProxy,
            maxIterations: config.agentMaxIterations,
            confirmDestructive: config.agentConfirmDestructive,
            stateUpdater: { [weak self] update in
                Task { @MainActor [weak self] in
                    self?.handleAgentStateUpdate(update)
                }
            }
        )
        self.agentLoop = loop

        // Show overlay
        agentOverlayController.show(
            appState: appState,
            onStop: { [weak self] in
                Task { await self?.stopAgentMode() }
            },
            onConfirm: { [weak self] allowed in
                Task {
                    await self?.agentLoop?.respondToConfirmation(allowed: allowed)
                }
            }
        )

        // Start the loop
        Task {
            await loop.start()
        }
    }

    /// Stop the agent loop and clean up.
    func stopAgentMode() async {
        await agentLoop?.stop()
        agentLoop = nil
        appState.stopAgentMode()
        agentOverlayController.hide()
    }

    /// Handle state updates from the agent loop.
    private func handleAgentStateUpdate(_ update: AgentLoop.AgentStateUpdate) {
        switch update {
        case .started(let task, let maxIter):
            appState.agentTask = task
            appState.agentMaxIterations = maxIter

        case .iterationChanged(let iteration):
            appState.agentIteration = iteration

        case .statusChanged(let status):
            appState.agentStatus = status.displayText

        case .logEntry(let entry):
            appState.appendAgentLog(entry)

        case .pendingConfirmation(let action):
            appState.agentPendingConfirmation = action

        case .confirmationCleared:
            appState.agentPendingConfirmation = nil

        case .completed(let summary):
            appState.agentStatus = "✅ \(summary)"
            Task { await stopAgentMode() }

        case .error(let message):
            appState.agentStatus = "❌ \(message)"

        case .stopped:
            if appState.isAgentMode {
                Task { await stopAgentMode() }
            }
        }
    }
}

// MARK: - Helper to set event handler on actor

extension GeminiLiveSession {
    func setHandler(_ handler: @escaping @Sendable (Event) -> Void) {
        self.eventHandler = handler
    }
}

// MARK: - Helper to configure tool proxy on actor

extension GeminiToolProxy {
    /// Configure the tool proxy with clipboard and notification managers.
    func configure(
        clipboardManager: ClipboardManager?,
        notificationManager: NotificationManager?,
        clipboardEnabled: Bool,
        notificationsEnabled: Bool
    ) {
        self.clipboardManager = clipboardManager
        self.notificationManager = notificationManager
        self.clipboardEnabled = clipboardEnabled
        self.notificationsEnabled = notificationsEnabled
    }

    /// Configure the tool proxy for computer use / agent mode.
    func configureComputerUse(controller: ComputerController, enabled: Bool) {
        self.computerController = controller
        self.computerUseEnabled = enabled
    }
}
