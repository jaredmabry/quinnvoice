import SwiftUI
import UniformTypeIdentifiers

/// Configuration UI for QuinnVoice settings, organized as a tabbed settings window.
struct SettingsView: View {
    @Bindable var configManager: ConfigManager
    var memoryManager: MemoryManager
    var soulManager: SoulManager
    var profileManager: ProfileManager?
    var updateManager: UpdateManager?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general, voice, hotkey, personality, memory, profiles, appearance, audio, agent, advanced, updates

        var id: String { rawValue }

        var label: String {
            switch self {
            case .general: return "General"
            case .voice: return "Voice"
            case .hotkey: return "Hotkey"
            case .personality: return "Personality"
            case .memory: return "Memory"
            case .profiles: return "Profiles"
            case .appearance: return "Appearance"
            case .audio: return "Audio"
            case .agent: return "Agent"
            case .advanced: return "Advanced"
            case .updates: return "Updates"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gear"
            case .voice: return "waveform"
            case .hotkey: return "keyboard"
            case .personality: return "person.fill"
            case .memory: return "brain.head.profile"
            case .profiles: return "person.2.fill"
            case .appearance: return "paintbrush.fill"
            case .audio: return "mic.fill"
            case .agent: return "cpu"
            case .advanced: return "wrench.and.screwdriver"
            case .updates: return "arrow.triangle.2.circlepath"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.label, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            ScrollView {
                detailView
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 700, height: 550)
        .onDisappear {
            configManager.save()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .general:
            GeneralTab(configManager: configManager)
        case .voice:
            VoiceTab(configManager: configManager)
        case .hotkey:
            HotkeyTab(configManager: configManager)
        case .personality:
            PersonalityTab(configManager: configManager, soulManager: soulManager)
        case .memory:
            MemoryTab(memoryManager: memoryManager)
        case .profiles:
            if let profileManager {
                ProfileSettingsView(profileManager: profileManager, configManager: configManager)
            } else {
                Text("Profiles unavailable")
                    .foregroundStyle(.secondary)
            }
        case .appearance:
            AppearanceSettingsView(configManager: configManager)
        case .audio:
            AudioSettingsView(configManager: configManager)
        case .agent:
            AgentTab(configManager: configManager)
        case .advanced:
            AdvancedTab(configManager: configManager)
        case .updates:
            if let updateManager {
                UpdateSettingsView(updateManager: updateManager, configManager: configManager)
            } else {
                Text("Updates unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @Bindable var configManager: ConfigManager

    var body: some View {
        Form {
            Section("Gemini API") {
                SecureField("API Key", text: $configManager.config.geminiApiKey)
                    .textFieldStyle(.roundedBorder)

                Picker("Model", selection: $configManager.config.geminiModel) {
                    Text("Gemini Live 2.5 Flash (Native Audio)")
                        .tag("gemini-live-2.5-flash-native-audio")
                    Text("Gemini Live 2.0 Flash")
                        .tag("gemini-2.0-flash-live-001")
                }
            }

            Section("Behavior") {
                Toggle("Continuous Mode", isOn: $configManager.config.continuousMode)
                Toggle("Show Transcript", isOn: $configManager.config.showTranscript)
            }

            Section {
                Picker("Model Preference", selection: $configManager.config.preferredModel) {
                    ForEach(ModelPreference.allCases, id: \.self) { pref in
                        Text(pref.displayName).tag(pref)
                    }
                }

                Toggle("Context Caching", isOn: $configManager.config.contextCachingEnabled)
            } header: {
                Text("AI Model Routing")
            } footer: {
                Text("Auto routes simple tasks to Flash (cheaper) and complex tasks to Pro (smarter). Context caching reduces cost for repeated system prompts.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Voice Tab

struct VoiceTab: View {
    @Bindable var configManager: ConfigManager
    @State private var previewManager = VoicePreviewManager()

    var body: some View {
        Form {
            Section("Voice Selection") {
                ForEach(VoiceConfig.availableVoices, id: \.self) { voice in
                    HStack {
                        Image(systemName: configManager.config.voiceConfig.name == voice ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(configManager.config.voiceConfig.name == voice ? Color.accentColor : .secondary)
                            .font(.title3)

                        Text(voice)
                            .font(.body)

                        Spacer()

                        if previewManager.previewingVoice == voice && previewManager.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button {
                                previewManager.previewVoice(
                                    name: voice,
                                    apiKey: configManager.config.geminiApiKey
                                )
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .disabled(configManager.config.geminiApiKey.isEmpty)
                            .help("Preview this voice")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        configManager.config.voiceConfig.name = voice
                    }
                    .padding(.vertical, 2)
                }

                if let error = previewManager.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Enable Wake Word", isOn: $configManager.config.wakeWordEnabled)

                if configManager.config.wakeWordEnabled {
                    TextField("Wake Phrase", text: $configManager.config.wakePhrase)
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text("Wake Word")
            } footer: {
                Text("Always-on listening for your wake phrase using on-device speech recognition. Activates Quinn hands-free.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hotkey Tab

struct HotkeyTab: View {
    @Bindable var configManager: ConfigManager
    @State private var accessibilityGranted = false

    var body: some View {
        Form {
            Section("Global Hotkey") {
                Toggle("Enable Global Hotkey", isOn: $configManager.config.hotkeyEnabled)

                if configManager.config.hotkeyEnabled {
                    HStack {
                        Text("Current Hotkey")
                        Spacer()
                        HotkeyRecorderView(
                            keyCode: $configManager.config.hotkeyKeyCode,
                            modifiers: $configManager.config.hotkeyModifiers
                        )
                    }

                    Picker("Hotkey Mode", selection: $configManager.config.hotkeyMode) {
                        Text("Hold to Talk").tag(HotkeyMode.hold)
                        Text("Toggle (press to start/stop)").tag(HotkeyMode.toggle)
                    }
                    .pickerStyle(.segmented)

                    // Accessibility permission status
                    HStack {
                        Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(accessibilityGranted ? .green : .orange)
                        Text(accessibilityGranted ? "Accessibility granted" : "Accessibility required")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !accessibilityGranted {
                            Button("Request") {
                                _ = HotkeyManager.checkAccessibilityPermissions(prompt: true)
                                checkPermissions()
                            }
                            .font(.caption)
                        }
                    }
                }
            }

            Section {
                Text("The hotkey activates Quinn from anywhere on your Mac. In **Hold** mode, hold the key to talk and release to stop. In **Toggle** mode, press once to start and again to stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { checkPermissions() }
    }

    private func checkPermissions() {
        accessibilityGranted = HotkeyManager.checkAccessibilityPermissions(prompt: false)
    }
}

// MARK: - Hotkey Recorder View

/// A button that captures a key combination when clicked.
struct HotkeyRecorderView: View {
    @Binding var keyCode: UInt16
    @Binding var modifiers: UInt
    @State private var isRecording = false

    var body: some View {
        Button {
            isRecording = true
        } label: {
            if isRecording {
                Text("Press a key combination…")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    )
            } else {
                Text(HotkeyManager.formatHotkey(keyCode: keyCode, modifiers: modifiers))
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .buttonStyle(.plain)
        .background(
            HotkeyRecorderRepresentable(
                isRecording: $isRecording,
                keyCode: $keyCode,
                modifiers: $modifiers
            )
            .frame(width: 0, height: 0)
        )
    }
}

/// NSView-based key event capture for the hotkey recorder.
struct HotkeyRecorderRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: UInt16
    @Binding var modifiers: UInt

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.onKeyCaptured = { code, mods in
            self.keyCode = code
            self.modifiers = mods
            self.isRecording = false
        }
        view.onCancel = {
            self.isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        if isRecording {
            nsView.startRecording()
        } else {
            nsView.stopRecording()
        }
    }
}

/// NSView that captures key events for hotkey recording.
final class HotkeyRecorderNSView: NSView {
    var onKeyCaptured: ((UInt16, UInt) -> Void)?
    var onCancel: (() -> Void)?

    private var localMonitor: Any?
    private var isRecordingActive = false

    override var acceptsFirstResponder: Bool { true }

    func startRecording() {
        guard !isRecordingActive else { return }
        isRecordingActive = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecordingActive else { return event }

            // Escape cancels recording
            if event.keyCode == 53 {
                self.onCancel?()
                self.stopRecording()
                return nil
            }

            // Only accept key combos that include at least one modifier
            let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            let mods = event.modifierFlags.intersection(relevantModifiers)
            guard !mods.isEmpty else { return event }

            self.onKeyCaptured?(event.keyCode, mods.rawValue)
            self.stopRecording()
            return nil
        }
    }

    func stopRecording() {
        isRecordingActive = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}

// MARK: - Personality Tab

struct PersonalityTab: View {
    @Bindable var configManager: ConfigManager
    var soulManager: SoulManager
    @State private var showFileImporter = false

    var body: some View {
        Form {
            Section {
                Picker("When OpenClaw is available", selection: $configManager.config.contextPriority) {
                    ForEach(ContextPriority.allCases, id: \.self) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
                Text(configManager.config.contextPriority.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Context Priority")
            }

            Section("Soul Source") {
                Picker("Mode", selection: $configManager.config.soulSource) {
                    Text("Write Custom").tag(SoulSource.custom)
                    Text("Upload File").tag(SoulSource.file)
                }
                .pickerStyle(.segmented)
            }

            if configManager.config.soulSource == .file {
                Section("Imported File") {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        if configManager.config.soulFileName.isEmpty {
                            Text("No file imported")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(configManager.config.soulFileName)
                                .font(.body)
                        }
                        Spacer()
                        Button("Choose File…") {
                            showFileImporter = true
                        }
                    }

                    if !configManager.config.soulText.isEmpty {
                        Text("Preview:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(configManager.config.soulText.prefix(500)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                    }
                }
            } else {
                Section {
                    TextEditor(text: $configManager.config.soulText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 280)
                        .scrollContentBackground(.hidden)
                        .onChange(of: configManager.config.soulText) { _, newValue in
                            soulManager.soulText = newValue; soulManager.save()
                        }
                } header: {
                    Text("Personality Prompt")
                } footer: {
                    Text("Write a system prompt or personality description. This gets injected into Quinn's system instruction for every session.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    configManager.config.soulFileName = url.lastPathComponent
                    configManager.config.soulText = content
                    soulManager.soulText = content
                    soulManager.save()
                }
            case .failure(let error):
                print("[PersonalityTab] File import failed: \(error)")
            }
        }
        .onAppear {
            // Sync soul manager content into config if config is empty but manager has content
            if configManager.config.soulText.isEmpty && !soulManager.soulText.isEmpty {
                configManager.config.soulText = soulManager.soulText
            }
        }
    }
}

// MARK: - Memory Tab

struct MemoryTab: View {
    var memoryManager: MemoryManager
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    // iCloud sync status
                    HStack {
                        Circle()
                            .fill(syncStatusColor)
                            .frame(width: 8, height: 8)
                        Text(syncStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if memoryManager.iCloudAvailable {
                            Image(systemName: "icloud.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        } else {
                            Image(systemName: "icloud.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("iCloud Sync")
                } footer: {
                    Text("Memory syncs automatically across all your Macs via iCloud.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("Memory Content") {
                    TextEditor(text: Bindable(memoryManager).memoryText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 300)
                        .scrollContentBackground(.hidden)
                        .onChange(of: memoryManager.memoryText) { _, _ in
                            memoryManager.save()
                        }
                }
            }
            .formStyle(.grouped)

            // Bottom bar with stats and actions
            HStack {
                Text("\(memoryManager.lineCount) lines · \(memoryManager.wordCount) words")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                Spacer()

                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Label("Clear Memory", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .alert("Clear Memory?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                memoryManager.clearMemory()
            }
        } message: {
            Text("This will permanently delete all memory content. This action cannot be undone.")
        }
    }

    private var syncStatusColor: Color {
        switch memoryManager.iCloudSyncStatus {
        case .synced: return .green
        case .syncing: return .orange
        case .offline: return .gray
        case .error: return .red
        }
    }

    private var syncStatusText: String {
        switch memoryManager.iCloudSyncStatus {
        case .synced: return "Synced"
        case .syncing: return "Syncing…"
        case .offline: return "Local only"
        case .error: return "Sync error"
        }
    }
}

// MARK: - Agent Tab

struct AgentTab: View {
    @Bindable var configManager: ConfigManager
    @State private var accessibilityGranted = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable Agent Mode", isOn: $configManager.config.agentModeEnabled)
            } header: {
                Text("Agent / Computer Use")
            } footer: {
                Text("When enabled, Quinn can autonomously control your Mac: type, click, run commands, and navigate apps. Say \"take over\" or \"do it for me\" to activate.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if configManager.config.agentModeEnabled {
                Section("Agent Settings") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Max Iterations")
                            Spacer()
                            Text("\(configManager.config.agentMaxIterations)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(configManager.config.agentMaxIterations) },
                                set: { configManager.config.agentMaxIterations = Int($0) }
                            ),
                            in: 5...50,
                            step: 1
                        )
                    }

                    Toggle("Confirm Destructive Commands", isOn: $configManager.config.agentConfirmDestructive)
                }

                Section("Allowed Apps") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(configManager.config.agentAllowedApps.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }

                Section("Permissions") {
                    HStack {
                        Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(accessibilityGranted ? .green : .orange)
                        Text(accessibilityGranted ? "Accessibility granted" : "Accessibility required for computer use")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !accessibilityGranted {
                            Button("Request") {
                                _ = HotkeyManager.checkAccessibilityPermissions(prompt: true)
                                checkPermissions()
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { checkPermissions() }
    }

    private func checkPermissions() {
        accessibilityGranted = HotkeyManager.checkAccessibilityPermissions(prompt: false)
    }
}

// MARK: - Advanced Tab

struct AdvancedTab: View {
    @Bindable var configManager: ConfigManager
    @State private var notificationGranted = false

    var body: some View {
        Form {
            Section("OpenClaw") {
                TextField("Gateway URL", text: $configManager.config.openclawUrl)
                    .textFieldStyle(.roundedBorder)
            }

            Section {
                Toggle("Include Screen Context", isOn: $configManager.config.includeScreenContext)
            } header: {
                Text("Screen Context")
            } footer: {
                Text("When enabled, Quinn sees the name and window title of your frontmost app, plus any selected text. Requires Accessibility permissions.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Clipboard Access", isOn: $configManager.config.clipboardAccess)
            } header: {
                Text("Clipboard")
            } footer: {
                Text("When enabled, Quinn can read and write your clipboard. Say \"summarize what I copied\" or \"copy that to clipboard\".")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable Notifications", isOn: $configManager.config.notificationsEnabled)

                if configManager.config.notificationsEnabled {
                    HStack {
                        Image(systemName: notificationGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(notificationGranted ? .green : .orange)
                        Text(notificationGranted ? "Notifications authorized" : "Notification permission needed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !notificationGranted {
                            Button("Request") {
                                Task {
                                    let mgr = NotificationManager()
                                    await mgr.requestPermission()
                                    notificationGranted = mgr.isAuthorized
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Surface important tool results as native macOS notifications.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Camera and screen sharing can be toggled from the voice panel during an active session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Multi-Modal Input")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            Task {
                let mgr = NotificationManager()
                await mgr.checkAuthorizationStatus()
                notificationGranted = mgr.isAuthorized
            }
        }
    }
}
