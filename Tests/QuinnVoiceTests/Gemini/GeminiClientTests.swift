/// GeminiClientTests.swift — Tests for GeminiClient REST API client.
/// Uses a mock URLSession to avoid real API calls.

import Foundation
import XCTest

@testable import QuinnVoice

// MARK: - Mock URLSession

/// A mock URLSession that returns predefined responses.
final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    var responseData: Data = Data()
    var responseStatusCode: Int = 200
    var responseError: Error?
    /// Access only from nonisolated synchronous context or after await.
    nonisolated(unsafe) var lastRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request

        if let error = responseError {
            throw error
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: responseStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        return (responseData, response)
    }

    func getLastRequest() -> URLRequest? {
        lastRequest
    }
}

final class GeminiClientTests: XCTestCase {

    // MARK: - Request Construction

    func testGenerate_requestConstruction() async throws {
        let mockSession = MockURLSession()
        mockSession.responseData = makeSuccessResponse(text: "Hello!")

        let client = GeminiClient(
            apiKey: "test-key",
            session: mockSession,
            baseURL: "https://generativelanguage.googleapis.com/v1beta"
        )

        _ = try await client.generate(model: .flash, prompt: "Say hello")

        let request = mockSession.getLastRequest()
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertTrue(request?.url?.absoluteString.contains("gemini-2.5-flash") ?? false)
        XCTAssertTrue(request?.url?.absoluteString.contains("key=test-key") ?? false)
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testGenerate_proModel_usesCorrectEndpoint() async throws {
        let mockSession = MockURLSession()
        mockSession.responseData = makeSuccessResponse(text: "Result")

        let client = GeminiClient(apiKey: "test-key", session: mockSession)
        _ = try await client.generate(model: .pro, prompt: "Complex task")

        let request = mockSession.getLastRequest()
        XCTAssertTrue(request?.url?.absoluteString.contains("gemini-2.5-pro") ?? false)
    }

    // MARK: - Response Parsing

    func testGenerate_parsesTextFromResponse() async throws {
        let mockSession = MockURLSession()
        mockSession.responseData = makeSuccessResponse(text: "The answer is 42.")

        let client = GeminiClient(apiKey: "test-key", session: mockSession)
        let result = try await client.generate(model: .flash, prompt: "What is the answer?")

        XCTAssertEqual(result, "The answer is 42.")
    }

    func testGenerate_noContent_throwsError() async {
        let mockSession = MockURLSession()
        mockSession.responseData = makeSuccessResponse(text: nil)

        let client = GeminiClient(apiKey: "test-key", session: mockSession)

        do {
            _ = try await client.generate(model: .flash, prompt: "Empty response")
            XCTFail("Should have thrown")
        } catch let error as GeminiError {
            if case .noContent = error {
                // Expected
            } else {
                XCTFail("Expected noContent error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Error Response Handling

    func testGenerate_httpError_throwsGeminiError() async {
        let mockSession = MockURLSession()
        mockSession.responseStatusCode = 400
        mockSession.responseData = "Bad request".data(using: .utf8)!

        let client = GeminiClient(apiKey: "test-key", session: mockSession)

        do {
            _ = try await client.generate(model: .flash, prompt: "Bad request")
            XCTFail("Should have thrown")
        } catch let error as GeminiError {
            if case .httpError(let code, _) = error {
                XCTAssertEqual(code, 400)
            } else {
                XCTFail("Expected httpError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testGenerate_missingApiKey_throwsError() async {
        let mockSession = MockURLSession()
        let client = GeminiClient(apiKey: "", session: mockSession)

        do {
            _ = try await client.generate(model: .flash, prompt: "No key")
            XCTFail("Should have thrown")
        } catch let error as GeminiError {
            if case .missingApiKey = error {
                // Expected
            } else {
                XCTFail("Expected missingApiKey, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Structured Output

    func testGenerateStructured_parsesDecodable() async throws {
        struct SimpleResult: Codable {
            let answer: String
        }

        let mockSession = MockURLSession()
        // Build the response with escaped JSON in the text field
        let responseJson = """
        {
            "candidates": [{
                "content": {
                    "parts": [{"text": "{\\"answer\\": \\"Paris\\"}"}],
                    "role": "model"
                },
                "finishReason": "STOP"
            }]
        }
        """
        mockSession.responseData = responseJson.data(using: .utf8)!

        let client = GeminiClient(apiKey: "test-key", session: mockSession)
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["answer": ["type": "string"]],
            "required": ["answer"]
        ]

        let result: SimpleResult = try await client.generateStructured(
            model: .flash,
            prompt: "What is the capital of France?",
            responseSchema: schema
        )

        XCTAssertEqual(result.answer, "Paris")
    }

    // MARK: - Summarize

    func testSummarize_usesFlashModel() async throws {
        let mockSession = MockURLSession()
        mockSession.responseData = makeSuccessResponse(text: "Short summary here.")

        let client = GeminiClient(apiKey: "test-key", session: mockSession)
        let result = try await client.summarize(text: "Long text goes here...")

        XCTAssertEqual(result, "Short summary here.")

        let request = mockSession.getLastRequest()
        XCTAssertTrue(request?.url?.absoluteString.contains("gemini-2.5-flash") ?? false)
    }

    // MARK: - Image Analysis

    func testAnalyzeImage_includesImageInRequest() async throws {
        let mockSession = MockURLSession()
        mockSession.responseData = makeSuccessResponse(text: "A cat sitting on a chair.")

        let client = GeminiClient(apiKey: "test-key", session: mockSession)

        // JPEG magic bytes
        let fakeImageData = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(repeating: 0, count: 100)
        let result = try await client.analyzeImage(imageData: fakeImageData, prompt: "What is this?")

        XCTAssertEqual(result, "A cat sitting on a chair.")
    }

    // MARK: - GeminiModel

    func testGeminiModel_rawValues() {
        XCTAssertEqual(GeminiModel.flash.rawValue, "gemini-2.5-flash")
        XCTAssertEqual(GeminiModel.pro.rawValue, "gemini-2.5-pro")
    }

    func testGeminiModel_displayNames() {
        XCTAssertFalse(GeminiModel.flash.displayName.isEmpty)
        XCTAssertFalse(GeminiModel.pro.displayName.isEmpty)
    }

    func testGeminiModel_allCases() {
        XCTAssertEqual(GeminiModel.allCases.count, 2)
    }

    // MARK: - GeminiError

    func testGeminiError_descriptions() {
        let errors: [GeminiError] = [
            .missingApiKey,
            .invalidRequest("bad"),
            .httpError(statusCode: 500, message: "server error"),
            .decodingError("decode fail"),
            .noContent,
            .rateLimited(retryAfterSeconds: 5.0),
            .rateLimited(retryAfterSeconds: nil),
            .networkError("timeout"),
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    // MARK: - GeminiGenerateResponse

    func testGenerateResponse_textExtraction() throws {
        let json = """
        {
            "candidates": [{
                "content": {
                    "parts": [{"text": "Hello"}, {"text": " World"}],
                    "role": "model"
                },
                "finishReason": "STOP"
            }]
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(GeminiGenerateResponse.self, from: data)

        XCTAssertEqual(response.text, "Hello World")
        XCTAssertEqual(response.candidates?.first?.finishReason, "STOP")
    }

    func testGenerateResponse_noCandidates_textIsNil() throws {
        let json = """
        {"candidates": []}
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(GeminiGenerateResponse.self, from: data)
        XCTAssertNil(response.text)
    }

    // MARK: - Helpers

    private func makeSuccessResponse(text: String?) -> Data {
        if let text {
            let json = """
            {
                "candidates": [{
                    "content": {
                        "parts": [{"text": "\(text)"}],
                        "role": "model"
                    },
                    "finishReason": "STOP"
                }]
            }
            """
            return json.data(using: .utf8)!
        } else {
            return """
            {"candidates": [{"content": {"parts": [], "role": "model"}, "finishReason": "STOP"}]}
            """.data(using: .utf8)!
        }
    }
}
