import Foundation
import Sparkle

/// Manages application auto-updates using the Sparkle framework.
///
/// Wraps `SPUStandardUpdaterController` and provides observable state for the settings UI.
/// The appcast URL is configured via the `SUFeedURL` Info.plist key or defaults to the
/// GitHub releases atom feed.
@Observable
@MainActor
final class UpdateManager {

    // MARK: - Public State

    /// Whether an update is available for download.
    var updateAvailable: Bool = false

    /// The current app version from the main bundle.
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// The current build number from the main bundle.
    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// The latest version available, if known.
    var latestVersion: String?

    /// Whether Sparkle is currently checking for updates.
    var isChecking: Bool = false

    /// The last time an update check was performed.
    var lastCheckDate: Date?

    // MARK: - Private

    /// The Sparkle updater controller, initialized lazily.
    private var updaterController: SPUStandardUpdaterController?

    /// The updater delegate that receives Sparkle callbacks.
    private let updaterDelegate = UpdateManagerDelegate()

    // MARK: - Init

    init() {
        setupSparkle()
    }

    // MARK: - Setup

    /// Initialize the Sparkle updater controller.
    ///
    /// Sparkle reads the `SUFeedURL` key from Info.plist to determine where to look for updates.
    /// If running as a debug build without a proper bundle, Sparkle initialization may fail silently.
    private func setupSparkle() {
        // Create the updater controller — Sparkle handles all UI and download logic
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
        self.updaterController = controller

        // Wire delegate callbacks back to this manager
        updaterDelegate.onUpdateFound = { [weak self] version in
            guard let self else { return }
            self.updateAvailable = true
            self.latestVersion = version
        }

        updaterDelegate.onCheckComplete = { [weak self] in
            guard let self else { return }
            self.isChecking = false
            self.lastCheckDate = Date()
        }
    }

    // MARK: - Actions

    /// Manually check for updates, showing UI to the user.
    func checkForUpdates() {
        guard let controller = updaterController else { return }
        isChecking = true
        controller.checkForUpdates(nil)
    }

    /// Silently check for updates in the background without showing UI.
    func checkForUpdatesInBackground() {
        guard let updater = updaterController?.updater else { return }
        isChecking = true
        updater.checkForUpdatesInBackground()
    }

    /// Whether automatic update checks are enabled in Sparkle.
    var automaticallyChecksForUpdates: Bool {
        get { updaterController?.updater.automaticallyChecksForUpdates ?? true }
        set { updaterController?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Start the Sparkle updater (call once during app launch).
    func startUpdater() {
        try? updaterController?.updater.start()
    }

    /// Whether the updater can currently check for updates.
    var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? false
    }
}

// MARK: - Sparkle Delegate

/// Delegate that receives callbacks from the Sparkle updater.
final class UpdateManagerDelegate: NSObject, SPUUpdaterDelegate, @unchecked Sendable {

    /// Called when an update is found.
    var onUpdateFound: ((String) -> Void)?

    /// Called when the update check completes.
    var onCheckComplete: (() -> Void)?

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            onUpdateFound?(version)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor in
            onCheckComplete?()
        }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        Task { @MainActor in
            onCheckComplete?()
        }
    }
}
