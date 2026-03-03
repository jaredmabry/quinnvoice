import Foundation

/// Loads Quinn's persona and user context from the OpenClaw workspace files.
///
/// Optionally includes live screen context (frontmost app, window title, selected text)
/// when ``includeScreenContext`` is enabled. Also integrates soul/personality and memory
/// content from their respective managers.
///
/// When a ``GeminiClient`` is provided and context caching is enabled, MEMORY.md content
/// exceeding 2000 tokens (~8000 characters) is automatically summarized using Flash
/// to reduce costs.
actor ContextLoader {
    private let bridge: OpenClawBridge
    private let workspacePath: String
    private let screenContextProvider: ScreenContextProvider?

    /// Whether to include screen context in system instructions.
    var includeScreenContext: Bool

    /// Optional GeminiClient for context summarization.
    var geminiClient: GeminiClient?

    /// Whether context summarization is enabled.
    var contextSummarizationEnabled: Bool = true

    /// Soul/personality text to inject into system instructions.
    var soulContent: String?

    /// Memory text to inject into system instructions.
    var memoryContent: String?

    /// Approximate character threshold for MEMORY.md summarization (~2000 tokens).
    private let memorySummarizationThreshold = 8000

    init(bridge: OpenClawBridge, workspacePath: String = "/Users/jaredmabry/.openclaw/workspace", includeScreenContext: Bool = false) {
        self.bridge = bridge
        self.workspacePath = workspacePath
        self.includeScreenContext = includeScreenContext
        self.screenContextProvider = nil
    }

    /// Update the soul content from SoulManager.
    func setSoulContent(_ content: String?) {
        self.soulContent = content
    }

    /// Update the memory content from MemoryManager.
    func setMemoryContent(_ content: String?) {
        self.memoryContent = content
    }

    /// Build the full system instruction string from workspace context files.
    /// - Parameter screenContext: Optional pre-captured screen context string to include.
    func loadSystemInstructions(screenContext: String? = nil) async -> String {
        var parts: [String] = []

        // Core identity
        parts.append("""
        You are Quinn, a personal voice assistant for Jared. You run as a macOS menu bar app \
        connected to Jared's OpenClaw instance. Be warm, concise, and genuinely helpful. \
        Skip filler phrases — just help. Have opinions. Be resourceful.
        """)

        // Inject soul/personality from SoulManager (takes priority over workspace SOUL.md)
        if let soul = soulContent, !soul.isEmpty {
            parts.append("## Persona\n\(soul)")
        } else if let soul = await loadFile("SOUL.md") {
            parts.append("## Persona\n\(soul)")
        }

        // Load IDENTITY.md
        if let identity = await loadFile("IDENTITY.md") {
            parts.append("## Identity\n\(identity)")
        }

        // Load USER.md
        if let user = await loadFile("USER.md") {
            parts.append("## About the User\n\(user)")
        }

        // Inject on-device memory from MemoryManager (takes priority over workspace MEMORY.md)
        if let memory = memoryContent, !memory.isEmpty {
            let memoryCompressed = await compressIfNeeded(memory, label: "on-device memory")
            parts.append("## On-Device Memory\n\(memoryCompressed)")
        }

        // Load workspace MEMORY.md (summarize if too long)
        if let memory = await loadFile("MEMORY.md") {
            let memoryContent = await compressIfNeeded(memory, label: "MEMORY.md")
            parts.append("## Memory\n\(memoryContent)")
        }

        // Include screen context if provided
        if let context = screenContext, !context.isEmpty {
            parts.append("## Current Screen Context\n\(context)")
        }

        // Voice-specific instructions
        parts.append("""
        ## Voice Interaction Guidelines
        - Keep responses concise for voice — aim for 1-3 sentences unless asked for detail.
        - Use natural conversational language, not written prose.
        - If you need to present a list, summarize verbally and offer to send details via text.
        - Acknowledge commands quickly: "Done", "On it", "Got it".
        - For complex requests, confirm understanding before executing.
        - You have access to the user's clipboard via get_clipboard and set_clipboard tools.
        - You can see what app the user is currently using (screen context) when enabled.
        """)

        return parts.joined(separator: "\n\n")
    }

    private func loadFile(_ name: String) async -> String? {
        let path = "\(workspacePath)/\(name)"
        do {
            let content = try await bridge.fetchFileContent(path: path)
            return content.isEmpty ? nil : content
        } catch {
            print("[ContextLoader] Could not load \(name): \(error)")
            return nil
        }
    }

    /// Compress context text using GeminiClient (Flash) if it exceeds the threshold.
    private func compressIfNeeded(_ text: String, label: String) async -> String {
        guard contextSummarizationEnabled,
              text.count > memorySummarizationThreshold,
              let client = geminiClient else {
            return text
        }

        do {
            let summary = try await client.summarize(text: text, maxTokens: 500)
            print("[ContextLoader] Summarized \(label): \(text.count) → \(summary.count) chars")
            return summary
        } catch {
            print("[ContextLoader] Summarization failed for \(label), using truncated version: \(error)")
            return String(text.prefix(memorySummarizationThreshold)) + "\n[…truncated]"
        }
    }
}
