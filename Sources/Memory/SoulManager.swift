import Foundation

/// Manages the `soul.md` personality file with iCloud Drive sync.
///
/// Stores soul/personality content in the same iCloud ubiquity container as MemoryManager.
/// Falls back to local storage if iCloud is unavailable.
@Observable
@MainActor
final class SoulManager {

    // MARK: - Public State

    /// Current soul/personality content.
    var soulText: String = ""

    /// Whether iCloud container is accessible.
    var iCloudAvailable: Bool = false

    /// Current iCloud sync status.
    var iCloudSyncStatus: SyncStatus = .offline

    // MARK: - Private

    private let fileName = "soul.md"
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
        self.localURL = dir.appendingPathComponent("soul.md")
    }

    // MARK: - Lifecycle

    /// Load soul content from iCloud (or local fallback) and start monitoring.
    func load() {
        setupiCloud()
        readFromDisk()
        startMonitoring()
    }

    /// Save current soul content to disk.
    func save() {
        debouncedSave()
    }

    /// Update soul content from an external source (e.g., file import or editor).
    func updateContent(_ text: String) {
        soulText = text
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
                soulText = content
            } catch {
                print("[SoulManager] Failed to read \(url.lastPathComponent): \(error)")
            }
        }
    }

    private func writeToDisk() {
        let url = activeURL
        do {
            try soulText.write(to: url, atomically: true, encoding: .utf8)
            if iCloudAvailable {
                iCloudSyncStatus = .syncing
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self else { return }
                    if self.iCloudSyncStatus == .syncing {
                        self.iCloudSyncStatus = .synced
                    }
                }
            }
        } catch {
            print("[SoulManager] Failed to write \(url.lastPathComponent): \(error)")
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
                if status == NSMetadataUbiquitousItemDownloadingStatusCurrent ||
                   status == NSMetadataUbiquitousItemDownloadingStatusDownloaded {
                    iCloudSyncStatus = .synced
                    readFromDisk()
                } else {
                    iCloudSyncStatus = .syncing
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
