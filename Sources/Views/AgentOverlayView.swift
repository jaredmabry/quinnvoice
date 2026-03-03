import SwiftUI

/// Floating overlay bar that appears when Quinn is in autonomous agent/computer-use mode.
///
/// Displays at the top of the screen as a semi-transparent Liquid Glass bar showing:
/// - Current action description
/// - Step progress (e.g., "Step 3/20")
/// - Pause, Resume, and Stop controls
/// - Confirmation dialog for destructive actions
/// - Expandable action log
///
/// Uses `NSPanel` with `.floating` window level to stay above all other windows.
struct AgentOverlayView: View {
    @Bindable var appState: AppState
    let onStop: () -> Void
    let onConfirm: (Bool) -> Void

    @State private var showLog = false

    var body: some View {
        VStack(spacing: 0) {
            // Main status bar
            HStack(spacing: 12) {
                // Robot indicator with active glow
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .blur(radius: 4)
                        .opacity(appState.isAgentMode ? 1 : 0)

                    Image(systemName: "cpu")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(appState.isAgentMode ? .red : .secondary)
                }

                // Status text
                VStack(alignment: .leading, spacing: 2) {
                    Text("🤖 Quinn is working")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    if let status = appState.agentStatus {
                        Text(status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Step counter
                Text("Step \(appState.agentIteration)/\(appState.agentMaxIterations)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())

                // Log toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showLog.toggle()
                    }
                } label: {
                    Image(systemName: showLog ? "list.bullet.circle.fill" : "list.bullet.circle")
                        .font(.caption)
                        .foregroundStyle(showLog ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help("Show action log")

                // Stop button
                Button {
                    onStop()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.caption2)
                        Text("Stop")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.red)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Confirmation bar (when awaiting user approval)
            if let pendingAction = appState.agentPendingConfirmation {
                Divider()

                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Confirmation Required")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(pendingAction.displayDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Button {
                        onConfirm(false)
                    } label: {
                        Text("Deny")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.red.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onConfirm(true)
                    } label: {
                        Text("Allow")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.green)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
            }

            // Expandable action log
            if showLog && !appState.agentLog.isEmpty {
                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(appState.agentLog) { entry in
                                AgentLogEntryRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 200)
                    .onChange(of: appState.agentLog.count) { _, _ in
                        if let lastEntry = appState.agentLog.last {
                            withAnimation {
                                proxy.scrollTo(lastEntry.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    appState.isAgentMode ? Color.red.opacity(0.4) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .frame(width: 480)
        .padding(.top, 8)
    }
}

/// A single row in the agent action log.
struct AgentLogEntryRow: View {
    let entry: AgentLogEntry

    private var timeFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Status icon
            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(entry.success ? .green : .red)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.action.displayDescription)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Spacer()

                    Text(timeFormatter.string(from: entry.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                if let observation = entry.observation, !observation.isEmpty {
                    Text(observation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
    }
}

// MARK: - Agent Overlay Window Controller

/// Manages the floating `NSPanel` that hosts the agent overlay.
///
/// Creates a borderless, floating panel that stays on top of all windows
/// and positions itself at the top-center of the main screen.
@MainActor
final class AgentOverlayWindowController {
    private var panel: NSPanel?

    /// Show the agent overlay.
    func show(appState: AppState, onStop: @escaping () -> Void, onConfirm: @escaping (Bool) -> Void) {
        guard panel == nil else { return }

        let overlayView = AgentOverlayView(
            appState: appState,
            onStop: onStop,
            onConfirm: onConfirm
        )

        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 120)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Position at top center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 240
            let y = screenFrame.maxY - 130
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        self.panel = panel
    }

    /// Hide and release the agent overlay.
    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Whether the overlay is currently visible.
    var isVisible: Bool { panel != nil }
}
