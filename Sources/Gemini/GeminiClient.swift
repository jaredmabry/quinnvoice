import Foundation

// MARK: - Gemini Model

/// Available Gemini models for non-live (REST API) tasks.
enum GeminiModel: String, Codable, Sendable, CaseIterable {
    /// Cheap/fast — tool processing, image analysis, summarization.
    case flash = "gemini-2.5-flash"
    /// Smart/expensive — agent reasoning, code analysis.
    case pro = "gemini-2.5-pro"

    var displayName: String {
        switch self {
        case .flash: return "Gemini 2.5 Flash"
        case .pro: return "Gemini 2.5 Pro"
        }
    }
}

// MARK: - Gemini Error

/// Errors from the Gemini REST API client.
enum GeminiError: Error, LocalizedError, Sendable {
    case missingApiKey
    case invalidRequest(String)
    case httpError(statusCode: Int, message: String)
    case decodingError(String)
    case noContent
    case rateLimited(retryAfterSeconds: Double?)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Gemini API key is not configured"
        case .invalidRequest(let detail):
            return "Invalid request: \(detail)"
        case .httpError(let code, let message):
            return "Gemini API error (\(code)): \(message)"
        case .decodingError(let detail):
            return "Failed to decode Gemini response: \(detail)"
        case .noContent:
            return "Gemini returned no content"
        case .rateLimited(let retry):
            if let retry {
                return "Rate limited — retry after \(Int(retry))s"
            }
            return "Rate limited by Gemini API"
        case .networkError(let detail):
            return "Network error: \(detail)"
        }
    }
}

// MARK: - Request/Response Models

/// Gemini generateContent request body.
struct GeminiGenerateRequest: Codable, Sendable {
    let contents: [GeminiContent]
    var generationConfig: GeminiGenerationConfig?
    var systemInstruction: GeminiContent?
    var cachedContent: String?

    struct GeminiContent: Codable, Sendable {
        var role: String?
        let parts: [GeminiPart]
    }

    struct GeminiPart: Codable, Sendable {
        var text: String?
        var inlineData: GeminiInlineData?
    }

    struct GeminiInlineData: Codable, Sendable {
        let mimeType: String
        let data: String // base64
    }

    struct GeminiGenerationConfig: Codable, Sendable {
        var temperature: Double?
        var maxOutputTokens: Int?
        var responseMimeType: String?
        var responseSchema: AnyCodable?
    }
}

/// Gemini generateContent response.
struct GeminiGenerateResponse: Codable, Sendable {
    let candidates: [Candidate]?
    let error: GeminiAPIError?

    struct Candidate: Codable, Sendable {
        let content: Content?
        let finishReason: String?
    }

    struct Content: Codable, Sendable {
        let parts: [Part]?
        let role: String?
    }

    struct Part: Codable, Sendable {
        let text: String?
    }

    struct GeminiAPIError: Codable, Sendable {
        let code: Int?
        let message: String?
        let status: String?
    }

    /// Extract the text from the first candidate.
    var text: String? {
        candidates?.first?.content?.parts?.compactMap(\.text).joined()
    }
}

/// Type-erased Codable wrapper for JSON schema values.
struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map(\.value)
        } else if let str = try? container.decode(String.self) {
            value = str
        } else if let num = try? container.decode(Double.self) {
            value = num
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let dict = value as? [String: Any] {
            let wrapped = dict.mapValues { AnyCodable($0) }
            try container.encode(wrapped)
        } else if let arr = value as? [Any] {
            try container.encode(arr.map { AnyCodable($0) })
        } else if let str = value as? String {
            try container.encode(str)
        } else if let num = value as? Double {
            try container.encode(num)
        } else if let num = value as? Int {
            try container.encode(num)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else {
            try container.encodeNil()
        }
    }
}

// MARK: - URLSession Protocol (for testing)

/// Protocol abstracting URLSession for dependency injection in tests.
protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

// MARK: - GeminiClient

/// REST API client for the standard (non-Live) Gemini generateContent endpoint.
///
/// Supports text generation, structured output, summarization, and image analysis.
/// Includes rate limiting with exponential backoff and optional context caching.
actor GeminiClient {

    // MARK: - Properties

    private let apiKey: String
    private let session: URLSessionProtocol
    private let baseURL: String

    /// Maximum retry attempts for rate-limited requests.
    private let maxRetries: Int = 3

    /// Base delay for exponential backoff (seconds).
    private let baseRetryDelay: Double = 1.0

    /// Whether to include cachedContent in requests (for system prompts).
    var contextCachingEnabled: Bool = true

    /// Cached system instruction identifier, if any.
    var cachedContentId: String?

    // MARK: - Init

    /// Create a new GeminiClient.
    ///
    /// - Parameters:
    ///   - apiKey: The Gemini API key.
    ///   - session: URLSession to use (injectable for testing).
    ///   - baseURL: Base URL for the Gemini API.
    init(
        apiKey: String,
        session: URLSessionProtocol = URLSession.shared,
        baseURL: String = "https://generativelanguage.googleapis.com/v1beta"
    ) {
        self.apiKey = apiKey
        self.session = session
        self.baseURL = baseURL
    }

    // MARK: - Public Methods

    /// Generate text from a prompt with optional image input.
    ///
    /// - Parameters:
    ///   - model: The Gemini model to use.
    ///   - prompt: The text prompt.
    ///   - images: Optional array of (mimeType, data) tuples for image input.
    /// - Returns: The generated text response.
    func generate(
        model: GeminiModel,
        prompt: String,
        images: [(mimeType: String, data: Data)]? = nil
    ) async throws -> String {
        var parts: [GeminiGenerateRequest.GeminiPart] = [
            .init(text: prompt)
        ]

        if let images {
            for image in images {
                parts.append(.init(
                    inlineData: .init(
                        mimeType: image.mimeType,
                        data: image.data.base64EncodedString()
                    )
                ))
            }
        }

        let request = GeminiGenerateRequest(
            contents: [.init(role: "user", parts: parts)]
        )

        let response = try await sendRequest(model: model, body: request)

        guard let text = response.text, !text.isEmpty else {
            throw GeminiError.noContent
        }

        return text
    }

    /// Generate structured output conforming to a JSON schema.
    ///
    /// - Parameters:
    ///   - model: The Gemini model to use.
    ///   - prompt: The text prompt.
    ///   - responseSchema: A JSON schema dictionary describing the expected output.
    /// - Returns: The decoded structured response.
    func generateStructured<T: Decodable>(
        model: GeminiModel,
        prompt: String,
        responseSchema: [String: Any]
    ) async throws -> T {
        let request = GeminiGenerateRequest(
            contents: [.init(role: "user", parts: [.init(text: prompt)])],
            generationConfig: .init(
                responseMimeType: "application/json",
                responseSchema: AnyCodable(responseSchema)
            )
        )

        let response = try await sendRequest(model: model, body: request)

        guard let text = response.text, !text.isEmpty else {
            throw GeminiError.noContent
        }

        guard let jsonData = text.data(using: .utf8) else {
            throw GeminiError.decodingError("Response is not valid UTF-8")
        }

        do {
            return try JSONDecoder().decode(T.self, from: jsonData)
        } catch {
            throw GeminiError.decodingError(error.localizedDescription)
        }
    }

    /// Summarize text content using Flash model.
    ///
    /// - Parameters:
    ///   - text: The text to summarize.
    ///   - maxTokens: Maximum tokens in the summary (default: 500).
    /// - Returns: The summarized text.
    func summarize(text: String, maxTokens: Int = 500) async throws -> String {
        let prompt = """
        Summarize the following text concisely, preserving key facts and actionable items. \
        Keep the summary under \(maxTokens) tokens.

        Text to summarize:
        \(text)
        """

        let request = GeminiGenerateRequest(
            contents: [.init(role: "user", parts: [.init(text: prompt)])],
            generationConfig: .init(maxOutputTokens: maxTokens)
        )

        let response = try await sendRequest(model: .flash, body: request)

        guard let result = response.text, !result.isEmpty else {
            throw GeminiError.noContent
        }

        return result
    }

    /// Analyze an image with a text prompt.
    ///
    /// - Parameters:
    ///   - imageData: The raw image data (JPEG or PNG).
    ///   - prompt: The analysis prompt.
    /// - Returns: The analysis result text.
    func analyzeImage(imageData: Data, prompt: String) async throws -> String {
        let mimeType: String
        // Detect image format from magic bytes
        if imageData.starts(with: [0xFF, 0xD8]) {
            mimeType = "image/jpeg"
        } else if imageData.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            mimeType = "image/png"
        } else {
            mimeType = "image/jpeg" // fallback
        }

        return try await generate(
            model: .flash,
            prompt: prompt,
            images: [(mimeType: mimeType, data: imageData)]
        )
    }

    // MARK: - Private Methods

    /// Send a generateContent request with retry logic.
    private func sendRequest(
        model: GeminiModel,
        body: GeminiGenerateRequest
    ) async throws -> GeminiGenerateResponse {
        guard !apiKey.isEmpty else {
            throw GeminiError.missingApiKey
        }

        let url = URL(string: "\(baseURL)/models/\(model.rawValue):generateContent?key=\(apiKey)")!

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 60

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(body)

        // Retry loop with exponential backoff
        var lastError: Error = GeminiError.networkError("No attempts made")

        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await session.data(for: urlRequest)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw GeminiError.networkError("Invalid response type")
                }

                // Handle rate limiting
                if httpResponse.statusCode == 429 {
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                        .flatMap(Double.init)
                    let delay = retryAfter ?? (baseRetryDelay * pow(2.0, Double(attempt)))

                    if attempt < maxRetries - 1 {
                        try await Task.sleep(for: .seconds(delay))
                        continue
                    }
                    throw GeminiError.rateLimited(retryAfterSeconds: retryAfter)
                }

                // Handle other HTTP errors
                if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw GeminiError.httpError(
                        statusCode: httpResponse.statusCode,
                        message: errorMessage
                    )
                }

                // Decode response
                let decoded = try JSONDecoder().decode(GeminiGenerateResponse.self, from: data)

                // Check for API-level error
                if let apiError = decoded.error {
                    throw GeminiError.httpError(
                        statusCode: apiError.code ?? 0,
                        message: apiError.message ?? "Unknown API error"
                    )
                }

                return decoded

            } catch let error as GeminiError {
                lastError = error
                // Only retry on rate limit; other errors are terminal
                if case .rateLimited = error, attempt < maxRetries - 1 {
                    continue
                }
                throw error
            } catch {
                lastError = error
                // Retry on network errors
                if attempt < maxRetries - 1 {
                    let delay = baseRetryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(for: .seconds(delay))
                    continue
                }
                throw GeminiError.networkError(error.localizedDescription)
            }
        }

        throw lastError
    }
}
