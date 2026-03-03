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

    /// Whether clipboard tools are available.
    var clipboardEnabled: Bool = false

    /// Whether notifications are enabled for tool results.
    var notificationsEnabled: Bool = false

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
        ]
    ]

    /// Tools that require user confirmation before execution.
    static let confirmationRequired: Set<String> = [
        "send_message", "send_email", "create_calendar_event",
        "control_locks", "control_garage", "arm_security",
        "write_file", "run_command"
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
