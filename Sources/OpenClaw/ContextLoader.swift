import Foundation

/// Loads Quinn's persona and user context from the OpenClaw workspace files.
///
/// Optionally includes live screen context (frontmost app, window title, selected text)
/// when ``includeScreenContext`` is enabled.
actor ContextLoader {
    private let bridge: OpenClawBridge
    private let workspacePath: String
    private let screenContextProvider: ScreenContextProvider?

    /// Whether to include screen context in system instructions.
    var includeScreenContext: Bool

    init(bridge: OpenClawBridge, workspacePath: String = "/Users/jaredmabry/.openclaw/workspace", includeScreenContext: Bool = false) {
        self.bridge = bridge
        self.workspacePath = workspacePath
        self.includeScreenContext = includeScreenContext
        // ScreenContextProvider is MainActor-bound, but we create it here and use it from MainActor calls
        self.screenContextProvider = nil
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

        // Load SOUL.md
        if let soul = await loadFile("SOUL.md") {
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

        // Load MEMORY.md
        if let memory = await loadFile("MEMORY.md") {
            parts.append("## Memory\n\(memory)")
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
}
