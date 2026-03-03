import Foundation

/// Proxies Gemini function calls to the OpenClaw gateway.
///
/// Also provides local tools (clipboard access) that execute directly
/// without going through the OpenClaw gateway.
actor GeminiToolProxy {
    private let bridge: OpenClawBridge

    /// Reference to the clipboard manager for local clipboard operations.
    var clipboardManager: ClipboardManager?

    /// Reference to the notification manager for surfacing important results.
    var notificationManager: NotificationManager?

    /// Reference to the computer controller for agent/computer-use tools.
    var computerController: ComputerController?

    /// Whether clipboard tools are available.
    var clipboardEnabled: Bool = false

    /// Whether notifications are enabled for tool results.
    var notificationsEnabled: Bool = false

    /// Whether computer-use/agent tools are available.
    var computerUseEnabled: Bool = false

    init(bridge: OpenClawBridge) {
        self.bridge = bridge
    }

    /// Available tools to declare in the Gemini session setup.
    /// These map to OpenClaw capabilities and local tools.
    // MARK: - Tool Declarations

    /// Full agentic tool catalog covering all OpenClaw capabilities + local tools.
    /// Gemini Live supports sequential/chained function calls in a single turn,
    /// enabling multi-step task execution.
    nonisolated(unsafe) static let toolDeclarations: [[String: Any]] = [

        // MARK: Web & Search
        [
            "name": "search_web",
            "description": "Search the web for current information.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "The search query"]
                ],
                "required": ["query"]
            ]
        ],
        [
            "name": "fetch_url",
            "description": "Fetch and extract readable content from a URL (HTML → markdown).",
            "parameters": [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "The URL to fetch"]
                ],
                "required": ["url"]
            ]
        ],

        // MARK: Calendar
        [
            "name": "get_calendar",
            "description": "Get calendar events. Can fetch today's schedule, upcoming events, or events for a specific date range.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Natural language query, e.g. 'today', 'tomorrow', 'this week', 'next Monday'"],
                    "calendar": ["type": "string", "description": "Optional: specific calendar name to filter"]
                ],
                "required": ["query"]
            ]
        ],
        [
            "name": "create_calendar_event",
            "description": "Create a new calendar event. REQUIRES CONFIRMATION before executing.",
            "parameters": [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "Event title"],
                    "start_time": ["type": "string", "description": "Start time in natural language or ISO format"],
                    "end_time": ["type": "string", "description": "End time in natural language or ISO format"],
                    "calendar": ["type": "string", "description": "Calendar name (default: personal)"],
                    "location": ["type": "string", "description": "Optional event location"],
                    "notes": ["type": "string", "description": "Optional event notes"]
                ],
                "required": ["title", "start_time"]
            ]
        ],

        // MARK: Reminders / Tasks
        [
            "name": "get_reminders",
            "description": "List reminders from Apple Reminders. Can filter by list name or show all.",
            "parameters": [
                "type": "object",
                "properties": [
                    "list": ["type": "string", "description": "Optional list name to filter (e.g. 'Quinn', 'Groceries')"],
                    "include_completed": ["type": "string", "description": "Whether to include completed items: 'true' or 'false'"]
                ],
                "required": [] as [String]
            ]
        ],
        [
            "name": "create_reminder",
            "description": "Create a reminder in Apple Reminders.",
            "parameters": [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "The reminder title"],
                    "due_date": ["type": "string", "description": "Optional due date in natural language"],
                    "list": ["type": "string", "description": "Optional reminders list name"],
                    "priority": ["type": "string", "description": "Priority: 'urgent', 'normal', or 'low'"],
                    "notes": ["type": "string", "description": "Optional notes for the reminder"]
                ],
                "required": ["title"]
            ]
        ],
        [
            "name": "complete_reminder",
            "description": "Mark a reminder as complete.",
            "parameters": [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "The reminder title to complete"],
                    "list": ["type": "string", "description": "Optional list name to narrow search"]
                ],
                "required": ["title"]
            ]
        ],

        // MARK: Messaging
        [
            "name": "send_message",
            "description": "Send a message via iMessage. REQUIRES CONFIRMATION before executing.",
            "parameters": [
                "type": "object",
                "properties": [
                    "recipient": ["type": "string", "description": "Who to send to (name or phone number)"],
                    "message": ["type": "string", "description": "The message content"]
                ],
                "required": ["recipient", "message"]
            ]
        ],
        [
            "name": "read_messages",
            "description": "Read recent messages from a conversation.",
            "parameters": [
                "type": "object",
                "properties": [
                    "contact": ["type": "string", "description": "Contact name or phone number"],
                    "limit": ["type": "string", "description": "Number of messages to retrieve (default: 10)"]
                ],
                "required": ["contact"]
            ]
        ],

        // MARK: Email
        [
            "name": "read_email",
            "description": "Read recent emails or search for specific emails.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Search query or 'inbox' for recent, 'unread' for unread"],
                    "account": ["type": "string", "description": "Optional email account to search"],
                    "limit": ["type": "string", "description": "Number of emails (default: 5)"]
                ],
                "required": ["query"]
            ]
        ],
        [
            "name": "send_email",
            "description": "Compose and send an email. REQUIRES CONFIRMATION before executing.",
            "parameters": [
                "type": "object",
                "properties": [
                    "to": ["type": "string", "description": "Recipient email address or contact name"],
                    "subject": ["type": "string", "description": "Email subject line"],
                    "body": ["type": "string", "description": "Email body content"],
                    "account": ["type": "string", "description": "Optional: which email account to send from"]
                ],
                "required": ["to", "subject", "body"]
            ]
        ],

        // MARK: Home Assistant / Smart Home
        [
            "name": "control_lights",
            "description": "Control smart home lights (on/off/brightness/color).",
            "parameters": [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "Natural language command, e.g. 'turn off office lights', 'set bedroom to 50%', 'all lights off'"]
                ],
                "required": ["command"]
            ]
        ],
        [
            "name": "control_thermostat",
            "description": "Control home thermostats (temperature, mode).",
            "parameters": [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "Natural language, e.g. 'set downstairs to 70', 'turn off upstairs heat'"],
                    "zone": ["type": "string", "description": "Optional: 'living_room' or 'upstairs'"]
                ],
                "required": ["command"]
            ]
        ],
        [
            "name": "control_locks",
            "description": "Lock or unlock doors. REQUIRES CONFIRMATION for unlock.",
            "parameters": [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "e.g. 'lock all doors', 'unlock front door'"],
                    "door": ["type": "string", "description": "Optional: 'front_door', 'garden_door', 'kitchen_door', 'garage'"]
                ],
                "required": ["command"]
            ]
        ],
        [
            "name": "control_garage",
            "description": "Open or close the garage door. REQUIRES CONFIRMATION.",
            "parameters": [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "'open' or 'close'"]
                ],
                "required": ["action"]
            ]
        ],
        [
            "name": "get_home_status",
            "description": "Get current smart home status: temperatures, locks, lights, security, appliances.",
            "parameters": [
                "type": "object",
                "properties": [
                    "category": ["type": "string", "description": "Optional filter: 'climate', 'security', 'lights', 'appliances', 'all'"]
                ],
                "required": [] as [String]
            ]
        ],
        [
            "name": "arm_security",
            "description": "Arm or disarm the Abode security system. REQUIRES CONFIRMATION.",
            "parameters": [
                "type": "object",
                "properties": [
                    "mode": ["type": "string", "description": "'home' (perimeter only), 'away' (full), or 'disarm'"]
                ],
                "required": ["mode"]
            ]
        ],
        [
            "name": "run_scene",
            "description": "Run a Home Assistant scene or automation, e.g. 'Good Night', 'Movie Time'.",
            "parameters": [
                "type": "object",
                "properties": [
                    "scene": ["type": "string", "description": "Scene or automation name"]
                ],
                "required": ["scene"]
            ]
        ],

        // MARK: Weather
        [
            "name": "get_weather",
            "description": "Get current weather and forecast for a location.",
            "parameters": [
                "type": "object",
                "properties": [
                    "location": ["type": "string", "description": "City name or location (default: home)"]
                ],
                "required": [] as [String]
            ]
        ],

        // MARK: Notes
        [
            "name": "create_note",
            "description": "Create a note in Apple Notes.",
            "parameters": [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "Note title"],
                    "body": ["type": "string", "description": "Note content"],
                    "folder": ["type": "string", "description": "Optional folder name"]
                ],
                "required": ["title", "body"]
            ]
        ],
        [
            "name": "search_notes",
            "description": "Search Apple Notes for content.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Search query"]
                ],
                "required": ["query"]
            ]
        ],

        // MARK: Files & Drive
        [
            "name": "read_file",
            "description": "Read the contents of a file from the local filesystem or Google Drive.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "File path or Drive path"]
                ],
                "required": ["path"]
            ]
        ],
        [
            "name": "write_file",
            "description": "Write content to a file. REQUIRES CONFIRMATION for overwrites.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "File path"],
                    "content": ["type": "string", "description": "Content to write"]
                ],
                "required": ["path", "content"]
            ]
        ],

        // MARK: Shell / Terminal (Agentic Computer Use)
        [
            "name": "run_command",
            "description": "Execute a shell command in the terminal. REQUIRES CONFIRMATION for destructive commands (rm, git push, sudo, etc.). Use for: running builds, checking status, installing packages, git operations.",
            "parameters": [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "The shell command to execute"],
                    "workdir": ["type": "string", "description": "Optional working directory"]
                ],
                "required": ["command"]
            ]
        ],

        // MARK: Clipboard (Local)
        [
            "name": "get_clipboard",
            "description": "Read the current contents of the user's clipboard/pasteboard. Use when the user says 'summarize what I copied', 'what's on my clipboard', or similar.",
            "parameters": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
        [
            "name": "set_clipboard",
            "description": "Write text to the user's clipboard/pasteboard.",
            "parameters": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "The text to place on the clipboard"]
                ],
                "required": ["text"]
            ]
        ],

        // MARK: Computer Use / Agent Mode
        [
            "name": "type_text",
            "description": "Type text into the currently focused application. Use for entering text, code, commands, etc.",
            "parameters": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "The text to type"]
                ],
                "required": ["text"]
            ]
        ],
        [
            "name": "press_keys",
            "description": "Press a key combination. Supports modifiers: command, option, shift, control. Examples: Cmd+S to save, Cmd+Z to undo, Return to execute.",
            "parameters": [
                "type": "object",
                "properties": [
                    "modifiers": ["type": "string", "description": "Comma-separated modifier keys: command, option, shift, control. Leave empty for no modifiers."],
                    "key": ["type": "string", "description": "The key to press: a-z, 0-9, return, tab, escape, space, delete, up, down, left, right, f1-f12"]
                ],
                "required": ["key"]
            ]
        ],
        [
            "name": "click_at",
            "description": "Click at specific screen coordinates. Use after reading screen content or taking a screenshot to know where UI elements are.",
            "parameters": [
                "type": "object",
                "properties": [
                    "x": ["type": "string", "description": "Horizontal screen coordinate"],
                    "y": ["type": "string", "description": "Vertical screen coordinate"],
                    "button": ["type": "string", "description": "Mouse button: 'left' (default), 'right', or 'middle'"],
                    "clicks": ["type": "string", "description": "Number of clicks: '1' (single, default) or '2' (double)"]
                ],
                "required": ["x", "y"]
            ]
        ],
        [
            "name": "scroll",
            "description": "Scroll up or down in the currently focused window.",
            "parameters": [
                "type": "object",
                "properties": [
                    "direction": ["type": "string", "description": "'up' or 'down'"],
                    "amount": ["type": "string", "description": "Number of scroll units (default: '3')"]
                ],
                "required": ["direction"]
            ]
        ],
        [
            "name": "read_screen",
            "description": "Read the text content of the currently focused window. Returns the app name, window title, focused element, and visible text content.",
            "parameters": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
        [
            "name": "focus_app",
            "description": "Bring a specific application to the foreground. Use before interacting with a particular app.",
            "parameters": [
                "type": "object",
                "properties": [
                    "app_name": ["type": "string", "description": "Application name, e.g. 'Terminal', 'Safari', 'Xcode', 'Visual Studio Code'"]
                ],
                "required": ["app_name"]
            ]
        ],
        [
            "name": "take_screenshot",
            "description": "Capture a screenshot of the currently focused window. Returns the image data for visual analysis.",
            "parameters": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
        [
            "name": "task_complete",
            "description": "Signal that the autonomous task is finished. Call this when the requested task has been completed successfully.",
            "parameters": [
                "type": "object",
                "properties": [
                    "summary": ["type": "string", "description": "A brief summary of what was accomplished"]
                ],
                "required": ["summary"]
            ]
        ],
        [
            "name": "ask_user",
            "description": "Ask the user a question mid-task and wait for their response. Use when you need clarification or a decision from the user.",
            "parameters": [
                "type": "object",
                "properties": [
                    "question": ["type": "string", "description": "The question to ask the user"]
                ],
                "required": ["question"]
            ]
        ]
    ]

    /// Tools that require user confirmation before execution.
    static let confirmationRequired: Set<String> = [
        "send_message", "send_email", "create_calendar_event",
        "control_locks", "control_garage", "arm_security",
        "write_file", "run_command",
        "click_at", "type_text"
    ]

    /// Execute a function call from Gemini by proxying to OpenClaw or handling locally.
    ///
    /// Clipboard tools (`get_clipboard`, `set_clipboard`) are executed locally.
    /// All other tools are proxied through the OpenClaw gateway.
    /// If notifications are enabled, tool results are evaluated for notification-worthy content.
    ///
    /// - Parameters:
    ///   - functionName: The name of the function to execute.
    ///   - arguments: The function arguments as string key-value pairs.
    /// - Returns: The result string from the tool execution.
    func execute(functionName: String, arguments: [String: String]) async -> String {
        let result: String

        // Handle local tools
        switch functionName {
        case "get_clipboard":
            if clipboardEnabled, let clipboard = clipboardManager {
                result = await MainActor.run { clipboard.getClipboard() }
            } else {
                result = "Clipboard access is not enabled."
            }

        case "set_clipboard":
            if clipboardEnabled, let clipboard = clipboardManager, let text = arguments["text"] {
                result = await MainActor.run { clipboard.setClipboard(text) }
            } else {
                result = "Clipboard access is not enabled."
            }

        // MARK: Computer Use Tools
        case "type_text":
            guard computerUseEnabled, let controller = computerController else {
                result = "Computer use is not enabled."
                break
            }
            let text = arguments["text"] ?? ""
            do {
                try await controller.typeText(text)
                result = "Typed \(text.count) characters"
            } catch {
                result = "Error typing text: \(error.localizedDescription)"
            }

        case "press_keys":
            guard computerUseEnabled, let controller = computerController else {
                result = "Computer use is not enabled."
                break
            }
            let modifiersStr = arguments["modifiers"] ?? ""
            let modifiers = modifiersStr.isEmpty ? [] : modifiersStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let key = arguments["key"] ?? "return"
            do {
                try await controller.pressKeys(modifiers: modifiers, key: key)
                result = "Pressed \((modifiers + [key]).joined(separator: "+"))"
            } catch {
                result = "Error pressing keys: \(error.localizedDescription)"
            }

        case "click_at":
            guard computerUseEnabled, let controller = computerController else {
                result = "Computer use is not enabled."
                break
            }
            let x = Double(arguments["x"] ?? "0") ?? 0
            let y = Double(arguments["y"] ?? "0") ?? 0
            let button = arguments["button"] ?? "left"
            let clicks = Int(arguments["clicks"] ?? "1") ?? 1
            do {
                try await controller.click(x: x, y: y, button: button, clicks: clicks)
                result = "Clicked at (\(Int(x)), \(Int(y)))"
            } catch {
                result = "Error clicking: \(error.localizedDescription)"
            }

        case "scroll":
            guard computerUseEnabled, let controller = computerController else {
                result = "Computer use is not enabled."
                break
            }
            let direction = arguments["direction"] ?? "down"
            let amount = Int(arguments["amount"] ?? "3") ?? 3
            do {
                try await controller.scroll(direction: direction, amount: amount)
                result = "Scrolled \(direction) \(amount) units"
            } catch {
                result = "Error scrolling: \(error.localizedDescription)"
            }

        case "read_screen":
            guard computerUseEnabled, let controller = computerController else {
                result = "Computer use is not enabled."
                break
            }
            do {
                result = try await controller.readScreenContent()
            } catch {
                result = "Error reading screen: \(error.localizedDescription)"
            }

        case "focus_app":
            guard computerUseEnabled, let controller = computerController else {
                result = "Computer use is not enabled."
                break
            }
            let appName = arguments["app_name"] ?? ""
            do {
                try await controller.focusApp(appName)
                result = "Focused \(appName)"
            } catch {
                result = "Error focusing app: \(error.localizedDescription)"
            }

        case "take_screenshot":
            guard computerUseEnabled, let controller = computerController else {
                result = "Computer use is not enabled."
                break
            }
            do {
                let data = try await controller.takeScreenshot()
                result = "Screenshot captured (\(data.count) bytes). Image sent to Gemini for analysis."
            } catch {
                result = "Error taking screenshot: \(error.localizedDescription)"
            }

        case "task_complete":
            let summary = arguments["summary"] ?? "Task completed"
            result = "Task complete: \(summary)"

        case "ask_user":
            let question = arguments["question"] ?? "What would you like me to do?"
            result = "Asked user: \(question). Awaiting response."

        default:
            // Proxy to OpenClaw
            do {
                result = try await bridge.executeTool(name: functionName, arguments: arguments)
            } catch {
                return "Error executing \(functionName): \(error.localizedDescription)"
            }
        }

        // Evaluate for notification if enabled
        if notificationsEnabled, let notifManager = notificationManager {
            await notifManager.evaluateAndNotify(toolName: functionName, result: result)
        }

        return result
    }
}
