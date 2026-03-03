import SwiftUI

/// Configuration UI for QuinnVoice settings.
///
/// Organized into sections covering API configuration, voice settings, OpenClaw connection,
/// behavior, hotkey, screen context, clipboard, wake word, notifications, and multi-modal input.
struct SettingsView: View {
    @Bindable var configManager: ConfigManager
    @Environment(\.dismiss) private var dismiss

    @State private var accessibilityGranted = false
    @State private var notificationGranted = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("QuinnVoice Settings")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    configManager.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                Form {
                    // MARK: - Gemini API
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

                    // MARK: - Voice
                    Section("Voice") {
                        Picker("Voice", selection: $configManager.config.voiceConfig.name) {
                            ForEach(VoiceConfig.availableVoices, id: \.self) { voice in
                                Text(voice).tag(voice)
                            }
                        }
                    }

                    // MARK: - OpenClaw
                    Section("OpenClaw") {
                        TextField("Gateway URL", text: $configManager.config.openclawUrl)
                            .textFieldStyle(.roundedBorder)
                    }

                    // MARK: - Behavior
                    Section("Behavior") {
                        Toggle("Continuous Mode", isOn: $configManager.config.continuousMode)
                        Toggle("Show Transcript", isOn: $configManager.config.showTranscript)
                    }

                    // MARK: - Global Hotkey
                    Section {
                        Toggle("Enable Global Hotkey (⌥Space)", isOn: $configManager.config.hotkeyEnabled)

                        if configManager.config.hotkeyEnabled {
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
                    } header: {
                        Text("Global Hotkey")
                    } footer: {
                        Text("⌥Space activates Quinn from anywhere. Hold mode: hold key to talk. Toggle mode: press to start, press again to stop.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // MARK: - Screen Context
                    Section {
                        Toggle("Include Screen Context", isOn: $configManager.config.includeScreenContext)
                    } header: {
                        Text("Screen Context")
                    } footer: {
                        Text("When enabled, Quinn sees the name and window title of your frontmost app, plus any selected text. Requires Accessibility permissions.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // MARK: - Clipboard
                    Section {
                        Toggle("Clipboard Access", isOn: $configManager.config.clipboardAccess)
                    } header: {
                        Text("Clipboard")
                    } footer: {
                        Text("When enabled, Quinn can read and write your clipboard. Say \"summarize what I copied\" or \"copy that to clipboard\".")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // MARK: - Wake Word
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

                    // MARK: - Notifications
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
                        Text("Surface important tool results (calendar conflicts, security alerts, reminders) as native macOS notifications.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // MARK: - Multi-Modal
                    Section {
                        Text("Camera and screen sharing can be toggled from the voice panel during an active session. Quinn will send periodic frames to Gemini for visual context.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Multi-Modal Input")
                    }
                }
                .formStyle(.grouped)
                .padding()
            }
        }
        .frame(width: 480, height: 700)
        .onAppear {
            checkPermissions()
        }
    }

    private func checkPermissions() {
        accessibilityGranted = HotkeyManager.checkAccessibilityPermissions(prompt: false)
        Task {
            let mgr = NotificationManager()
            await mgr.checkAuthorizationStatus()
            notificationGranted = mgr.isAuthorized
        }
    }
}
