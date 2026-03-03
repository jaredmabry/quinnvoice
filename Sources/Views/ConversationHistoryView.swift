import SwiftUI

/// Full conversation history browser with sidebar-detail layout.
///
/// Displays all past sessions grouped by date, with search, export, and delete functionality.
/// Opens in its own window at 700×500.
struct ConversationHistoryView: View {
    @Bindable var store: ConversationStore
    @State private var selectedSessionId: UUID?
    @State private var searchText: String = ""
    @State private var showClearConfirmation = false

    /// Sessions filtered by search text.
    private var filteredSessions: [ConversationSession] {
        if searchText.isEmpty {
            return store.sessions
        }
        let lowered = searchText.lowercased()
        return store.sessions.filter { session in
            session.title.lowercased().contains(lowered) ||
            session.entries.contains { $0.text.lowercased().contains(lowered) }
        }
    }

    /// Group filtered sessions by date category.
    private var groupedSessions: [(group: SessionDateGroup, sessions: [ConversationSession])] {
        var dict: [SessionDateGroup: [ConversationSession]] = [:]
        for session in filteredSessions {
            let group = SessionDateGroup.group(for: session.startedAt)
            dict[group, default: []].append(session)
        }
        return SessionDateGroup.allCases.compactMap { group in
            guard let sessions = dict[group], !sessions.isEmpty else { return nil }
            return (group: group, sessions: sessions)
        }
    }

    /// The currently selected session.
    private var selectedSession: ConversationSession? {
        guard let id = selectedSessionId else { return nil }
        return store.sessions.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .frame(minWidth: 700, minHeight: 500)
        .alert("Clear All History?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                store.deleteAll()
                selectedSessionId = nil
            }
        } message: {
            Text("This will permanently delete all \(store.sessions.count) conversation sessions. This cannot be undone.")
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSessionId) {
                if groupedSessions.isEmpty {
                    ContentUnavailableView {
                        Label(searchText.isEmpty ? "No Conversations Yet" : "No Results", systemImage: searchText.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass")
                    } description: {
                        Text(searchText.isEmpty ? "Start a voice session to see your conversation history here." : "Try a different search term.")
                    }
                } else {
                    ForEach(groupedSessions, id: \.group) { groupEntry in
                        Section(groupEntry.group.rawValue) {
                            ForEach(groupEntry.sessions) { session in
                                SessionRowView(session: session)
                                    .tag(session.id)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            store.deleteSession(session.id)
                                            if selectedSessionId == session.id {
                                                selectedSessionId = nil
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search conversations…")

            // Bottom toolbar
            HStack {
                Text("\(store.sessions.count) sessions")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                if !store.sessions.isEmpty {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label("Clear All", systemImage: "trash")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 350)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if let session = selectedSession {
            SessionDetailView(session: session)
        } else {
            ContentUnavailableView {
                Label("Select a Conversation", systemImage: "text.bubble")
            } description: {
                Text("Choose a session from the sidebar to view its transcript.")
            }
        }
    }
}

// MARK: - Session Row

/// A single row in the session list sidebar.
struct SessionRowView: View {
    let session: ConversationSession

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(.body)
                .fontWeight(.medium)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(Self.dateFormatter.string(from: session.startedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("•")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)

                Text("\(session.entryCount) entries")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if session.duration > 0 {
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)

                    Text(formattedDuration)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var formattedDuration: String {
        let minutes = Int(session.duration / 60)
        let seconds = Int(session.duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

// MARK: - Session Detail

/// The detail view showing a full conversation transcript.
struct SessionDetailView: View {
    let session: ConversationSession

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.headline)
                    Text("\(session.entryCount) entries • \(formattedDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Export menu
                Menu {
                    Button {
                        exportMarkdown()
                    } label: {
                        Label("Copy as Markdown", systemImage: "doc.plaintext")
                    }

                    Button {
                        shareMarkdown()
                    } label: {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Transcript
            if session.entries.isEmpty {
                ContentUnavailableView {
                    Label("Empty Session", systemImage: "text.bubble")
                } description: {
                    Text("This session has no transcript entries.")
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(session.entries) { entry in
                            EntryBubbleView(entry: entry)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var formattedDuration: String {
        let minutes = Int(session.duration / 60)
        let seconds = Int(session.duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private func exportMarkdown() {
        let md = ConversationExporter.exportAsMarkdown(session: session)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }

    private func shareMarkdown() {
        let md = ConversationExporter.exportAsMarkdown(session: session)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(session.title).md")
        try? md.write(to: tempURL, atomically: true, encoding: .utf8)

        let picker = NSSharingServicePicker(items: [tempURL])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        }
    }
}

// MARK: - Entry Bubble

/// A single conversation entry rendered as a colored bubble.
struct EntryBubbleView: View {
    let entry: ConversationEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .medium
        return f
    }()

    private var roleColor: Color {
        switch entry.role {
        case .user: return .blue
        case .assistant: return .purple
        case .system: return .gray
        case .tool: return .orange
        }
    }

    private var roleLabel: String {
        switch entry.role {
        case .user: return "You"
        case .assistant: return "Quinn"
        case .system: return "System"
        case .tool: return "Tool"
        }
    }

    private var isUser: Bool { entry.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(roleLabel)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(roleColor)

                    Text(Self.timeFormatter.string(from: entry.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(entry.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(roleColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}
