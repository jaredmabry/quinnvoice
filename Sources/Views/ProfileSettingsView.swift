import SwiftUI

/// Settings view for managing personality profiles.
///
/// Displays a grid of profile cards with the active profile highlighted.
/// Supports creating, editing, duplicating, and deleting profiles.
struct ProfileSettingsView: View {
    @Bindable var profileManager: ProfileManager
    @Bindable var configManager: ConfigManager
    @State private var showEditor = false
    @State private var editingProfile: Profile?
    @State private var showDeleteConfirmation = false
    @State private var profileToDelete: UUID?

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header with add button
                    HStack {
                        Text("Profiles")
                            .font(.headline)
                        Spacer()
                        Button {
                            editingProfile = nil
                            showEditor = true
                        } label: {
                            Label("New Profile", systemImage: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    // Profile grid
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(profileManager.profiles) { profile in
                            ProfileCardView(
                                profile: profile,
                                isActive: profile.isActive
                            )
                            .onTapGesture {
                                profileManager.switchTo(profile.id)
                                applyActiveProfile()
                            }
                            .contextMenu {
                                Button {
                                    editingProfile = profile
                                    showEditor = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }

                                Button {
                                    profileManager.duplicateProfile(profile.id)
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    profileToDelete = profile.id
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .disabled(profileManager.profiles.count <= 1)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 16)
            }

            // Footer info
            HStack {
                Text("\(profileManager.profiles.count) profiles")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if let active = profileManager.activeProfile {
                    HStack(spacing: 4) {
                        Image(systemName: active.icon)
                            .font(.caption2)
                        Text("Active: \(active.name)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showEditor) {
            ProfileEditorView(
                profileManager: profileManager,
                existingProfile: editingProfile,
                onSave: { applyActiveProfile() }
            )
        }
        .alert("Delete Profile?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let id = profileToDelete {
                    profileManager.deleteProfile(id)
                    applyActiveProfile()
                }
            }
        } message: {
            Text("This profile and all its settings will be permanently deleted.")
        }
    }

    /// Apply the active profile's settings to ConfigManager.
    private func applyActiveProfile() {
        guard let active = profileManager.activeProfile else { return }
        configManager.config.soulText = active.soulText
        configManager.config.voiceConfig = active.voiceConfig
        configManager.save()
    }
}

// MARK: - Profile Card

/// A card view representing a single profile in the grid.
struct ProfileCardView: View {
    let profile: Profile
    let isActive: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Icon
            Image(systemName: profile.icon)
                .font(.title)
                .foregroundStyle(isActive ? .white : .secondary)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.15))
                )

            // Name
            Text(profile.name)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .lineLimit(1)

            // Active indicator
            if isActive {
                Text("Active")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
            } else {
                Text("Tap to switch")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}
