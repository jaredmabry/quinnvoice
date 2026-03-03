import Foundation

// MARK: - Task Type

/// Categories of tasks that can be routed to different Gemini models.
enum GeminiTaskType: String, Sendable, CaseIterable {
    /// Processing results from tool calls.
    case toolResultProcessing
    /// Analyzing screen context (app name, window title, visible text).
    case screenContextAnalysis
    /// Simple question and answer.
    case simpleQA
    /// Complex agent reasoning with multi-step planning.
    case agentReasoning
    /// Analyzing or debugging code.
    case codeAnalysis
    /// Summarizing or compressing context.
    case contextSummarization
    /// Analyzing images.
    case imageAnalysis
    /// General-purpose generation.
    case general
}

// MARK: - Model Preference

/// User preference for model selection.
enum ModelPreference: String, Codable, Sendable, CaseIterable {
    /// Let the router decide based on task type.
    case auto
    /// Always use Flash (cheap/fast).
    case flash
    /// Always use Pro (smart/expensive).
    case pro

    var displayName: String {
        switch self {
        case .auto: return "Auto (recommended)"
        case .flash: return "Always Flash (cheaper)"
        case .pro: return "Always Pro (smarter)"
        }
    }
}

// MARK: - GeminiModelRouter

/// Smart routing logic that picks Flash vs Pro based on task complexity.
///
/// Default routing rules:
/// - **Flash**: Tool result processing, screen context analysis, simple Q&A,
///   context summarization, image analysis
/// - **Pro**: Agent reasoning / multi-step, code analysis / debugging
///
/// Users can override with a `ModelPreference` to force a specific model.
struct GeminiModelRouter: Sendable {

    /// The user's model preference override.
    var preference: ModelPreference

    init(preference: ModelPreference = .auto) {
        self.preference = preference
    }

    /// Route a task to the appropriate Gemini model.
    ///
    /// - Parameter task: The type of task to route.
    /// - Returns: The recommended `GeminiModel`.
    func route(task: GeminiTaskType) -> GeminiModel {
        switch preference {
        case .flash:
            return .flash
        case .pro:
            return .pro
        case .auto:
            return autoRoute(task: task)
        }
    }

    /// Automatic routing based on task complexity.
    private func autoRoute(task: GeminiTaskType) -> GeminiModel {
        switch task {
        case .toolResultProcessing:
            return .flash
        case .screenContextAnalysis:
            return .flash
        case .simpleQA:
            return .flash
        case .contextSummarization:
            return .flash
        case .imageAnalysis:
            return .flash
        case .agentReasoning:
            return .pro
        case .codeAnalysis:
            return .pro
        case .general:
            return .flash
        }
    }
}
