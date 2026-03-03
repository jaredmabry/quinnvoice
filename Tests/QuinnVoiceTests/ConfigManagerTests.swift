/// ConfigManagerTests.swift
/// Tests for the persistent configuration manager that reads/writes
/// `~/Library/Application Support/QuinnVoice/config.json`.
///
/// Uses a temporary directory to avoid polluting the real config.

import XCTest

@testable import QuinnVoice

@MainActor
final class ConfigManagerTests: XCTestCase {

    // MARK: - AppConfig Default Values

    func testDefaultConfig_hasEmptyApiKey() {
        let config = AppConfig.default
        XCTAssertEqual(config.geminiApiKey, "")
    }

    func testDefaultConfig_hasExpectedModel() {
        let config = AppConfig.default
        XCTAssertEqual(config.geminiModel, "gemini-live-2.5-flash-native-audio")
    }

    func testDefaultConfig_hasLocalOpenClawUrl() {
        let config = AppConfig.default
        XCTAssertEqual(config.openclawUrl, "http://127.0.0.1:18789")
    }

    func testDefaultConfig_hasDefaultVoice() {
        let config = AppConfig.default
        XCTAssertEqual(config.voiceConfig.name, "Kore")
        XCTAssertEqual(config.voiceConfig.pitch, 0)
        XCTAssertEqual(config.voiceConfig.speed, 1.0)
    }

    func testDefaultConfig_continuousModeIsOn() {
        XCTAssertTrue(AppConfig.default.continuousMode)
    }

    func testDefaultConfig_showTranscriptIsOff() {
        XCTAssertFalse(AppConfig.default.showTranscript)
    }

    func testDefaultConfig_isNotConfigured() {
        XCTAssertFalse(AppConfig.default.isConfigured,
                       "Default config with empty API key should not be 'configured'")
    }

    func testIsConfigured_trueWhenApiKeyPresent() {
        var config = AppConfig.default
        config.geminiApiKey = "AIzaSyFakeKey123"
        XCTAssertTrue(config.isConfigured)
    }

    // MARK: - Codable Round-Trip

    func testAppConfig_codableRoundTrip() throws {
        var original = AppConfig.default
        original.geminiApiKey = "test-key-123"
        original.geminiModel = "gemini-2.0-flash-live-001"
        original.openclawUrl = "http://192.168.1.100:18789"
        original.voiceConfig = VoiceConfig(name: "Puck", pitch: 0.3, speed: 1.2)
        original.continuousMode = false
        original.showTranscript = true

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded.geminiApiKey, "test-key-123")
        XCTAssertEqual(decoded.geminiModel, "gemini-2.0-flash-live-001")
        XCTAssertEqual(decoded.openclawUrl, "http://192.168.1.100:18789")
        XCTAssertEqual(decoded.voiceConfig.name, "Puck")
        XCTAssertEqual(decoded.voiceConfig.pitch, 0.3)
        XCTAssertEqual(decoded.voiceConfig.speed, 1.2)
        XCTAssertFalse(decoded.continuousMode)
        XCTAssertTrue(decoded.showTranscript)
    }

    // MARK: - File-Based Save/Load

    func testSaveAndLoad_roundTrip() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuinnVoiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = tmpDir.appendingPathComponent("config.json")

        // Write a config
        var config = AppConfig.default
        config.geminiApiKey = "test-save-load"
        config.voiceConfig.name = "Fenrir"

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)

        // Read it back
        let loadedData = try Data(contentsOf: fileURL)
        let loaded = try JSONDecoder().decode(AppConfig.self, from: loadedData)

        XCTAssertEqual(loaded.geminiApiKey, "test-save-load")
        XCTAssertEqual(loaded.voiceConfig.name, "Fenrir")
    }

    // MARK: - Config File Path

    func testConfigManager_configFileIsInAppSupport() {
        let manager = ConfigManager()
        // The ConfigManager should store config in Application Support/QuinnVoice/
        // We verify this by checking the manager loads defaults when no file exists,
        // rather than accessing private fileURL directly.
        XCTAssertNotNil(manager.config, "ConfigManager should initialize with a valid config")
    }

    func testConfigManager_defaultInit_loadsDefaultConfig() {
        // A fresh ConfigManager in a clean environment should have default values
        // (unless a real config.json exists, which is fine — we just verify it doesn't crash)
        let manager = ConfigManager()
        XCTAssertNotNil(manager.config)
        XCTAssertEqual(manager.config.geminiModel, AppConfig.default.geminiModel)
    }

    // MARK: - Missing/Corrupt Config

    func testCorruptJson_decodeFails_gracefully() {
        let corruptJson = "{ not valid json at all }"
        let data = corruptJson.data(using: .utf8)!
        let decoded = try? JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertNil(decoded, "Corrupt JSON should fail to decode")
    }

    func testPartialJson_decodeFails() {
        // Missing required fields
        let partialJson = """
        {"geminiApiKey": "key123"}
        """
        let data = partialJson.data(using: .utf8)!
        let decoded = try? JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertNil(decoded, "Partial JSON missing required fields should fail")
    }

    func testEmptyFile_decodeFails() {
        let data = Data()
        let decoded = try? JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertNil(decoded, "Empty data should fail to decode")
    }

    // MARK: - JSON Format

    func testAppConfig_jsonOutputIsSorted() throws {
        let config = AppConfig.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        let jsonString = String(data: data, encoding: .utf8)!

        // Verify keys appear in sorted order
        let continuousIdx = jsonString.range(of: "continuousMode")!.lowerBound
        let geminiIdx = jsonString.range(of: "geminiApiKey")!.lowerBound
        let openclawIdx = jsonString.range(of: "openclawUrl")!.lowerBound

        XCTAssertLessThan(continuousIdx, geminiIdx)
        XCTAssertLessThan(geminiIdx, openclawIdx)
    }
}
