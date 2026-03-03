/// VoiceConfigTests.swift — Comprehensive tests for VoiceConfig.

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
        XCTAssertTrue(VoiceConfig.availableVoices.contains(VoiceConfig.default.name))
    }

    // MARK: - Codable Round-Trip (Every Field)

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

    func testCodable_roundTrip_zeroPitchAndSpeed() throws {
        let original = VoiceConfig(name: "Charon", pitch: 0.0, speed: 0.0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VoiceConfig.self, from: data)
        XCTAssertEqual(decoded.name, "Charon")
        XCTAssertEqual(decoded.pitch, 0.0)
        XCTAssertEqual(decoded.speed, 0.0)
    }

    func testCodable_roundTrip_extremeValues() throws {
        let original = VoiceConfig(name: "Aoede", pitch: -2.0, speed: 3.0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VoiceConfig.self, from: data)
        XCTAssertEqual(decoded.name, "Aoede")
        XCTAssertEqual(decoded.pitch, -2.0)
        XCTAssertEqual(decoded.speed, 3.0)
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

    // MARK: - Equality

    func testEquality_identicalConfigs() {
        let a = VoiceConfig(name: "Kore", pitch: 0, speed: 1.0)
        let b = VoiceConfig(name: "Kore", pitch: 0, speed: 1.0)
        XCTAssertEqual(a.name, b.name)
        XCTAssertEqual(a.pitch, b.pitch)
        XCTAssertEqual(a.speed, b.speed)
    }

    func testEquality_differentConfigs() {
        let a = VoiceConfig(name: "Kore", pitch: 0, speed: 1.0)
        let b = VoiceConfig(name: "Puck", pitch: 0.5, speed: 1.5)
        XCTAssertNotEqual(a.name, b.name)
    }

    // MARK: - Custom Initialization

    func testCustomInit() {
        let config = VoiceConfig(name: "Aoede", pitch: -0.5, speed: 2.0)
        XCTAssertEqual(config.name, "Aoede")
        XCTAssertEqual(config.pitch, -0.5)
        XCTAssertEqual(config.speed, 2.0)
    }

    // MARK: - Codable Round-Trip for Each Voice

    func testCodable_roundTrip_Aoede() throws {
        try assertVoiceCodableRoundTrip(name: "Aoede")
    }

    func testCodable_roundTrip_Charon() throws {
        try assertVoiceCodableRoundTrip(name: "Charon")
    }

    func testCodable_roundTrip_Fenrir() throws {
        try assertVoiceCodableRoundTrip(name: "Fenrir")
    }

    func testCodable_roundTrip_Kore() throws {
        try assertVoiceCodableRoundTrip(name: "Kore")
    }

    func testCodable_roundTrip_Leda() throws {
        try assertVoiceCodableRoundTrip(name: "Leda")
    }

    func testCodable_roundTrip_Orus() throws {
        try assertVoiceCodableRoundTrip(name: "Orus")
    }

    func testCodable_roundTrip_Puck() throws {
        try assertVoiceCodableRoundTrip(name: "Puck")
    }

    func testCodable_roundTrip_Zephyr() throws {
        try assertVoiceCodableRoundTrip(name: "Zephyr")
    }

    // MARK: - Helpers

    private func assertVoiceCodableRoundTrip(name: String) throws {
        let original = VoiceConfig(name: name, pitch: 0.3, speed: 1.1)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VoiceConfig.self, from: data)
        XCTAssertEqual(decoded.name, name)
        XCTAssertEqual(decoded.pitch, 0.3)
        XCTAssertEqual(decoded.speed, 1.1)
    }
}
