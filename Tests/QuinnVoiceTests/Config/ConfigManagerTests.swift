/// ConfigManagerTests.swift — Comprehensive tests for AppConfig, KeychainHelper, and ConfigManager.

import XCTest

@testable import QuinnVoice

@MainActor
final class ConfigManagerTests: XCTestCase {

    // MARK: - AppConfig Default Values (ALL fields)

    func testDefaultConfig_hasEmptyApiKey() {
        XCTAssertEqual(AppConfig.default.geminiApiKey, "")
    }

    func testDefaultConfig_hasExpectedModel() {
        XCTAssertEqual(AppConfig.default.geminiModel, "gemini-live-2.5-flash-native-audio")
    }

    func testDefaultConfig_hasLocalOpenClawUrl() {
        XCTAssertEqual(AppConfig.default.openclawUrl, "http://127.0.0.1:18789")
    }

    func testDefaultConfig_hasDefaultVoice() {
        XCTAssertEqual(AppConfig.default.voiceConfig.name, "Kore")
        XCTAssertEqual(AppConfig.default.voiceConfig.pitch, 0)
        XCTAssertEqual(AppConfig.default.voiceConfig.speed, 1.0)
    }

    func testDefaultConfig_continuousModeIsOn() {
        XCTAssertTrue(AppConfig.default.continuousMode)
    }

    func testDefaultConfig_showTranscriptIsOff() {
        XCTAssertFalse(AppConfig.default.showTranscript)
    }

    func testDefaultConfig_hotkeyEnabled() {
        XCTAssertTrue(AppConfig.default.hotkeyEnabled)
    }

    func testDefaultConfig_hotkeyModeIsHold() {
        XCTAssertEqual(AppConfig.default.hotkeyMode, .hold)
    }

    func testDefaultConfig_includeScreenContextIsTrue() {
        XCTAssertTrue(AppConfig.default.includeScreenContext)
    }

    func testDefaultConfig_clipboardAccessIsTrue() {
        XCTAssertTrue(AppConfig.default.clipboardAccess)
    }

    func testDefaultConfig_wakeWordDisabled() {
        XCTAssertFalse(AppConfig.default.wakeWordEnabled)
    }

    func testDefaultConfig_wakePhrase() {
        XCTAssertEqual(AppConfig.default.wakePhrase, "Hey Quinn")
    }

    func testDefaultConfig_notificationsEnabled() {
        XCTAssertTrue(AppConfig.default.notificationsEnabled)
    }

    func testDefaultConfig_preferredModelIsAuto() {
        XCTAssertEqual(AppConfig.default.preferredModel, .auto)
    }

    func testDefaultConfig_contextCachingEnabled() {
        XCTAssertTrue(AppConfig.default.contextCachingEnabled)
    }

    func testDefaultConfig_agentModeEnabled() {
        XCTAssertTrue(AppConfig.default.agentModeEnabled)
    }

    func testDefaultConfig_agentMaxIterations() {
        XCTAssertEqual(AppConfig.default.agentMaxIterations, 20)
    }

    func testDefaultConfig_agentConfirmDestructive() {
        XCTAssertTrue(AppConfig.default.agentConfirmDestructive)
    }

    func testDefaultConfig_agentAllowedApps() {
        let expected = ["Terminal", "iTerm2", "Xcode", "Visual Studio Code", "Safari", "Finder"]
        XCTAssertEqual(AppConfig.default.agentAllowedApps, expected)
    }

    func testDefaultConfig_isNotConfigured() {
        XCTAssertFalse(AppConfig.default.isConfigured)
    }

    func testIsConfigured_trueWhenApiKeyPresent() {
        var config = AppConfig.default
        config.geminiApiKey = "AIzaSyFakeKey123"
        XCTAssertTrue(config.isConfigured)
    }

    // MARK: - Codable Round-Trip (JSON serialization)

    func testAppConfig_codableRoundTrip() throws {
        var original = AppConfig.default
        original.geminiModel = "gemini-2.0-flash-live-001"
        original.openclawUrl = "http://192.168.1.100:18789"
        original.voiceConfig = VoiceConfig(name: "Puck", pitch: 0.3, speed: 1.2)
        original.continuousMode = false
        original.showTranscript = true
        original.preferredModel = .pro
        original.contextCachingEnabled = false
        original.agentMaxIterations = 30

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        // geminiApiKey excluded from JSON, always decoded as ""
        XCTAssertEqual(decoded.geminiApiKey, "")
        XCTAssertEqual(decoded.geminiModel, "gemini-2.0-flash-live-001")
        XCTAssertEqual(decoded.openclawUrl, "http://192.168.1.100:18789")
        XCTAssertEqual(decoded.voiceConfig.name, "Puck")
        XCTAssertFalse(decoded.continuousMode)
        XCTAssertTrue(decoded.showTranscript)
        XCTAssertEqual(decoded.preferredModel, .pro)
        XCTAssertFalse(decoded.contextCachingEnabled)
        XCTAssertEqual(decoded.agentMaxIterations, 30)
    }

    // MARK: - geminiApiKey NOT in JSON

    func testGeminiApiKey_excludedFromJson() throws {
        var config = AppConfig.default
        config.geminiApiKey = "super-secret-key"

        let data = try JSONEncoder().encode(config)
        let jsonString = String(data: data, encoding: .utf8)!

        XCTAssertFalse(jsonString.contains("super-secret-key"),
                       "API key must not appear in JSON output")
        XCTAssertFalse(jsonString.contains("geminiApiKey"),
                       "geminiApiKey key must not appear in JSON output")
    }

    func testGeminiApiKey_decodedAsEmptyFromJson() throws {
        let data = try JSONEncoder().encode(AppConfig.default)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.geminiApiKey, "",
                       "Decoded API key should always be empty (loaded from Keychain)")
    }

    // MARK: - Backward Compatibility

    func testBackwardCompatibility_oldConfigWithoutNewFields() throws {
        // JSON without preferredModel, contextCachingEnabled
        let oldJson = """
        {
            "geminiModel": "gemini-2.0-flash-live-001",
            "openclawUrl": "http://127.0.0.1:18789",
            "voiceConfig": {"name": "Kore", "pitch": 0, "speed": 1.0},
            "continuousMode": true,
            "showTranscript": false
        }
        """
        let data = oldJson.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        // New fields should use defaults
        XCTAssertEqual(decoded.preferredModel, .auto)
        XCTAssertTrue(decoded.contextCachingEnabled)
        XCTAssertTrue(decoded.hotkeyEnabled)
        XCTAssertEqual(decoded.hotkeyMode, .hold)
        XCTAssertTrue(decoded.includeScreenContext)
        XCTAssertTrue(decoded.clipboardAccess)
        XCTAssertFalse(decoded.wakeWordEnabled)
        XCTAssertEqual(decoded.wakePhrase, "Hey Quinn")
        XCTAssertTrue(decoded.notificationsEnabled)
        XCTAssertTrue(decoded.agentModeEnabled)
        XCTAssertEqual(decoded.agentMaxIterations, 20)
        XCTAssertTrue(decoded.agentConfirmDestructive)
    }

    // MARK: - File-Based Save/Load

    func testSaveAndLoad_roundTrip() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuinnVoiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = tmpDir.appendingPathComponent("config.json")

        var config = AppConfig.default
        config.voiceConfig.name = "Fenrir"
        config.preferredModel = .flash
        config.contextCachingEnabled = false

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)

        let loadedData = try Data(contentsOf: fileURL)
        let loaded = try JSONDecoder().decode(AppConfig.self, from: loadedData)

        XCTAssertEqual(loaded.voiceConfig.name, "Fenrir")
        XCTAssertEqual(loaded.preferredModel, .flash)
        XCTAssertFalse(loaded.contextCachingEnabled)
    }

    // MARK: - Config Manager Init

    func testConfigManager_defaultInit_loadsDefaultConfig() {
        let manager = ConfigManager()
        XCTAssertNotNil(manager.config)
        XCTAssertEqual(manager.config.geminiModel, AppConfig.default.geminiModel)
    }

    // MARK: - Missing/Corrupt Config

    func testCorruptJson_decodeFails_gracefully() {
        let data = "{ not valid json at all }".data(using: .utf8)!
        XCTAssertNil(try? JSONDecoder().decode(AppConfig.self, from: data))
    }

    func testEmptyFile_decodeFails() {
        XCTAssertNil(try? JSONDecoder().decode(AppConfig.self, from: Data()))
    }

    // MARK: - JSON Format

    func testAppConfig_jsonOutputIsSorted() throws {
        let config = AppConfig.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        let jsonString = String(data: data, encoding: .utf8)!

        let continuousIdx = jsonString.range(of: "continuousMode")!.lowerBound
        let geminiIdx = jsonString.range(of: "geminiModel")!.lowerBound
        let openclawIdx = jsonString.range(of: "openclawUrl")!.lowerBound

        XCTAssertLessThan(continuousIdx, geminiIdx)
        XCTAssertLessThan(geminiIdx, openclawIdx)
    }

    // MARK: - ModelPreference

    func testModelPreference_allCases() {
        XCTAssertEqual(ModelPreference.allCases.count, 3)
        XCTAssertTrue(ModelPreference.allCases.contains(.auto))
        XCTAssertTrue(ModelPreference.allCases.contains(.flash))
        XCTAssertTrue(ModelPreference.allCases.contains(.pro))
    }

    func testModelPreference_displayNames() {
        XCTAssertFalse(ModelPreference.auto.displayName.isEmpty)
        XCTAssertFalse(ModelPreference.flash.displayName.isEmpty)
        XCTAssertFalse(ModelPreference.pro.displayName.isEmpty)
    }

    func testModelPreference_codableRoundTrip() throws {
        for pref in ModelPreference.allCases {
            let data = try JSONEncoder().encode(pref)
            let decoded = try JSONDecoder().decode(ModelPreference.self, from: data)
            XCTAssertEqual(decoded, pref)
        }
    }
}
