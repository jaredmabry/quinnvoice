import Foundation
import Combine

/// Sync status for iCloud documents.
enum SyncStatus: String, Sendable {
    case synced
    case syncing
    case offline
    case error
}

/// Manages an on-device `memory.md` file with iCloud Drive sync.
///
/// Primary storage: iCloud Drive ubiquity container (`iCloud.com.mabryventures.quinnvoice`).
/// Fallback: local `~/Library/Application Support/QuinnVoice/memory.md` if iCloud unavailable.
@Observable
@MainActor
final class MemoryManager {

    // MARK: - Public State

    /// Current memory content.
    var memoryText: String = ""

    /// Whether iCloud container is accessible.
    var iCloudAvailable: Bool = false

    /// Current iCloud sync status.
    var iCloudSyncStatus: SyncStatus = .offline

    /// Word count of current memory.
    var wordCount: Int { memoryText.split(whereSeparator: \.isWhitespace).count }

    /// Line count of current memory.
    var lineCount: Int { memoryText.isEmpty ? 0 : memoryText.components(separatedBy: .newlines).count }

    // MARK: - Private

    private let fileName = "memory.md"
    private let containerIdentifier = "iCloud.com.mabryventures.quinnvoice"
    private var metadataQuery: NSMetadataQuery?
    private var iCloudURL: URL?
    private var localURL: URL
    private var filePresenter: MemoryFilePresenter?
    private var saveTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("QuinnVoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.localURL = dir.appendingPathComponent("memory.md")
    }

    // MARK: - Lifecycle

    /// Load memory from iCloud (or local fallback) and start monitoring for changes.
    func load() {
        setupiCloud()
        readFromDisk()
        startMonitoring()
    }

    /// Save current memory content to disk.
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

    // MARK: - iCloud Setup

    private func setupiCloud() {
        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) {
            let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
            try? FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
            iCloudURL = documentsURL.appendingPathComponent(fileName)
            iCloudAvailable = true
            iCloudSyncStatus = .synced
        } else {
            iCloudAvailable = false
            iCloudSyncStatus = .offline
        }
    }

    private var activeURL: URL {
        iCloudURL ?? localURL
    }

    // MARK: - Read/Write

    private func readFromDisk() {
        let url = activeURL
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                memoryText = content
            } catch {
                print("[MemoryManager] Failed to read \(url.lastPathComponent): \(error)")
            }
        }
    }

    private func writeToDisk() {
        let url = activeURL
        do {
            try memoryText.write(to: url, atomically: true, encoding: .utf8)
            if iCloudAvailable {
                iCloudSyncStatus = .syncing
                // iCloud will handle sync automatically; status updates via metadata query
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self else { return }
                    if self.iCloudSyncStatus == .syncing {
                        self.iCloudSyncStatus = .synced
                    }
                }
            }
        } catch {
            print("[MemoryManager] Failed to write \(url.lastPathComponent): \(error)")
            if iCloudAvailable {
                iCloudSyncStatus = .error
            }
        }
    }

    private func debouncedSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            writeToDisk()
        }
    }

    // MARK: - iCloud Monitoring

    private func startMonitoring() {
        guard iCloudAvailable else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, fileName)

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMetadataUpdate()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMetadataUpdate()
            }
        }

        query.start()
        self.metadataQuery = query

        // Set up file presenter for conflict resolution
        let presenter = MemoryFilePresenter(url: activeURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.readFromDisk()
            }
        }
        NSFileCoordinator.addFilePresenter(presenter)
        self.filePresenter = presenter
    }

    private func handleMetadataUpdate() {
        guard let query = metadataQuery else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        if query.resultCount > 0 {
            if let item = query.result(at: 0) as? NSMetadataItem {
                let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
                if status == NSMetadataUbiquitousItemDownloadingStatusCurrent {
                    iCloudSyncStatus = .synced
                    readFromDisk()
                } else if status == NSMetadataUbiquitousItemDownloadingStatusDownloaded {
                    iCloudSyncStatus = .synced
                    readFromDisk()
                } else {
                    iCloudSyncStatus = .syncing
                    // Trigger download if not yet downloaded
                    if let url = iCloudURL {
                        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                    }
                }
            }
        }
    }

    /// Clean up monitoring resources. Call before releasing the manager.
    func teardown() {
        metadataQuery?.stop()
        metadataQuery = nil
        if let presenter = filePresenter {
            NSFileCoordinator.removeFilePresenter(presenter)
            filePresenter = nil
        }
    }
}

// MARK: - File Presenter

/// Monitors a file for external changes and invokes a callback.
final class MemoryFilePresenter: NSObject, NSFilePresenter, Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue.main
    private let onChange: @Sendable () -> Void

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.presentedItemURL = url
        self.onChange = onChange
        super.init()
    }

    func presentedItemDidChange() {
        onChange()
    }

    func presentedItemDidGain(_ version: NSFileVersion) {
        // Latest write wins — resolve by using current version
        if let url = presentedItemURL {
            do {
                try NSFileVersion.removeOtherVersionsOfItem(at: url)
            } catch {
                print("[MemoryFilePresenter] Failed to resolve conflict: \(error)")
            }
        }
        onChange()
    }
}
