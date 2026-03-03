import Foundation

/// Sync status for iCloud key-value store.
enum SyncStatus: String, Sendable {
    case synced
    case syncing
    case offline
    case error
}

/// Manages an on-device `memory.md` with iCloud sync via `NSUbiquitousKeyValueStore`.
///
/// Uses `NSUbiquitousKeyValueStore` for cross-device sync (works without sandbox).
/// Falls back to local-only storage if iCloud is unavailable.
/// Local copy at `~/Library/Application Support/QuinnVoice/memory.md` always exists as backup.
@Observable
@MainActor
final class MemoryManager {

    // MARK: - Public State

    /// Current memory content.
    var memoryText: String = ""

    /// Whether iCloud key-value store is accessible.
    var iCloudAvailable: Bool = false

    /// Current iCloud sync status.
    var iCloudSyncStatus: SyncStatus = .offline

    /// Word count of current memory.
    var wordCount: Int { memoryText.split(whereSeparator: \.isWhitespace).count }

    /// Line count of current memory.
    var lineCount: Int { memoryText.isEmpty ? 0 : memoryText.components(separatedBy: .newlines).count }

    // MARK: - Private

    private let kvStoreKey = "memory_md"
    private let localURL: URL
    private var saveTask: Task<Void, Never>?
    private var kvStore: NSUbiquitousKeyValueStore { .default }

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("QuinnVoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.localURL = dir.appendingPathComponent("memory.md")
    }

    // MARK: - Lifecycle

    /// Load memory from iCloud KV store (or local fallback) and start monitoring.
    func load() {
        setupiCloudKVStore()
        readContent()
    }

    /// Save current memory content.
    func save() {
        debouncedSave()
    }

    /// Append a timestamped entry to memory.
    func appendEntry(_ text: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime, .withSpaceBetweenDateAndTime]
        let timestamp = formatter.string(from: Date())
        let entry = "\n\n---\n**\(timestamp)**\n\(text)"
        memoryText += entry
        save()
    }

    /// Clear all memory content.
    func clearMemory() {
        memoryText = ""
        save()
    }

    // MARK: - iCloud KV Store Setup

    private func setupiCloudKVStore() {
        // NSUbiquitousKeyValueStore works without sandbox — just needs
        // com.apple.developer.ubiquity-kvstore-identifier entitlement
        let synced = kvStore.synchronize()
        iCloudAvailable = synced
        iCloudSyncStatus = synced ? .synced : .offline

        // Monitor for external changes (other devices)
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore,
            queue: .main
        ) { [weak self] notif in
            let reason = notif.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let changedKeys = notif.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            Task { @MainActor [weak self] in
                self?.handleKVStoreChange(reason: reason, changedKeys: changedKeys)
            }
        }
    }

    // MARK: - Read/Write

    private func readContent() {
        // Try iCloud KV store first
        if iCloudAvailable, let cloudContent = kvStore.string(forKey: kvStoreKey), !cloudContent.isEmpty {
            memoryText = cloudContent
            // Also update local backup
            writeToLocal()
            return
        }

        // Fall back to local file
        if FileManager.default.fileExists(atPath: localURL.path) {
            do {
                memoryText = try String(contentsOf: localURL, encoding: .utf8)
            } catch {
                print("[MemoryManager] Failed to read local file: \(error)")
            }
        }
    }

    private func writeContent() {
        // Always write to local backup
        writeToLocal()

        // Write to iCloud KV store if available
        if iCloudAvailable {
            // KV store has 64KB per key limit — check size
            if memoryText.utf8.count < 60_000 {
                iCloudSyncStatus = .syncing
                kvStore.set(memoryText, forKey: kvStoreKey)
                kvStore.synchronize()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self else { return }
                    if self.iCloudSyncStatus == .syncing {
                        self.iCloudSyncStatus = .synced
                    }
                }
            } else {
                // Content too large for KV store — local only
                print("[MemoryManager] Memory content exceeds 60KB, syncing locally only")
                iCloudSyncStatus = .offline
            }
        }
    }

    private func writeToLocal() {
        do {
            try memoryText.write(to: localURL, atomically: true, encoding: .utf8)
        } catch {
            print("[MemoryManager] Failed to write local file: \(error)")
        }
    }

    private func debouncedSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            writeContent()
        }
    }

    // MARK: - iCloud Change Handling

    private func handleKVStoreChange(reason: Int?, changedKeys: [String]?) {
        guard let reason,
              let changedKeys,
              changedKeys.contains(kvStoreKey) else {
            return
        }

        switch reason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            // Another device updated — pull the new content
            if let newContent = kvStore.string(forKey: kvStoreKey) {
                memoryText = newContent
                writeToLocal()
                iCloudSyncStatus = .synced
            }

        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            print("[MemoryManager] iCloud KV store quota exceeded")
            iCloudSyncStatus = .error

        case NSUbiquitousKeyValueStoreAccountChange:
            // iCloud account changed — re-sync
            readContent()

        default:
            break
        }
    }

    /// Clean up monitoring resources.
    func teardown() {
        NotificationCenter.default.removeObserver(self)
    }
}
