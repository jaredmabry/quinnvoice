import Foundation
import AppKit

/// Manages application auto-updates by checking GitHub Releases.
///
/// Checks the GitHub API for the latest release and compares version numbers.
/// Downloads are handled by opening the release page in the browser.
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

    /// URL to the latest release page.
    var latestReleaseURL: URL?

    /// URL to the DMG download.
    var latestDownloadURL: URL?

    /// Whether currently checking for updates.
    var isChecking: Bool = false

    /// The last time an update check was performed.
    var lastCheckDate: Date?

    /// Whether the user can check for updates.
    var canCheckForUpdates: Bool { !isChecking }

    /// Whether automatic update checks are enabled.
    var automaticallyChecksForUpdates: Bool = true

    // MARK: - Private

    private let repoOwner = "jaredmabry"
    private let repoName = "quinnvoice"

    // MARK: - Actions

    /// Check GitHub Releases for a newer version.
    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true

        Task {
            defer {
                Task { @MainActor in
                    self.isChecking = false
                    self.lastCheckDate = Date()
                }
            }

            do {
                let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
                var request = URLRequest(url: url)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 15

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("[UpdateManager] GitHub API returned non-200")
                    return
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String,
                      let htmlURL = json["html_url"] as? String else {
                    print("[UpdateManager] Failed to parse release JSON")
                    return
                }

                // Extract version from tag (strip leading 'v')
                let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

                // Find DMG asset
                var dmgURL: URL?
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           name.hasSuffix(".dmg"),
                           let downloadURL = asset["browser_download_url"] as? String {
                            dmgURL = URL(string: downloadURL)
                            break
                        }
                    }
                }

                await MainActor.run {
                    self.latestVersion = remoteVersion
                    self.latestReleaseURL = URL(string: htmlURL)
                    self.latestDownloadURL = dmgURL

                    if isNewerVersion(remoteVersion, than: self.currentVersion) {
                        self.updateAvailable = true
                    } else {
                        self.updateAvailable = false
                    }
                }
            } catch {
                print("[UpdateManager] Update check failed: \(error)")
            }
        }
    }

    /// Check for updates silently in the background.
    func checkForUpdatesInBackground() {
        checkForUpdates()
    }

    /// Open the latest release page or download URL in the browser.
    func downloadUpdate() {
        if let url = latestDownloadURL ?? latestReleaseURL {
            NSWorkspace.shared.open(url)
        }
    }

    /// Start checking for updates on app launch (if automatic checks are enabled).
    func startUpdater() {
        if automaticallyChecksForUpdates {
            // Delay initial check by 30 seconds to not slow down launch
            Task {
                try? await Task.sleep(for: .seconds(30))
                checkForUpdatesInBackground()
            }
        }
    }

    // MARK: - Version Comparison

    /// Compare semantic versions. Returns true if `remote` is newer than `local`.
    private func isNewerVersion(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}
