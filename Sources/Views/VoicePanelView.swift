import SwiftUI

/// Main floating Liquid Glass voice panel — the primary UI of QuinnVoice.
///
/// Includes controls for voice session management, transcript panel toggle,
/// and multi-modal sharing (camera/screen) buttons.
struct VoicePanelView: View {
    @Bindable var appState: AppState
    let onToggleSession: () -> Void
    let onStopSession: () -> Void
    let onOpenSettings: () -> Void
    var onToggleCamera: (() -> Void)?
    var onToggleScreen: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Main voice panel
            VStack(spacing: 16) {
                // Header
                HStack {
                    StateIndicator(state: appState.voiceState, level: appState.micLevel)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()

                    // Transcript toggle button
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.showTranscriptPanel.toggle()
                        }
                    } label: {
                        Image(systemName: appState.showTranscriptPanel ? "text.bubble.fill" : "text.bubble")
                            .font(.caption)
                            .foregroundStyle(appState.showTranscriptPanel ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle transcript")

                    Button {
                        onOpenSettings()
                    } label: {
                        Image(systemName: "gear")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                // Waveform visualization
                WaveformView(
                    state: appState.voiceState,
                    micLevel: appState.micLevel,
                    outputLevel: appState.outputLevel
                )
                .frame(height: 60)

                // Multi-modal sharing buttons (only visible during active session)
                if appState.isSessionActive {
                    HStack(spacing: 12) {
                        // Camera share toggle
                        Button {
                            onToggleCamera?()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: appState.isSharingCamera ? "video.fill" : "video")
                                    .font(.caption2)
                                Text(appState.isSharingCamera ? "Camera On" : "Camera")
                                    .font(.caption2)
                            }
                            .foregroundStyle(appState.isSharingCamera ? .green : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                appState.isSharingCamera
                                    ? Color.green.opacity(0.15)
                                    : Color.clear
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(appState.isSharingCamera ? "Stop sharing camera" : "Share camera with Quinn")

                        // Screen share toggle
                        Button {
                            onToggleScreen?()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: appState.isSharingScreen ? "rectangle.inset.filled.and.person.filled" : "rectangle.and.person.inset.filled")
                                    .font(.caption2)
                                Text(appState.isSharingScreen ? "Screen On" : "Screen")
                                    .font(.caption2)
                            }
                            .foregroundStyle(appState.isSharingScreen ? .blue : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                appState.isSharingScreen
                                    ? Color.blue.opacity(0.15)
                                    : Color.clear
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(appState.isSharingScreen ? "Stop sharing screen" : "Share screen with Quinn")
                    }
                }

                // Main action button
                Button {
                    if appState.voiceState == .idle {
                        onToggleSession()
                    } else {
                        onStopSession()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(buttonColor)
                            .frame(width: 56, height: 56)

                        Image(systemName: buttonIcon)
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .scaleEffect(isHovering ? 1.05 : 1.0)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovering = hovering
                    }
                }

                // Wake word indicator
                if appState.isWakeWordListening {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                        Text("Listening for wake word…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Error display
                if let error = appState.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(20)
            .frame(width: 280)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))

            // Transcript panel (slide-out)
            if appState.showTranscriptPanel {
                TranscriptPanelView(
                    appState: appState,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.showTranscriptPanel = false
                        }
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .padding(.leading, 4)
            }
        }
    }

    private var statusText: String {
        switch appState.voiceState {
        case .idle: return "Ready"
        case .listening: return "Listening…"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking…"
        }
    }

    private var buttonColor: Color {
        switch appState.voiceState {
        case .idle: return .blue
        case .listening: return .red
        case .thinking: return .purple
        case .speaking: return .green
        }
    }

    private var buttonIcon: String {
        switch appState.voiceState {
        case .idle: return "mic.fill"
        case .listening: return "stop.fill"
        case .thinking: return "ellipsis"
        case .speaking: return "stop.fill"
        }
    }
}

/// Small floating indicator shown when the hotkey is activated (even with panel closed).
struct HotkeyIndicatorView: View {
    let isActive: Bool

    var body: some View {
        if isActive {
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("⌥Space")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .transition(.scale.combined(with: .opacity))
        }
    }
}
