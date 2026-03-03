import Foundation
import AppKit

/// Manages application auto-updates by checking GitHub Releases.
///
/// Checks the GitHub API for the latest release, downloads the DMG,
/// mounts it, replaces the running app, and relaunches.
@Observable
@MainActor
final class UpdateManager {

    // MARK: - Public State

    var updateAvailable: Bool = false
    var isChecking: Bool = false
    var isDownloading: Bool = false
    var isInstalling: Bool = false
    var downloadProgress: Double = 0
    var updateError: String?
    var lastCheckDate: Date?
    var latestVersion: String?
    var latestReleaseURL: URL?
    var latestDownloadURL: URL?
    var automaticallyChecksForUpdates: Bool = true

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    var canCheckForUpdates: Bool { !isChecking && !isDownloading && !isInstalling }

    // MARK: - Private

    private let repoOwner = "jaredmabry"
    private let repoName = "quinnvoice"

    // MARK: - Check for Updates

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        updateError = nil

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
                    await MainActor.run { self.updateError = "GitHub API error" }
                    return
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String,
                      let htmlURL = json["html_url"] as? String else {
                    await MainActor.run { self.updateError = "Failed to parse release" }
                    return
                }

                let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

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
                    self.updateAvailable = isNewerVersion(remoteVersion, than: self.currentVersion)
                }
            } catch {
                await MainActor.run { self.updateError = "Check failed: \(error.localizedDescription)" }
            }
        }
    }

    func checkForUpdatesInBackground() {
        checkForUpdates()
    }

    func startUpdater() {
        if automaticallyChecksForUpdates {
            Task {
                try? await Task.sleep(for: .seconds(30))
                checkForUpdatesInBackground()
            }
        }
    }

    // MARK: - Download & Install

    /// Download the DMG, mount it, replace the app, and relaunch.
    func installUpdate() {
        guard let dmgURL = latestDownloadURL else {
            // Fallback: open in browser
            if let url = latestReleaseURL {
                NSWorkspace.shared.open(url)
            }
            return
        }

        isDownloading = true
        downloadProgress = 0
        updateError = nil

        Task {
            do {
                // 1. Download DMG to temp
                let dmgPath = try await downloadDMG(from: dmgURL)

                await MainActor.run {
                    self.isDownloading = false
                    self.isInstalling = true
                }

                // 2. Mount DMG
                let mountPoint = try await mountDMG(at: dmgPath)

                // 3. Find .app in mounted volume
                let appPath = try findApp(in: mountPoint)

                // 4. Get current app location
                guard let currentAppPath = currentAppBundlePath() else {
                    throw UpdateError.cannotLocateCurrentApp
                }

                // 5. Replace app via shell script that runs after we quit
                try await replaceAndRelaunch(
                    newApp: appPath,
                    currentApp: currentAppPath,
                    mountPoint: mountPoint,
                    dmgPath: dmgPath
                )

            } catch {
                await MainActor.run {
                    self.isDownloading = false
                    self.isInstalling = false
                    self.updateError = "Install failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Open the release page in a browser (fallback).
    func downloadUpdate() {
        if let url = latestDownloadURL ?? latestReleaseURL {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private Helpers

    private func downloadDMG(from url: URL) async throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let dmgPath = tempDir.appendingPathComponent("QuinnVoice-update.dmg")

        // Remove old download
        try? FileManager.default.removeItem(at: dmgPath)

        // Stream download with progress
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        let totalBytes = response.expectedContentLength
        var downloadedBytes: Int64 = 0
        var data = Data()

        for try await byte in asyncBytes {
            data.append(byte)
            downloadedBytes += 1
            if totalBytes > 0 && downloadedBytes % 65536 == 0 {
                let progress = Double(downloadedBytes) / Double(totalBytes)
                await MainActor.run { self.downloadProgress = progress }
            }
        }

        try data.write(to: dmgPath)
        await MainActor.run { self.downloadProgress = 1.0 }
        return dmgPath.path
    }

    private func mountDMG(at path: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", path, "-nobrowse", "-readonly", "-mountpoint", "/tmp/QuinnVoice-update"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UpdateError.dmgMountFailed
        }

        return "/tmp/QuinnVoice-update"
    }

    private func findApp(in mountPoint: String) throws -> String {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(atPath: mountPoint)
        guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
            throw UpdateError.appNotFoundInDMG
        }
        return (mountPoint as NSString).appendingPathComponent(appName)
    }

    private func currentAppBundlePath() -> String? {
        let bundlePath = Bundle.main.bundlePath
        // Verify it's a .app bundle
        guard bundlePath.hasSuffix(".app") else { return nil }
        return bundlePath
    }

    private nonisolated func replaceAndRelaunch(
        newApp: String,
        currentApp: String,
        mountPoint: String,
        dmgPath: String
    ) async throws {
        // Write a shell script that:
        // 1. Waits for the app to quit
        // 2. Copies the new app over the old one
        // 3. Unmounts the DMG
        // 4. Cleans up
        // 5. Relaunches the app
        let script = """
        #!/bin/bash
        # Wait for app to quit (up to 10 seconds)
        for i in $(seq 1 20); do
            if ! pgrep -x "QuinnVoice" > /dev/null 2>&1; then
                break
            fi
            sleep 0.5
        done

        # Remove old app
        rm -rf "\(currentApp)"

        # Copy new app
        cp -R "\(newApp)" "\(currentApp)"

        # Unmount DMG
        hdiutil detach "\(mountPoint)" -quiet 2>/dev/null

        # Clean up DMG
        rm -f "\(dmgPath)"

        # Relaunch
        open "\(currentApp)"

        # Self-destruct
        rm -f /tmp/quinnvoice-update.sh
        """

        let scriptPath = "/tmp/quinnvoice-update.sh"
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        // Make executable
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", scriptPath]
        try chmod.run()
        chmod.waitUntilExit()

        // Launch the update script in background
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
        launcher.arguments = [scriptPath]
        try launcher.run()

        // Quit the app
        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Version Comparison

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

    // MARK: - Errors

    enum UpdateError: LocalizedError {
        case dmgMountFailed
        case appNotFoundInDMG
        case cannotLocateCurrentApp

        var errorDescription: String? {
            switch self {
            case .dmgMountFailed: return "Failed to mount the update DMG"
            case .appNotFoundInDMG: return "No app found in the update DMG"
            case .cannotLocateCurrentApp: return "Cannot locate the current app bundle"
            }
        }
    }
}
