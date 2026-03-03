import Foundation

/// Direct WebSocket client for the Gemini Live Multimodal API.
/// Protocol: wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent
actor GeminiLiveSession {

    // MARK: - Types

    enum SessionError: Error, LocalizedError {
        case notConnected
        case setupFailed(String)
        case connectionFailed(String)

        var errorDescription: String? {
            switch self {
            case .notConnected: return "WebSocket not connected"
            case .setupFailed(let msg): return "Session setup failed: \(msg)"
            case .connectionFailed(let msg): return "Connection failed: \(msg)"
            }
        }
    }

    enum Event: Sendable {
        case setupComplete
        case audioData(Data)
        case text(String)
        case turnComplete
        case interrupted
        case functionCall(name: String, id: String, arguments: [String: String])
        case error(String)
        case disconnected
    }

    // MARK: - Properties

    private var webSocket: URLSessionWebSocketTask?
    private let urlSession: URLSession
    private var isSetupComplete = false

    private let apiKey: String
    private let model: String

    /// Stream of events from the session.
    var eventHandler: (@Sendable (Event) -> Void)?

    // MARK: - Init

    init(apiKey: String, model: String = "gemini-2.5-flash-native-audio-latest") {
        self.apiKey = apiKey
        self.model = model
        self.urlSession = URLSession(configuration: .default)
    }

    // MARK: - Connection

    func connect(systemInstruction: String, voiceConfig: VoiceConfig) async throws {
        let wsURL = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)")!

        let task = urlSession.webSocketTask(with: wsURL)
        self.webSocket = task
        task.resume()

        // Send setup message
        let setupMessage = buildSetupMessage(
            systemInstruction: systemInstruction,
            voiceConfig: voiceConfig
        )

        let jsonData = try JSONSerialization.data(withJSONObject: setupMessage)
        try await task.send(.string(String(data: jsonData, encoding: .utf8)!))

        // Start receiving messages
        startReceiving()
    }

    func disconnect() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        isSetupComplete = false
        eventHandler?(.disconnected)
    }

    // MARK: - Sending Audio

    /// Send raw 16-bit PCM audio data (16kHz mono) to Gemini.
    func sendAudio(_ data: Data) async throws {
        guard let ws = webSocket else { throw SessionError.notConnected }

        let base64Audio = data.base64EncodedString()

        let message: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [
                    [
                        "mimeType": "audio/pcm;rate=16000",
                        "data": base64Audio
                    ]
                ]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: message)
        try await ws.send(.string(String(data: jsonData, encoding: .utf8)!))
    }

    /// Send an image frame alongside the audio stream for multi-modal processing.
    ///
    /// The Gemini Live API accepts `inlineData` with a MIME type in the realtime input.
    /// Images are sent as base64-encoded JPEG data.
    ///
    /// - Parameters:
    ///   - imageData: JPEG-encoded image data.
    ///   - mimeType: The MIME type of the image (default: "image/jpeg").
    func sendImage(_ imageData: Data, mimeType: String = "image/jpeg") async throws {
        guard let ws = webSocket else { throw SessionError.notConnected }

        let base64Image = imageData.base64EncodedString()

        let message: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [
                    [
                        "mimeType": mimeType,
                        "data": base64Image
                    ]
                ]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: message)
        try await ws.send(.string(String(data: jsonData, encoding: .utf8)!))
    }

    /// Send a text message as a user turn (used for voice preview).
    func sendText(_ text: String) async throws {
        guard let ws = webSocket else { throw SessionError.notConnected }

        let message: [String: Any] = [
            "clientContent": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [
                            ["text": text]
                        ]
                    ]
                ],
                "turnComplete": true
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: message)
        try await ws.send(.string(String(data: jsonData, encoding: .utf8)!))
    }

    /// Send a function call response back to Gemini.
    func sendFunctionResponse(callId: String, name: String, response: String) async throws {
        guard let ws = webSocket else { throw SessionError.notConnected }

        let message: [String: Any] = [
            "toolResponse": [
                "functionResponses": [
                    [
                        "id": callId,
                        "name": name,
                        "response": [
                            "result": response
                        ]
                    ]
                ]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: message)
        try await ws.send(.string(String(data: jsonData, encoding: .utf8)!))
    }

    // MARK: - Setup Message

    private func buildSetupMessage(systemInstruction: String, voiceConfig: VoiceConfig) -> [String: Any] {
        var generationConfig: [String: Any] = [
            "responseModalities": ["AUDIO"],
            "speechConfig": [
                "voiceConfig": [
                    "prebuiltVoiceConfig": [
                        "voiceName": voiceConfig.name
                    ]
                ]
            ]
        ]

        // Build tool declarations
        let tools: [[String: Any]] = [
            [
                "functionDeclarations": GeminiToolProxy.toolDeclarations
            ]
        ]

        let setup: [String: Any] = [
            "setup": [
                "model": "models/\(model)",
                "generationConfig": generationConfig,
                "systemInstruction": [
                    "parts": [
                        ["text": systemInstruction]
                    ]
                ],
                "tools": tools
            ]
        ]

        return setup
    }

    // MARK: - Receiving

    private func startReceiving() {
        guard let ws = webSocket else { return }

        Task {
            do {
                while true {
                    let message = try await ws.receive()
                    switch message {
                    case .string(let text):
                        handleTextMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            handleTextMessage(text)
                        }
                    @unknown default:
                        break
                    }
                }
            } catch {
                eventHandler?(.disconnected)
            }
        }
    }

    private func handleTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Setup complete response
        if json["setupComplete"] != nil {
            isSetupComplete = true
            eventHandler?(.setupComplete)
            return
        }

        // Server content (audio, text, turn complete)
        if let serverContent = json["serverContent"] as? [String: Any] {
            handleServerContent(serverContent)
            return
        }

        // Tool call
        if let toolCall = json["toolCall"] as? [String: Any],
           let functionCalls = toolCall["functionCalls"] as? [[String: Any]] {
            for call in functionCalls {
                if let name = call["name"] as? String,
                   let id = call["id"] as? String {
                    let rawArgs = call["args"] as? [String: Any] ?? [:]
                    // Convert to [String: String] for Sendable conformance
                    var stringArgs: [String: String] = [:]
                    for (key, value) in rawArgs {
                        if let str = value as? String {
                            stringArgs[key] = str
                        } else if let data = try? JSONSerialization.data(withJSONObject: value),
                                  let str = String(data: data, encoding: .utf8) {
                            stringArgs[key] = str
                        }
                    }
                    eventHandler?(.functionCall(name: name, id: id, arguments: stringArgs))
                }
            }
            return
        }

        // Interrupted (barge-in from server)
        if json["serverContent"] == nil, let _ = json["interrupted"] {
            eventHandler?(.interrupted)
        }
    }

    private func handleServerContent(_ content: [String: Any]) {
        // Check for turn complete
        if let turnComplete = content["turnComplete"] as? Bool, turnComplete {
            eventHandler?(.turnComplete)
            return
        }

        // Check for interrupted
        if let interrupted = content["interrupted"] as? Bool, interrupted {
            eventHandler?(.interrupted)
            return
        }

        // Parse model turn parts
        if let modelTurn = content["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            for part in parts {
                // Audio response
                if let inlineData = part["inlineData"] as? [String: Any],
                   let base64 = inlineData["data"] as? String,
                   let mimeType = inlineData["mimeType"] as? String,
                   mimeType.contains("audio") {
                    if let audioData = Data(base64Encoded: base64) {
                        eventHandler?(.audioData(audioData))
                    }
                }

                // Text response
                if let text = part["text"] as? String {
                    eventHandler?(.text(text))
                }
            }
        }
    }
}
