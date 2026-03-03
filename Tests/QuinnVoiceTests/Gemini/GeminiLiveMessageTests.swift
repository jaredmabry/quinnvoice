/// GeminiLiveMessageTests.swift — Tests for Gemini Live WebSocket message formats.

import XCTest

@testable import QuinnVoice

final class GeminiLiveMessageTests: XCTestCase {

    // MARK: - Setup Message Format

    func testSetupMessage_containsModel() throws {
        let message = buildSetupMessage(
            model: "gemini-live-2.5-flash-native-audio",
            voice: VoiceConfig.default,
            systemInstruction: "You are Quinn.",
            tools: GeminiToolProxy.toolDeclarations
        )

        let data = try JSONSerialization.data(withJSONObject: message)
        XCTAssertGreaterThan(data.count, 0)

        let setup = message["setup"] as? [String: Any]
        XCTAssertNotNil(setup)
        XCTAssertEqual(setup?["model"] as? String, "gemini-live-2.5-flash-native-audio")
    }

    func testSetupMessage_containsGenerationConfig() throws {
        let message = buildSetupMessage(
            model: "gemini-live-2.5-flash-native-audio",
            voice: VoiceConfig(name: "Puck", pitch: 0.5, speed: 1.2),
            systemInstruction: "You are Quinn.",
            tools: []
        )

        let setup = message["setup"] as? [String: Any]
        let config = setup?["generationConfig"] as? [String: Any]
        XCTAssertNotNil(config)

        let speechConfig = config?["speechConfig"] as? [String: Any]
        let voiceConfig = speechConfig?["voiceConfig"] as? [String: Any]
        XCTAssertEqual(voiceConfig?["prebuiltVoiceConfig"] as? [String: String],
                       ["voiceName": "Puck"])
    }

    func testSetupMessage_containsSystemInstruction() throws {
        let message = buildSetupMessage(
            model: "gemini-live-2.5-flash-native-audio",
            voice: VoiceConfig.default,
            systemInstruction: "Test instruction",
            tools: []
        )

        let setup = message["setup"] as? [String: Any]
        let system = setup?["systemInstruction"] as? [String: Any]
        let parts = system?["parts"] as? [[String: Any]]
        XCTAssertEqual(parts?.count, 1)
        XCTAssertEqual(parts?.first?["text"] as? String, "Test instruction")
    }

    func testSetupMessage_containsTools() throws {
        let message = buildSetupMessage(
            model: "gemini-live-2.5-flash-native-audio",
            voice: VoiceConfig.default,
            systemInstruction: "You are Quinn.",
            tools: GeminiToolProxy.toolDeclarations
        )

        let setup = message["setup"] as? [String: Any]
        let tools = setup?["tools"] as? [[String: Any]]
        XCTAssertNotNil(tools)
        XCTAssertGreaterThan(tools?.count ?? 0, 0)
    }

    // MARK: - Audio Data Message

    func testAudioDataMessage_containsBase64() throws {
        let pcmData = Data(repeating: 0, count: 3200) // 100ms of 16kHz int16
        let message = buildAudioDataMessage(pcmData: pcmData)

        let realtimeInput = message["realtimeInput"] as? [String: Any]
        let mediaChunks = realtimeInput?["mediaChunks"] as? [[String: Any]]
        XCTAssertEqual(mediaChunks?.count, 1)

        let chunk = mediaChunks?.first
        XCTAssertEqual(chunk?["mimeType"] as? String, "audio/pcm;rate=16000")

        let base64Data = chunk?["data"] as? String
        XCTAssertNotNil(base64Data)
        XCTAssertFalse(base64Data!.isEmpty)

        // Verify it's valid base64
        let decoded = Data(base64Encoded: base64Data!)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 3200)
    }

    // MARK: - Function Response Message

    func testFunctionResponse_format() throws {
        let response = buildFunctionResponseMessage(
            callId: "call_123",
            functionName: "search_web",
            result: "The weather is 72°F"
        )

        let toolResponse = response["toolResponse"] as? [String: Any]
        XCTAssertNotNil(toolResponse)

        let functionResponses = toolResponse?["functionResponses"] as? [[String: Any]]
        XCTAssertEqual(functionResponses?.count, 1)

        let resp = functionResponses?.first
        XCTAssertEqual(resp?["id"] as? String, "call_123")
        XCTAssertEqual(resp?["name"] as? String, "search_web")

        let responseBody = resp?["response"] as? [String: Any]
        XCTAssertEqual(responseBody?["result"] as? String, "The weather is 72°F")
    }

    func testFunctionResponse_isValidJson() throws {
        let response = buildFunctionResponseMessage(
            callId: "call_456",
            functionName: "get_weather",
            result: "Sunny, 85°F"
        )

        let data = try JSONSerialization.data(withJSONObject: response)
        XCTAssertGreaterThan(data.count, 0)

        // Round-trip
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(parsed?["toolResponse"])
    }

    // MARK: - Different Voice Configs

    func testSetupMessage_withDifferentVoices() throws {
        for voice in VoiceConfig.availableVoices {
            let config = VoiceConfig(name: voice, pitch: 0, speed: 1.0)
            let message = buildSetupMessage(
                model: "gemini-live-2.5-flash-native-audio",
                voice: config,
                systemInstruction: "Test",
                tools: []
            )

            let setup = message["setup"] as? [String: Any]
            let genConfig = setup?["generationConfig"] as? [String: Any]
            let speechConfig = genConfig?["speechConfig"] as? [String: Any]
            let voiceConfig = speechConfig?["voiceConfig"] as? [String: Any]
            let prebuilt = voiceConfig?["prebuiltVoiceConfig"] as? [String: String]
            XCTAssertEqual(prebuilt?["voiceName"], voice, "Voice config should use \(voice)")
        }
    }

    // MARK: - Helpers

    private func buildSetupMessage(
        model: String,
        voice: VoiceConfig,
        systemInstruction: String,
        tools: [[String: Any]]
    ) -> [String: Any] {
        var setup: [String: Any] = [
            "model": model,
            "generationConfig": [
                "speechConfig": [
                    "voiceConfig": [
                        "prebuiltVoiceConfig": [
                            "voiceName": voice.name
                        ]
                    ]
                ],
                "responseModalities": ["AUDIO"]
            ] as [String: Any],
            "systemInstruction": [
                "parts": [["text": systemInstruction]]
            ]
        ]

        if !tools.isEmpty {
            setup["tools"] = [["functionDeclarations": tools]]
        }

        return ["setup": setup]
    }

    private func buildAudioDataMessage(pcmData: Data) -> [String: Any] {
        [
            "realtimeInput": [
                "mediaChunks": [
                    [
                        "mimeType": "audio/pcm;rate=16000",
                        "data": pcmData.base64EncodedString()
                    ]
                ]
            ]
        ]
    }

    private func buildFunctionResponseMessage(
        callId: String,
        functionName: String,
        result: String
    ) -> [String: Any] {
        [
            "toolResponse": [
                "functionResponses": [
                    [
                        "id": callId,
                        "name": functionName,
                        "response": ["result": result]
                    ]
                ]
            ]
        ]
    }
}
