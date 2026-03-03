import Foundation

// MARK: - Conversation Entry

/// A single entry in a conversation transcript (one user or assistant turn).
struct ConversationEntry: Codable, Sendable, Identifiable {
    /// Unique identifier for this entry.
    let id: UUID

    /// When this entry was created.
    let timestamp: Date

    /// Who produced this entry.
    let role: ConversationRole

    /// The text content of the entry.
    let text: String

    /// Duration of audio in seconds, if this entry was spoken.
    let audioLengthSeconds: Double?

    init(id: UUID = UUID(), timestamp: Date = Date(), role: ConversationRole, text: String, audioLengthSeconds: Double? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.role = role
        self.text = text
        self.audioLengthSeconds = audioLengthSeconds
    }
}

/// The role of a conversation entry author.
enum ConversationRole: String, Codable, Sendable {
    case user
    case assistant
    case system
    case tool
}

// MARK: - Conversation Session

/// A complete conversation session containing multiple entries.
struct ConversationSession: Codable, Sendable, Identifiable {
    /// Unique identifier for this session.
    let id: UUID

    /// Auto-generated title from the first user message.
    var title: String

    /// When the session started.
    let startedAt: Date

    /// When the session ended, or `nil` if still active.
    var endedAt: Date?

    /// All conversation entries in chronological order.
    var entries: [ConversationEntry]

    /// The duration of this session, or time since start if still active.
    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    /// Number of entries in this session.
    var entryCount: Int { entries.count }

    init(id: UUID = UUID(), title: String = "New Conversation", startedAt: Date = Date(), endedAt: Date? = nil, entries: [ConversationEntry] = []) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.entries = entries
    }
}

// MARK: - Conversation Store

/// Manages persistent storage of conversation sessions with iCloud sync and local fallback.
///
/// Sessions are stored as individual JSON files (one per session) in either the iCloud
/// ubiquity container or local Application Support directory.
@Observable
@MainActor
final class ConversationStore {

    // MARK: - Public State

    /// All sessions sorted by date descending (most recent first).
    var sessions: [ConversationSession] = []

    // MARK: - Private

    private let containerIdentifier = "iCloud.com.mabryventures.quinnvoice"
    private let historyDirectoryName = "history"
    private var iCloudURL: URL?
    private var localURL: URL
    private var metadataQuery: NSMetadataQuery?

    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("QuinnVoice", isDirectory: true)
            .appendingPathComponent("history", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.localURL = dir
        setupiCloud()
        loadAll()
        startMonitoring()
    }

    // MARK: - iCloud Setup

    private func setupiCloud() {
        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) {
            let historyURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(historyDirectoryName, isDirectory: true)
            try? FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: true)
            iCloudURL = historyURL
        }
    }

    /// The directory used for reading and writing session files.
    private var activeURL: URL {
        iCloudURL ?? localURL
    }

    // MARK: - Session Management

    /// Start a new conversation session and return it.
    @discardableResult
    func startSession() -> ConversationSession {
        let session = ConversationSession()
        sessions.insert(session, at: 0)
        saveSession(session)
        return session
    }

    /// End a session by setting its `endedAt` timestamp.
    func endSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].endedAt = Date()
        saveSession(sessions[index])
    }

    /// Add an entry to an existing session.
    func addEntry(to sessionId: UUID, role: ConversationRole, text: String, audioLength: Double? = nil) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        let entry = ConversationEntry(role: role, text: text, audioLengthSeconds: audioLength)
        sessions[index].entries.append(entry)

        // Auto-title from first user message
        if sessions[index].title == "New Conversation" && role == .user {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            sessions[index].title = String(trimmed.prefix(50))
        }

        saveSession(sessions[index])
    }

    /// Delete a session and remove its file from disk.
    func deleteSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions.remove(at: index)
        let fileURL = activeURL.appendingPathComponent("\(session.id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Delete all sessions.
    func deleteAll() {
        for session in sessions {
            let fileURL = activeURL.appendingPathComponent("\(session.id.uuidString).json")
            try? FileManager.default.removeItem(at: fileURL)
        }
        sessions.removeAll()
    }

    /// Full-text search across all sessions and their entries.
    func search(query: String) -> [(session: ConversationSession, matches: [ConversationEntry])] {
        guard !query.isEmpty else { return [] }
        let lowered = query.lowercased()

        var results: [(session: ConversationSession, matches: [ConversationEntry])] = []
        for session in sessions {
            let matches = session.entries.filter { $0.text.lowercased().contains(lowered) }
            if !matches.isEmpty || session.title.lowercased().contains(lowered) {
                results.append((session: session, matches: matches))
            }
        }
        return results
    }

    /// Load all session files from disk.
    func loadAll() {
        let url = activeURL
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var loaded: [ConversationSession] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let session = try? jsonDecoder.decode(ConversationSession.self, from: data) {
                loaded.append(session)
            }
        }

        sessions = loaded.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Persistence

    /// Save a single session to its JSON file.
    private func saveSession(_ session: ConversationSession) {
        let fileURL = activeURL.appendingPathComponent("\(session.id.uuidString).json")
        guard let data = try? jsonEncoder.encode(session) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - iCloud Monitoring

    private func startMonitoring() {
        guard iCloudURL != nil else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K ENDSWITH '.json' AND %K CONTAINS 'history'",
                                       NSMetadataItemFSNameKey, NSMetadataItemPathKey)

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadAll()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadAll()
            }
        }

        query.start()
        self.metadataQuery = query
    }

}

// MARK: - Date Grouping

/// Groups conversation sessions by relative date for display.
enum SessionDateGroup: String, CaseIterable {
    case today = "Today"
    case yesterday = "Yesterday"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case older = "Older"

    /// Categorize a date into the appropriate group relative to now.
    static func group(for date: Date) -> SessionDateGroup {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            return .today
        } else if calendar.isDateInYesterday(date) {
            return .yesterday
        } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date >= weekAgo {
            return .thisWeek
        } else if let monthAgo = calendar.date(byAdding: .month, value: -1, to: now), date >= monthAgo {
            return .thisMonth
        } else {
            return .older
        }
    }
}
