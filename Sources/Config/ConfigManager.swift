import Foundation
import Security

// MARK: - Keychain Helper

/// Secure storage for sensitive values using the macOS Keychain.
enum KeychainHelper {

    private static let service = "com.quinnvoice.app"

    /// Save a string value to the Keychain.
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

// MARK: - Soul Source

/// How the soul/personality content is provided.
enum SoulSource: String, Codable, Sendable {
    /// Loaded from an imported .md file.
    case file
    /// Written directly in the editor.
    case custom
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

    /// Whether the global hotkey is enabled.
    var hotkeyEnabled: Bool

    /// The hotkey behavior mode (hold-to-talk vs toggle).
    var hotkeyMode: HotkeyMode

    /// The key code for the hotkey (Carbon virtual key code). Default: 49 (Space).
    var hotkeyKeyCode: UInt16

    /// The modifier flags for the hotkey. Default: Option key.
    var hotkeyModifiers: UInt

    // MARK: - Screen Context Configuration

    var includeScreenContext: Bool

    // MARK: - Clipboard Configuration

    var clipboardAccess: Bool

    // MARK: - Wake Word Configuration

    var wakeWordEnabled: Bool
    var wakePhrase: String

    // MARK: - Notification Configuration

    var notificationsEnabled: Bool

    // MARK: - AI Model Configuration

    var preferredModel: ModelPreference
    var contextCachingEnabled: Bool

    // MARK: - Agent / Computer Use Configuration

    var agentModeEnabled: Bool
    var agentMaxIterations: Int
    var agentConfirmDestructive: Bool
    var agentAllowedApps: [String]

    // MARK: - Soul / Personality Configuration

    /// How the soul content is sourced.
    var soulSource: SoulSource

    /// Custom soul text (when soulSource == .custom).
    var soulText: String

    /// Filename of imported soul file (when soulSource == .file).
    var soulFileName: String

    // MARK: - Update Configuration

    /// Whether to automatically check for updates on launch.
    var autoCheckUpdates: Bool

    /// The last time an update check was performed.
    var lastUpdateCheck: Date?

    // MARK: - Appearance Configuration

    /// The app color scheme preference.
    var theme: AppTheme

    /// The accent color for the app UI.
    var accentColor: AccentColorChoice

    /// The waveform animation style.
    var waveformStyle: WaveformStyle

    /// The voice panel background opacity (0.5–1.0).
    var panelOpacity: Double

    /// Whether to reduce animations (manual override).
    var reduceAnimations: Bool

    // MARK: - Audio Processing Configuration

    /// Audio input processing settings (noise suppression, VAD, etc.).
    var audioProcessing: AudioProcessingConfig

    /// Whether the API key has been configured
    var isConfigured: Bool { !geminiApiKey.isEmpty }

    // Exclude geminiApiKey from JSON serialization — it lives in Keychain
    enum CodingKeys: String, CodingKey {
        case geminiModel, openclawUrl, voiceConfig, continuousMode, showTranscript
        case hotkeyEnabled, hotkeyMode, hotkeyKeyCode, hotkeyModifiers
        case includeScreenContext, clipboardAccess
        case wakeWordEnabled, wakePhrase, notificationsEnabled
        case preferredModel, contextCachingEnabled
        case agentModeEnabled, agentMaxIterations, agentConfirmDestructive, agentAllowedApps
        case soulSource, soulText, soulFileName
        case autoCheckUpdates, lastUpdateCheck
        case theme, accentColor, waveformStyle, panelOpacity, reduceAnimations
        case audioProcessing
    }

    /// Default Option key modifier value (NSEvent.ModifierFlags.option.rawValue).
    static let defaultOptionModifier: UInt = 524288 // NSEvent.ModifierFlags.option.rawValue

    init(geminiApiKey: String = "",
         geminiModel: String = "gemini-live-2.5-flash-native-audio",
         openclawUrl: String = "http://127.0.0.1:18789",
         voiceConfig: VoiceConfig = .default,
         continuousMode: Bool = true,
         showTranscript: Bool = false,
         hotkeyEnabled: Bool = true,
         hotkeyMode: HotkeyMode = .hold,
         hotkeyKeyCode: UInt16 = 49,
         hotkeyModifiers: UInt = defaultOptionModifier,
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
         agentAllowedApps: [String] = ["Terminal", "iTerm2", "Xcode", "Visual Studio Code", "Safari", "Finder"],
         soulSource: SoulSource = .custom,
         soulText: String = "",
         soulFileName: String = "",
         autoCheckUpdates: Bool = true,
         lastUpdateCheck: Date? = nil,
         theme: AppTheme = .system,
         accentColor: AccentColorChoice = .system,
         waveformStyle: WaveformStyle = .subtle,
         panelOpacity: Double = 0.9,
         reduceAnimations: Bool = false,
         audioProcessing: AudioProcessingConfig = .default) {
        self.geminiApiKey = geminiApiKey
        self.geminiModel = geminiModel
        self.openclawUrl = openclawUrl
        self.voiceConfig = voiceConfig
        self.continuousMode = continuousMode
        self.showTranscript = showTranscript
        self.hotkeyEnabled = hotkeyEnabled
        self.hotkeyMode = hotkeyMode
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
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
        self.soulSource = soulSource
        self.soulText = soulText
        self.soulFileName = soulFileName
        self.autoCheckUpdates = autoCheckUpdates
        self.lastUpdateCheck = lastUpdateCheck
        self.theme = theme
        self.accentColor = accentColor
        self.waveformStyle = waveformStyle
        self.panelOpacity = panelOpacity
        self.reduceAnimations = reduceAnimations
        self.audioProcessing = audioProcessing
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
        self.hotkeyKeyCode = try container.decodeIfPresent(UInt16.self, forKey: .hotkeyKeyCode) ?? 49
        self.hotkeyModifiers = try container.decodeIfPresent(UInt.self, forKey: .hotkeyModifiers) ?? AppConfig.defaultOptionModifier
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
        self.soulSource = try container.decodeIfPresent(SoulSource.self, forKey: .soulSource) ?? .custom
        self.soulText = try container.decodeIfPresent(String.self, forKey: .soulText) ?? ""
        self.soulFileName = try container.decodeIfPresent(String.self, forKey: .soulFileName) ?? ""
        self.autoCheckUpdates = try container.decodeIfPresent(Bool.self, forKey: .autoCheckUpdates) ?? true
        self.lastUpdateCheck = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
        self.theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
        self.accentColor = try container.decodeIfPresent(AccentColorChoice.self, forKey: .accentColor) ?? .system
        self.waveformStyle = try container.decodeIfPresent(WaveformStyle.self, forKey: .waveformStyle) ?? .subtle
        self.panelOpacity = try container.decodeIfPresent(Double.self, forKey: .panelOpacity) ?? 0.9
        self.reduceAnimations = try container.decodeIfPresent(Bool.self, forKey: .reduceAnimations) ?? false
        self.audioProcessing = try container.decodeIfPresent(AudioProcessingConfig.self, forKey: .audioProcessing) ?? .default
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
