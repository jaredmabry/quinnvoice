import SwiftUI

/// Settings view for managing application updates via GitHub Releases.
struct UpdateSettingsView: View {
    @Bindable var updateManager: UpdateManager
    @Bindable var configManager: ConfigManager

    var body: some View {
        Form {
            Section("Current Version") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("QuinnVoice \(updateManager.currentVersion)")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Build \(updateManager.currentBuild)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if updateManager.updateAvailable, let latest = updateManager.latestVersion {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("v\(latest) available")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.green)
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.green)
                        }
                    } else if updateManager.lastCheckDate != nil {
                        Text("Up to date ✓")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Section("Update Check") {
                Button {
                    updateManager.checkForUpdates()
                } label: {
                    HStack {
                        if updateManager.isChecking {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking…")
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Check for Updates")
                        }
                    }
                }
                .disabled(updateManager.isChecking)

                if let lastCheck = updateManager.lastCheckDate ?? configManager.config.lastUpdateCheck {
                    HStack {
                        Text("Last checked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(lastCheck, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Automatically check for updates", isOn: $configManager.config.autoCheckUpdates)
                    .onChange(of: configManager.config.autoCheckUpdates) { _, newValue in
                        updateManager.automaticallyChecksForUpdates = newValue
                        configManager.save()
                    }
            } header: {
                Text("Preferences")
            } footer: {
                Text("When enabled, QuinnVoice checks GitHub Releases for new versions on launch.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if updateManager.updateAvailable, let latest = updateManager.latestVersion {
                Section("Available Update") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("QuinnVoice \(latest)")
                                .font(.body)
                                .fontWeight(.medium)
                            if updateManager.latestDownloadURL != nil {
                                Text("DMG ready to download")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("View release on GitHub")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button {
                            updateManager.downloadUpdate()
                        } label: {
                            Label(
                                updateManager.latestDownloadURL != nil ? "Download" : "View Release",
                                systemImage: "arrow.down.circle.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
