import SwiftUI

/// A sheet for creating or editing a profile.
///
/// Includes fields for name, icon selection, soul/personality text,
/// and voice configuration.
struct ProfileEditorView: View {
    @Bindable var profileManager: ProfileManager
    let existingProfile: Profile?
    var onSave: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var icon: String = "person.fill"
    @State private var soulText: String = ""
    @State private var voiceName: String = VoiceConfig.default.name

    private var isEditing: Bool { existingProfile != nil }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text(isEditing ? "Edit Profile" : "New Profile")
                    .font(.headline)

                Spacer()

                Button("Save") {
                    saveProfile()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        TextField("Profile name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Icon picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Icon")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: iconColumns, spacing: 8) {
                            ForEach(profileIconChoices, id: \.self) { symbolName in
                                IconPickerButton(
                                    symbolName: symbolName,
                                    isSelected: icon == symbolName
                                ) {
                                    icon = symbolName
                                }
                            }
                        }
                    }

                    // Soul/personality
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Personality / Soul")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $soulText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 150)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.08))
                            )

                        Text("Write a system prompt or personality description for this profile.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    // Voice picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Voice")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        Picker("Voice", selection: $voiceName) {
                            ForEach(VoiceConfig.availableVoices, id: \.self) { voice in
                                Text(voice).tag(voice)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 450, height: 550)
        .onAppear {
            if let profile = existingProfile {
                name = profile.name
                icon = profile.icon
                soulText = profile.soulText
                voiceName = profile.voiceConfig.name
            }
        }
    }

    // MARK: - Save

    private func saveProfile() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if var existing = existingProfile {
            existing.name = trimmedName
            existing.icon = icon
            existing.soulText = soulText
            existing.voiceConfig.name = voiceName
            profileManager.updateProfile(existing)
        } else {
            var newProfile = profileManager.createProfile(name: trimmedName, icon: icon)
            newProfile.soulText = soulText
            newProfile.voiceConfig.name = voiceName
            profileManager.updateProfile(newProfile)
        }

        onSave?()
    }
}

// MARK: - Icon Picker Button

/// A single selectable icon in the icon picker grid.
struct IconPickerButton: View {
    let symbolName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}
