import Foundation

/// Manages soul/personality content with iCloud sync via `NSUbiquitousKeyValueStore`.
///
/// Same sync mechanism as `MemoryManager` — uses KV store for cross-device sync,
/// local file as backup. Works without sandbox.
@Observable
@MainActor
final class SoulManager {

    // MARK: - Public State

    /// Current soul content.
    var soulText: String = ""

    /// Whether iCloud is available for sync.
    var iCloudAvailable: Bool = false

    /// Current sync status.
    var syncStatus: SyncStatus = .offline

    // MARK: - Private

    private let kvStoreKey = "soul_md"
    private let localURL: URL
    private var saveTask: Task<Void, Never>?
    private var kvStore: NSUbiquitousKeyValueStore { .default }

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("QuinnVoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.localURL = dir.appendingPathComponent("soul.md")
    }

    // MARK: - Lifecycle

    /// Load soul content from iCloud KV store (or local fallback).
    func load() {
        setupiCloudKVStore()
        readContent()
    }

    /// Save current soul content.
    func save() {
        debouncedSave()
    }

    // MARK: - iCloud KV Store

    private func setupiCloudKVStore() {
        let synced = kvStore.synchronize()
        iCloudAvailable = synced
        syncStatus = synced ? .synced : .offline

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
        if iCloudAvailable, let cloudContent = kvStore.string(forKey: kvStoreKey), !cloudContent.isEmpty {
            soulText = cloudContent
            writeToLocal()
            return
        }

        if FileManager.default.fileExists(atPath: localURL.path) {
            do {
                soulText = try String(contentsOf: localURL, encoding: .utf8)
            } catch {
                print("[SoulManager] Failed to read local file: \(error)")
            }
        }
    }

    private func writeContent() {
        writeToLocal()

        if iCloudAvailable {
            if soulText.utf8.count < 60_000 {
                syncStatus = .syncing
                kvStore.set(soulText, forKey: kvStoreKey)
                kvStore.synchronize()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self else { return }
                    if self.syncStatus == .syncing {
                        self.syncStatus = .synced
                    }
                }
            } else {
                syncStatus = .offline
            }
        }
    }

    private func writeToLocal() {
        do {
            try soulText.write(to: localURL, atomically: true, encoding: .utf8)
        } catch {
            print("[SoulManager] Failed to write local file: \(error)")
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
            if let newContent = kvStore.string(forKey: kvStoreKey) {
                soulText = newContent
                writeToLocal()
                syncStatus = .synced
            }
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            syncStatus = .error
        case NSUbiquitousKeyValueStoreAccountChange:
            readContent()
        default:
            break
        }
    }

    func teardown() {
        NotificationCenter.default.removeObserver(self)
    }
}
