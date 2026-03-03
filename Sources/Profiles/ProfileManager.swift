import Foundation

// MARK: - Profile Model

/// A named personality profile containing soul text, memory, voice config, and visual identity.
struct Profile: Codable, Sendable, Identifiable {
    /// Unique identifier for this profile.
    let id: UUID

    /// Display name for the profile.
    var name: String

    /// The soul/personality prompt text for this profile.
    var soulText: String

    /// The memory content for this profile.
    var memoryText: String

    /// Voice configuration (voice name, pitch, speed) for this profile.
    var voiceConfig: VoiceConfig

    /// Whether this profile is currently active.
    var isActive: Bool

    /// When this profile was created.
    let createdAt: Date

    /// SF Symbol name used as the profile icon.
    var icon: String

    init(
        id: UUID = UUID(),
        name: String,
        soulText: String = "",
        memoryText: String = "",
        voiceConfig: VoiceConfig = .default,
        isActive: Bool = false,
        createdAt: Date = Date(),
        icon: String = "person.fill"
    ) {
        self.id = id
        self.name = name
        self.soulText = soulText
        self.memoryText = memoryText
        self.voiceConfig = voiceConfig
        self.isActive = isActive
        self.createdAt = createdAt
        self.icon = icon
    }
}

// MARK: - Profile Manager

/// Manages multiple personality profiles with iCloud sync and local fallback.
///
/// Each profile stores its own soul text, memory, voice configuration, and icon.
/// Only one profile can be active at a time. Switching profiles updates the
/// active ConfigManager settings.
@Observable
@MainActor
final class ProfileManager {

    // MARK: - Public State

    /// All available profiles.
    var profiles: [Profile] = []

    /// The currently active profile, if any.
    var activeProfile: Profile? {
        profiles.first { $0.isActive }
    }

    // MARK: - Private

    private let containerIdentifier = "iCloud.com.mabryventures.quinnvoice"
    private let profilesDirectoryName = "profiles"
    private var iCloudURL: URL?
    private var localURL: URL
    private var metadataQuery: NSMetadataQuery?

    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("QuinnVoice", isDirectory: true)
            .appendingPathComponent("profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.localURL = dir
        setupiCloud()
        loadAll()
        createDefaultProfilesIfNeeded()
        startMonitoring()
    }

    // MARK: - iCloud Setup

    private func setupiCloud() {
        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) {
            let profilesURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(profilesDirectoryName, isDirectory: true)
            try? FileManager.default.createDirectory(at: profilesURL, withIntermediateDirectories: true)
            iCloudURL = profilesURL
        }
    }

    /// The directory used for reading and writing profile files.
    private var activeURL: URL {
        iCloudURL ?? localURL
    }

    // MARK: - Profile Management

    /// Create a new profile with the given name and icon.
    @discardableResult
    func createProfile(name: String, icon: String = "person.fill") -> Profile {
        let profile = Profile(name: name, icon: icon)
        profiles.append(profile)
        saveProfile(profile)
        return profile
    }

    /// Delete a profile by ID. Cannot delete the last remaining profile.
    func deleteProfile(_ id: UUID) {
        guard profiles.count > 1 else { return }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }

        let wasActive = profiles[index].isActive
        let profile = profiles.remove(at: index)

        // Remove file
        let fileURL = activeURL.appendingPathComponent("\(profile.id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)

        // If we deleted the active profile, activate the first one
        if wasActive, !profiles.isEmpty {
            profiles[0].isActive = true
            saveProfile(profiles[0])
        }
    }

    /// Switch to a different profile by ID.
    func switchTo(_ id: UUID) {
        // Deactivate all profiles
        for i in profiles.indices {
            if profiles[i].isActive {
                profiles[i].isActive = false
                saveProfile(profiles[i])
            }
        }

        // Activate the selected profile
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            profiles[index].isActive = true
            saveProfile(profiles[index])
        }
    }

    /// Duplicate a profile, creating a copy with "(Copy)" appended to the name.
    @discardableResult
    func duplicateProfile(_ id: UUID) -> Profile? {
        guard let original = profiles.first(where: { $0.id == id }) else { return nil }

        let copy = Profile(
            name: "\(original.name) (Copy)",
            soulText: original.soulText,
            memoryText: original.memoryText,
            voiceConfig: original.voiceConfig,
            isActive: false,
            icon: original.icon
        )
        profiles.append(copy)
        saveProfile(copy)
        return copy
    }

    /// Update a profile's properties and save.
    func updateProfile(_ profile: Profile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        saveProfile(profile)
    }

    // MARK: - Persistence

    /// Load all profile files from disk.
    func loadAll() {
        let url = activeURL
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        var loaded: [Profile] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let profile = try? jsonDecoder.decode(Profile.self, from: data) {
                loaded.append(profile)
            }
        }

        profiles = loaded.sorted { $0.createdAt < $1.createdAt }
    }

    /// Save a single profile to its JSON file.
    private func saveProfile(_ profile: Profile) {
        let fileURL = activeURL.appendingPathComponent("\(profile.id.uuidString).json")
        guard let data = try? jsonEncoder.encode(profile) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Create default profiles on first launch if none exist.
    private func createDefaultProfilesIfNeeded() {
        guard profiles.isEmpty else { return }

        let personal = Profile(
            name: "Personal",
            soulText: "",
            memoryText: "",
            voiceConfig: .default,
            isActive: true,
            icon: "person.fill"
        )
        profiles.append(personal)
        saveProfile(personal)

        let work = Profile(
            name: "Work",
            soulText: "",
            memoryText: "",
            voiceConfig: .default,
            isActive: false,
            icon: "briefcase.fill"
        )
        profiles.append(work)
        saveProfile(work)
    }

    // MARK: - iCloud Monitoring

    private func startMonitoring() {
        guard iCloudURL != nil else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K ENDSWITH '.json' AND %K CONTAINS 'profiles'",
                                       NSMetadataItemFSNameKey, NSMetadataItemPathKey)

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadAll()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadAll()
            }
        }

        query.start()
        self.metadataQuery = query
    }

}

// MARK: - Available Profile Icons

/// The set of SF Symbol names available for profile icons.
let profileIconChoices: [String] = [
    "person.fill",
    "briefcase.fill",
    "house.fill",
    "star.fill",
    "heart.fill",
    "brain.head.profile",
    "graduationcap.fill",
    "gamecontroller.fill",
    "wrench.fill",
    "leaf.fill",
    "book.fill",
    "music.note",
    "paintbrush.fill",
    "camera.fill",
    "airplane",
    "cart.fill",
    "stethoscope",
    "building.2.fill",
    "trophy.fill",
    "globe"
]
