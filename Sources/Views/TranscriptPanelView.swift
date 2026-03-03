import SwiftUI

/// Slide-out conversation history panel showing the full transcript with timestamps.
///
/// Displays user messages (from STT) and Quinn's responses in distinct visual styles,
/// with auto-scrolling to the latest message. Each message includes a copy button
/// and timestamp. Uses Liquid Glass aesthetic consistent with the main voice panel.
struct TranscriptPanelView: View {
    @Bindable var appState: AppState
    let onClose: () -> Void

    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(.secondary)
                Text("Conversation")
                    .font(.headline)
                Spacer()
                Button {
                    appState.clearTranscript()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear conversation")

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close transcript")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Transcript content
            if appState.transcript.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.largeTitle)
                        .foregroundStyle(.quaternary)
                    Text("No messages yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(appState.transcript) { line in
                                TranscriptMessageView(line: line)
                                    .id(line.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: appState.transcript.count) { _, _ in
                        // Auto-scroll to the latest message
                        if let lastId = appState.transcript.last?.id {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        // Scroll to bottom on initial appearance
                        if let lastId = appState.transcript.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(width: 300, height: 400)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }
}

/// A single message bubble in the transcript.
struct TranscriptMessageView: View {
    let line: TranscriptLine
    @State private var isHovering = false
    @State private var showCopied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if line.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: line.role == .user ? .trailing : .leading, spacing: 4) {
                // Role label and timestamp
                HStack(spacing: 4) {
                    Text(roleLabel)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(roleColor)

                    Text(formattedTime)
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }

                // Message text
                Text(line.text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(messageBubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // Copy button (shown on hover)
                if isHovering {
                    Button {
                        copyToClipboard()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            Text(showCopied ? "Copied" : "Copy")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }

            if line.role == .assistant || line.role == .system {
                Spacer(minLength: 40)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private var roleLabel: String {
        switch line.role {
        case .user: return "You"
        case .assistant: return "Quinn"
        case .system: return "System"
        }
    }

    private var roleColor: Color {
        switch line.role {
        case .user: return .blue
        case .assistant: return .green
        case .system: return .orange
        }
    }

    private var messageBubbleBackground: some ShapeStyle {
        switch line.role {
        case .user: return Color.blue.opacity(0.12)
        case .assistant: return Color.green.opacity(0.08)
        case .system: return Color.orange.opacity(0.08)
        }
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: line.timestamp)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line.text, forType: .string)
        showCopied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            showCopied = false
        }
    }
}
