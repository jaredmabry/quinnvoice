/// VoiceConfigTests.swift
/// Tests for the VoiceConfig model used to configure Gemini Live voice parameters.
///
/// Covers default values, available voice validation, and Codable round-trip encoding/decoding.

import XCTest

@testable import QuinnVoice

final class VoiceConfigTests: XCTestCase {

    // MARK: - Default Values

    func testDefault_hasExpectedValues() {
        let config = VoiceConfig.default
        XCTAssertEqual(config.name, "Kore")
        XCTAssertEqual(config.pitch, 0)
        XCTAssertEqual(config.speed, 1.0)
    }

    // MARK: - Available Voices

    func testAvailableVoices_containsEightVoices() {
        XCTAssertEqual(VoiceConfig.availableVoices.count, 8)
    }

    func testAvailableVoices_containsAoede() {
        XCTAssertTrue(VoiceConfig.availableVoices.contains("Aoede"))
    }

    func testAvailableVoices_containsCharon() {
        XCTAssertTrue(VoiceConfig.availableVoices.contains("Charon"))
    }

    func testAvailableVoices_containsFenrir() {
        XCTAssertTrue(VoiceConfig.availableVoices.contains("Fenrir"))
    }

    func testAvailableVoices_containsKore() {
        XCTAssertTrue(VoiceConfig.availableVoices.contains("Kore"))
    }

    func testAvailableVoices_containsLeda() {
        XCTAssertTrue(VoiceConfig.availableVoices.contains("Leda"))
    }

    func testAvailableVoices_containsOrus() {
        XCTAssertTrue(VoiceConfig.availableVoices.contains("Orus"))
    }

    func testAvailableVoices_containsPuck() {
        XCTAssertTrue(VoiceConfig.availableVoices.contains("Puck"))
    }

    func testAvailableVoices_containsZephyr() {
        XCTAssertTrue(VoiceConfig.availableVoices.contains("Zephyr"))
    }

    func testDefaultVoice_isInAvailableVoices() {
        XCTAssertTrue(
            VoiceConfig.availableVoices.contains(VoiceConfig.default.name),
            "Default voice '\(VoiceConfig.default.name)' should be in the available voices list"
        )
    }

    // MARK: - Codable Round-Trip

    func testCodable_roundTrip_default() throws {
        let original = VoiceConfig.default
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VoiceConfig.self, from: data)

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.pitch, original.pitch)
        XCTAssertEqual(decoded.speed, original.speed)
    }

    func testCodable_roundTrip_customValues() throws {
        let original = VoiceConfig(name: "Puck", pitch: 0.5, speed: 1.5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VoiceConfig.self, from: data)

        XCTAssertEqual(decoded.name, "Puck")
        XCTAssertEqual(decoded.pitch, 0.5)
        XCTAssertEqual(decoded.speed, 1.5)
    }

    func testCodable_roundTrip_negativePitch() throws {
        let original = VoiceConfig(name: "Fenrir", pitch: -1.0, speed: 0.8)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VoiceConfig.self, from: data)

        XCTAssertEqual(decoded.name, "Fenrir")
        XCTAssertEqual(decoded.pitch, -1.0)
        XCTAssertEqual(decoded.speed, 0.8)
    }

    func testCodable_jsonContainsExpectedKeys() throws {
        let config = VoiceConfig(name: "Zephyr", pitch: 0.2, speed: 1.1)
        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json?["name"])
        XCTAssertNotNil(json?["pitch"])
        XCTAssertNotNil(json?["speed"])
        XCTAssertEqual(json?["name"] as? String, "Zephyr")
    }

    func testCodable_decodesFromJson() throws {
        let jsonString = """
        {"name": "Leda", "pitch": 0.3, "speed": 0.9}
        """
        let data = jsonString.data(using: .utf8)!
        let config = try JSONDecoder().decode(VoiceConfig.self, from: data)

        XCTAssertEqual(config.name, "Leda")
        XCTAssertEqual(config.pitch, 0.3)
        XCTAssertEqual(config.speed, 0.9)
    }

    // MARK: - Custom Initialization

    func testCustomInit() {
        let config = VoiceConfig(name: "Aoede", pitch: -0.5, speed: 2.0)
        XCTAssertEqual(config.name, "Aoede")
        XCTAssertEqual(config.pitch, -0.5)
        XCTAssertEqual(config.speed, 2.0)
    }
}
