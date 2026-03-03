import Foundation
import Security

// MARK: - Keychain Helper

/// Secure storage for sensitive values using the macOS Keychain.
enum KeychainHelper {

    private static let service = "com.quinnvoice.app"

    /// Save a string value to the Keychain.
    /// - Parameters:
    ///   - value: The string to store.
    ///   - account: The key/account name for this entry.
    @discardableResult
    static func save(_ value: String, forAccount account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Don't store empty strings
        guard !value.isEmpty else { return true }

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve a string value from the Keychain.
    /// - Parameter account: The key/account name for this entry.
    /// - Returns: The stored string, or nil if not found.
    static func load(forAccount account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    /// Delete a value from the Keychain.
    /// - Parameter account: The key/account name to delete.
    @discardableResult
    static func delete(forAccount account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - App Configuration

/// Persistent configuration stored in ~/Library/Application Support/QuinnVoice/config.json.
/// Sensitive values (API keys) are stored in the macOS Keychain, not in the JSON file.
struct AppConfig: Codable, Sendable {
    /// Gemini API key — stored in Keychain, excluded from JSON serialization
    var geminiApiKey: String
    var geminiModel: String
    var openclawUrl: String
    var voiceConfig: VoiceConfig
    var continuousMode: Bool
    var showTranscript: Bool

    // MARK: - Hotkey Configuration

    /// Whether the global hotkey (⌥Space) is enabled.
    var hotkeyEnabled: Bool

    /// The hotkey behavior mode (hold-to-talk vs toggle).
    var hotkeyMode: HotkeyMode

    // MARK: - Screen Context Configuration

    /// Whether to include the frontmost app and window title in Gemini context.
    var includeScreenContext: Bool

    // MARK: - Clipboard Configuration

    /// Whether Gemini can access the clipboard via `get_clipboard` / `set_clipboard` tools.
    var clipboardAccess: Bool

    // MARK: - Wake Word Configuration

    /// Whether always-on "Hey Quinn" wake word detection is enabled.
    var wakeWordEnabled: Bool

    /// The wake phrase to listen for (e.g., "Hey Quinn").
    var wakePhrase: String

    // MARK: - Notification Configuration

    /// Whether to surface tool results as macOS notifications.
    var notificationsEnabled: Bool

    // MARK: - AI Model Configuration

    /// Preferred model selection: auto, flash, or pro.
    var preferredModel: ModelPreference

    /// Whether to use context caching for system prompts.
    var contextCachingEnabled: Bool

    // MARK: - Agent / Computer Use Configuration

    /// Whether the autonomous agent mode is enabled.
    var agentModeEnabled: Bool

    /// Maximum number of observe-act iterations before the agent stops.
    var agentMaxIterations: Int

    /// Whether to pause and confirm before executing destructive commands.
    var agentConfirmDestructive: Bool

    /// Applications the agent is allowed to interact with.
    var agentAllowedApps: [String]

    /// Whether the API key has been configured
    var isConfigured: Bool { !geminiApiKey.isEmpty }

    // Exclude geminiApiKey from JSON serialization — it lives in Keychain
    enum CodingKeys: String, CodingKey {
        case geminiModel, openclawUrl, voiceConfig, continuousMode, showTranscript
        case hotkeyEnabled, hotkeyMode, includeScreenContext, clipboardAccess
        case wakeWordEnabled, wakePhrase, notificationsEnabled
        case preferredModel, contextCachingEnabled
        case agentModeEnabled, agentMaxIterations, agentConfirmDestructive, agentAllowedApps
    }

    init(geminiApiKey: String = "",
         geminiModel: String = "gemini-live-2.5-flash-native-audio",
         openclawUrl: String = "http://127.0.0.1:18789",
         voiceConfig: VoiceConfig = .default,
         continuousMode: Bool = true,
         showTranscript: Bool = false,
         hotkeyEnabled: Bool = true,
         hotkeyMode: HotkeyMode = .hold,
         includeScreenContext: Bool = true,
         clipboardAccess: Bool = true,
         wakeWordEnabled: Bool = false,
         wakePhrase: String = "Hey Quinn",
         notificationsEnabled: Bool = true,
         preferredModel: ModelPreference = .auto,
         contextCachingEnabled: Bool = true,
         agentModeEnabled: Bool = true,
         agentMaxIterations: Int = 20,
         agentConfirmDestructive: Bool = true,
         agentAllowedApps: [String] = ["Terminal", "iTerm2", "Xcode", "Visual Studio Code", "Safari", "Finder"]) {
        self.geminiApiKey = geminiApiKey
        self.geminiModel = geminiModel
        self.openclawUrl = openclawUrl
        self.voiceConfig = voiceConfig
        self.continuousMode = continuousMode
        self.showTranscript = showTranscript
        self.hotkeyEnabled = hotkeyEnabled
        self.hotkeyMode = hotkeyMode
        self.includeScreenContext = includeScreenContext
        self.clipboardAccess = clipboardAccess
        self.wakeWordEnabled = wakeWordEnabled
        self.wakePhrase = wakePhrase
        self.notificationsEnabled = notificationsEnabled
        self.preferredModel = preferredModel
        self.contextCachingEnabled = contextCachingEnabled
        self.agentModeEnabled = agentModeEnabled
        self.agentMaxIterations = agentMaxIterations
        self.agentConfirmDestructive = agentConfirmDestructive
        self.agentAllowedApps = agentAllowedApps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.geminiApiKey = "" // Loaded separately from Keychain
        self.geminiModel = try container.decode(String.self, forKey: .geminiModel)
        self.openclawUrl = try container.decode(String.self, forKey: .openclawUrl)
        self.voiceConfig = try container.decode(VoiceConfig.self, forKey: .voiceConfig)
        self.continuousMode = try container.decode(Bool.self, forKey: .continuousMode)
        self.showTranscript = try container.decode(Bool.self, forKey: .showTranscript)
        self.hotkeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .hotkeyEnabled) ?? true
        self.hotkeyMode = try container.decodeIfPresent(HotkeyMode.self, forKey: .hotkeyMode) ?? .hold
        self.includeScreenContext = try container.decodeIfPresent(Bool.self, forKey: .includeScreenContext) ?? true
        self.clipboardAccess = try container.decodeIfPresent(Bool.self, forKey: .clipboardAccess) ?? true
        self.wakeWordEnabled = try container.decodeIfPresent(Bool.self, forKey: .wakeWordEnabled) ?? false
        self.wakePhrase = try container.decodeIfPresent(String.self, forKey: .wakePhrase) ?? "Hey Quinn"
        self.notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        self.preferredModel = try container.decodeIfPresent(ModelPreference.self, forKey: .preferredModel) ?? .auto
        self.contextCachingEnabled = try container.decodeIfPresent(Bool.self, forKey: .contextCachingEnabled) ?? true
        self.agentModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .agentModeEnabled) ?? true
        self.agentMaxIterations = try container.decodeIfPresent(Int.self, forKey: .agentMaxIterations) ?? 20
        self.agentConfirmDestructive = try container.decodeIfPresent(Bool.self, forKey: .agentConfirmDestructive) ?? true
        self.agentAllowedApps = try container.decodeIfPresent([String].self, forKey: .agentAllowedApps) ?? ["Terminal", "iTerm2", "Xcode", "Visual Studio Code", "Safari", "Finder"]
    }

    static let `default` = AppConfig()
}

// MARK: - Config Manager

@Observable
@MainActor
final class ConfigManager {
    var config: AppConfig

    private static let keychainAccountGemini = "gemini-api-key"
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("QuinnVoice", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("config.json")
        self.config = .default

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Load config from disk
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            self.config = loaded
        }

        // Load API key from Keychain (never from JSON)
        if let key = KeychainHelper.load(forAccount: Self.keychainAccountGemini) {
            self.config.geminiApiKey = key
        }
    }

    /// Save configuration to disk (JSON) and API key to Keychain.
    func save() {
        // Save API key to Keychain
        KeychainHelper.save(config.geminiApiKey, forAccount: Self.keychainAccountGemini)

        // Save non-sensitive config to JSON (API key excluded via CodingKeys)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Reload configuration from disk and Keychain.
    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = loaded
        }
        if let key = KeychainHelper.load(forAccount: Self.keychainAccountGemini) {
            config.geminiApiKey = key
        }
    }
}
