import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Core computer interaction engine using macOS Accessibility API and CGEvent.
///
/// Provides programmatic control over the macOS desktop environment including:
/// - Reading screen content from any window via `AXUIElement`
/// - Typing text and pressing key combinations via `CGEvent`
/// - Mouse clicks, scrolling, and window management
/// - Screenshot capture via `CGWindowListCreateImage`
///
/// All methods are async and designed for Swift 6.2 concurrency.
///
/// - Important: Requires Accessibility permissions granted in
///   System Settings → Privacy & Security → Accessibility.
///   Many methods will return errors if permissions are not granted.
actor ComputerController {

    // MARK: - Types

    /// Errors that can occur during computer control operations.
    enum ControlError: Error, LocalizedError, Sendable {
        case accessibilityNotGranted
        case elementNotFound(String)
        case actionFailed(String)
        case screenshotFailed
        case commandFailed(String)
        case appNotFound(String)
        case timeout

        var errorDescription: String? {
            switch self {
            case .accessibilityNotGranted:
                return "Accessibility permissions not granted. Enable in System Settings → Privacy & Security → Accessibility."
            case .elementNotFound(let detail):
                return "UI element not found: \(detail)"
            case .actionFailed(let detail):
                return "Action failed: \(detail)"
            case .screenshotFailed:
                return "Screenshot capture failed"
            case .commandFailed(let detail):
                return "Command failed: \(detail)"
            case .appNotFound(let name):
                return "Application not found: \(name)"
            case .timeout:
                return "Operation timed out"
            }
        }
    }

    /// Information about a visible window.
    struct WindowInfo: Sendable {
        let appName: String
        let title: String
        let bounds: CGRect
        let windowID: CGWindowID
        let isOnScreen: Bool
    }

    // MARK: - Properties

    /// Allowed applications the agent can interact with.
    private var allowedApps: Set<String> = []

    // MARK: - Configuration

    /// Update the set of applications the agent is allowed to interact with.
    func setAllowedApps(_ apps: [String]) {
        allowedApps = Set(apps)
    }

    // MARK: - Permission Checks

    /// Check if the app has Accessibility permissions.
    /// - Parameter prompt: If `true`, shows the system prompt to grant access.
    /// - Returns: `true` if accessibility is granted.
    @MainActor
    static func hasAccessibilityPermissions(prompt: Bool = false) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Verify accessibility permissions, throwing if not granted.
    @MainActor
    private func ensureAccessibility() throws(ControlError) {
        guard Self.hasAccessibilityPermissions(prompt: false) else {
            throw .accessibilityNotGranted
        }
    }

    // MARK: - Read Screen Content

    /// Read the text content of the frontmost application's focused window.
    ///
    /// Uses the Accessibility API to traverse the UI element hierarchy and extract
    /// visible text content including window title, focused element value, and
    /// the full text of text areas.
    ///
    /// - Returns: A string containing the screen content, or an error description.
    @MainActor
    func readScreenContent() async throws -> String {
        try ensureAccessibility()

        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw ControlError.elementNotFound("No frontmost application")
        }

        let appName = frontApp.localizedName ?? "Unknown"
        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var parts: [String] = ["=== Screen Content ===", "App: \(appName)"]

        // Get window title
        if let title = axGetStringAttribute(appElement, kAXFocusedWindowAttribute, then: kAXTitleAttribute) {
            parts.append("Window: \(title)")
        }

        // Get focused element info
        var focusedElement: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success {
            let element = focusedElement as! AXUIElement

            // Role
            if let role = axGetString(element, kAXRoleAttribute) {
                parts.append("Focused element role: \(role)")
            }

            // Value (text content)
            if let value = axGetString(element, kAXValueAttribute) {
                let truncated = value.count > 3000 ? String(value.suffix(3000)) : value
                parts.append("Content:\n\(truncated)")
            }

            // Selected text
            if let selected = axGetString(element, kAXSelectedTextAttribute), !selected.isEmpty {
                parts.append("Selected text: \(selected)")
            }
        }

        return parts.joined(separator: "\n")
    }

    /// Read the last N lines from a terminal window (Terminal.app or iTerm2).
    ///
    /// Uses the Accessibility API to find the terminal text area and extract
    /// the most recent output.
    ///
    /// - Parameter lineCount: Number of lines to read from the end (default: 50).
    /// - Returns: The terminal output text.
    @MainActor
    func readTerminalOutput(lineCount: Int = 50) async throws -> String {
        try ensureAccessibility()

        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw ControlError.elementNotFound("No frontmost application")
        }

        let appName = frontApp.localizedName ?? ""
        guard appName == "Terminal" || appName == "iTerm2" else {
            throw ControlError.actionFailed("Frontmost app is \(appName), not a terminal")
        }

        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Find the text area element
        guard let textContent = findTerminalTextContent(in: appElement) else {
            throw ControlError.elementNotFound("Terminal text area not found")
        }

        // Return last N lines
        let lines = textContent.components(separatedBy: .newlines)
        let lastLines = lines.suffix(lineCount)
        return lastLines.joined(separator: "\n")
    }

    // MARK: - Type Text

    /// Type text into the currently focused application.
    ///
    /// Injects keystrokes character by character with a small delay between each
    /// to ensure reliable input delivery.
    ///
    /// - Parameter text: The text string to type.
    @MainActor
    func typeText(_ text: String) async throws {
        try ensureAccessibility()

        let source = CGEventSource(stateID: .hidSystemState)

        for char in text {
            if char == "\n" {
                // Press Return
                try pressKey(virtualKey: 36, source: source) // Return key
            } else if char == "\t" {
                // Press Tab
                try pressKey(virtualKey: 48, source: source) // Tab key
            } else {
                // Use CGEvent with Unicode character
                let string = String(char)
                guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                    continue
                }

                let utf16 = Array(string.utf16)
                keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

                keyDown.post(tap: .cgAnnotatedSessionEventTap)
                keyUp.post(tap: .cgAnnotatedSessionEventTap)
            }

            // Small delay for reliable keystroke delivery
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Press Key Combinations

    /// Press a key combination with optional modifiers.
    ///
    /// Supports modifier keys: command (⌘), option (⌥), shift (⇧), control (⌃).
    ///
    /// - Parameters:
    ///   - modifiers: Array of modifier names (e.g., ["command", "shift"]).
    ///   - key: The key to press (e.g., "s", "z", "return", "tab", "escape", "space").
    @MainActor
    func pressKeys(modifiers: [String], key: String) async throws {
        try ensureAccessibility()

        let source = CGEventSource(stateID: .hidSystemState)
        let virtualKey = Self.virtualKeyCode(for: key)

        // Build modifier flags
        var flags: CGEventFlags = []
        for modifier in modifiers {
            switch modifier.lowercased() {
            case "command", "cmd", "⌘":
                flags.insert(.maskCommand)
            case "option", "alt", "opt", "⌥":
                flags.insert(.maskAlternate)
            case "shift", "⇧":
                flags.insert(.maskShift)
            case "control", "ctrl", "⌃":
                flags.insert(.maskControl)
            default:
                break
            }
        }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else {
            throw ControlError.actionFailed("Failed to create keyboard event for key: \(key)")
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        try await Task.sleep(for: .milliseconds(50))
    }

    // MARK: - Mouse Click

    /// Click at the specified screen coordinates.
    ///
    /// - Parameters:
    ///   - x: Horizontal screen coordinate.
    ///   - y: Vertical screen coordinate.
    ///   - button: "left", "right", or "middle" (default: "left").
    ///   - clicks: Number of clicks — 1 for single, 2 for double (default: 1).
    @MainActor
    func click(x: Double, y: Double, button: String = "left", clicks: Int = 1) async throws {
        try ensureAccessibility()

        let point = CGPoint(x: x, y: y)
        let source = CGEventSource(stateID: .hidSystemState)

        let (downType, upType, mouseButton): (CGEventType, CGEventType, CGMouseButton) = switch button.lowercased() {
        case "right":
            (.rightMouseDown, .rightMouseUp, .right)
        case "middle":
            (.otherMouseDown, .otherMouseUp, .center)
        default:
            (.leftMouseDown, .leftMouseUp, .left)
        }

        for clickIndex in 1...clicks {
            guard let mouseDown = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: mouseButton),
                  let mouseUp = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: mouseButton) else {
                throw ControlError.actionFailed("Failed to create mouse event")
            }

            // Set click count for double/triple click
            mouseDown.setIntegerValueField(.mouseEventClickState, value: Int64(clickIndex))
            mouseUp.setIntegerValueField(.mouseEventClickState, value: Int64(clickIndex))

            mouseDown.post(tap: .cgAnnotatedSessionEventTap)
            mouseUp.post(tap: .cgAnnotatedSessionEventTap)

            if clickIndex < clicks {
                try await Task.sleep(for: .milliseconds(50))
            }
        }

        try await Task.sleep(for: .milliseconds(50))
    }

    // MARK: - Scroll

    /// Scroll in the focused window.
    ///
    /// - Parameters:
    ///   - direction: "up" or "down".
    ///   - amount: Number of scroll units (default: 3).
    @MainActor
    func scroll(direction: String, amount: Int = 3) async throws {
        try ensureAccessibility()

        let scrollAmount = direction.lowercased() == "up" ? Int32(amount) : -Int32(amount)

        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: scrollAmount, wheel2: 0, wheel3: 0) else {
            throw ControlError.actionFailed("Failed to create scroll event")
        }

        event.post(tap: .cgAnnotatedSessionEventTap)
        try await Task.sleep(for: .milliseconds(50))
    }

    // MARK: - Window Management

    /// Get a list of all visible windows on screen.
    ///
    /// - Returns: Array of ``WindowInfo`` describing each visible window.
    @MainActor
    func getWindowList() async -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowList.compactMap { info -> WindowInfo? in
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] else {
                return nil
            }

            let title = info[kCGWindowName as String] as? String ?? ""
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? true

            // Filter out windows with zero size
            guard bounds.width > 1 && bounds.height > 1 else { return nil }

            return WindowInfo(
                appName: ownerName,
                title: title,
                bounds: bounds,
                windowID: windowID,
                isOnScreen: isOnScreen
            )
        }
    }

    /// Bring a specific application to the foreground.
    ///
    /// - Parameter appName: The name of the application to focus (e.g., "Terminal", "Safari").
    @MainActor
    func focusApp(_ appName: String) async throws {
        let runningApps = NSWorkspace.shared.runningApplications

        guard let app = runningApps.first(where: {
            $0.localizedName?.localizedCaseInsensitiveCompare(appName) == .orderedSame
        }) else {
            throw ControlError.appNotFound(appName)
        }

        let success = app.activate()
        guard success else {
            throw ControlError.actionFailed("Failed to activate \(appName)")
        }

        // Wait for app to come to front
        try await Task.sleep(for: .milliseconds(200))
    }

    // MARK: - Screenshot

    /// Capture a screenshot of the frontmost window using ScreenCaptureKit.
    ///
    /// - Returns: PNG image data of the screenshot.
    @MainActor
    func takeScreenshot() async throws -> Data {
        try ensureAccessibility()

        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw ControlError.elementNotFound("No frontmost application")
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        // Find a window belonging to the frontmost app
        let pid = frontApp.processIdentifier
        let targetWindow = content.windows.first { $0.owningApplication?.processID == pid }

        if let window = targetWindow {
            // Capture the specific window
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width) * 2
            config.height = Int(window.frame.height) * 2
            config.capturesAudio = false
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
                throw ControlError.screenshotFailed
            }
            return pngData
        } else {
            // Fallback: capture the main display
            return try await captureFullScreen()
        }
    }

    /// Execute a shell command and return the output.
    ///
    /// - Parameters:
    ///   - command: The shell command to run.
    ///   - workdir: Optional working directory.
    /// - Returns: The command output (stdout + stderr).
    nonisolated func runCommand(_ command: String, workdir: String? = nil) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        if let workdir {
            process.currentDirectoryURL = URL(fileURLWithPath: workdir)
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()

        let outStr = String(data: outData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""

        let status = process.terminationStatus

        var result = ""
        if !outStr.isEmpty {
            result += outStr
        }
        if !errStr.isEmpty {
            result += (result.isEmpty ? "" : "\n") + "STDERR: \(errStr)"
        }
        if status != 0 {
            result += (result.isEmpty ? "" : "\n") + "Exit code: \(status)"
        }

        // Truncate very long output
        if result.count > 5000 {
            result = String(result.suffix(5000))
            result = "[truncated]\n" + result
        }

        return result.isEmpty ? "(no output)" : result
    }

    // MARK: - Private Helpers

    /// Press a single virtual key.
    @MainActor
    private func pressKey(virtualKey: CGKeyCode, source: CGEventSource?) throws {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else {
            throw ControlError.actionFailed("Failed to create key event for virtual key \(virtualKey)")
        }

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Capture a full-screen screenshot using ScreenCaptureKit.
    @MainActor
    private func captureFullScreen() async throws -> Data {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let display = content.displays.first else {
            throw ControlError.screenshotFailed
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(display.width) * 2
        config.height = Int(display.height) * 2
        config.capturesAudio = false
        config.showsCursor = true

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ControlError.screenshotFailed
        }

        return pngData
    }

    /// Extract a string attribute from an AXUIElement.
    @MainActor
    private func axGetString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    /// Get a string attribute from a child element (e.g., window title from focused window).
    @MainActor
    private func axGetStringAttribute(_ element: AXUIElement, _ childAttr: String, then attr: String) -> String? {
        var child: AnyObject?
        guard AXUIElementCopyAttributeValue(element, childAttr as CFString, &child) == .success else {
            return nil
        }
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(child as! AXUIElement, attr as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    /// Recursively search for terminal text content in the accessibility tree.
    @MainActor
    private func findTerminalTextContent(in element: AXUIElement) -> String? {
        // Check if this element has a text value
        if let role = axGetString(element, kAXRoleAttribute),
           (role == "AXTextArea" || role == "AXStaticText"),
           let value = axGetString(element, kAXValueAttribute),
           !value.isEmpty {
            return value
        }

        // Search children
        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let childArray = children as? [AXUIElement] else {
            return nil
        }

        for child in childArray {
            if let text = findTerminalTextContent(in: child) {
                return text
            }
        }

        return nil
    }

    // MARK: - Virtual Key Code Mapping

    /// Map a key name string to a macOS virtual key code.
    static func virtualKeyCode(for key: String) -> CGKeyCode {
        switch key.lowercased() {
        // Letters
        case "a": return 0
        case "b": return 11
        case "c": return 8
        case "d": return 2
        case "e": return 14
        case "f": return 3
        case "g": return 5
        case "h": return 4
        case "i": return 34
        case "j": return 38
        case "k": return 40
        case "l": return 37
        case "m": return 46
        case "n": return 45
        case "o": return 31
        case "p": return 35
        case "q": return 12
        case "r": return 15
        case "s": return 1
        case "t": return 17
        case "u": return 32
        case "v": return 9
        case "w": return 13
        case "x": return 7
        case "y": return 16
        case "z": return 6

        // Numbers
        case "0": return 29
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "5": return 23
        case "6": return 22
        case "7": return 26
        case "8": return 28
        case "9": return 25

        // Special keys
        case "return", "enter": return 36
        case "tab": return 48
        case "space": return 49
        case "delete", "backspace": return 51
        case "escape", "esc": return 53
        case "forwarddelete": return 117

        // Arrow keys
        case "left", "leftarrow": return 123
        case "right", "rightarrow": return 124
        case "down", "downarrow": return 125
        case "up", "uparrow": return 126

        // Function keys
        case "f1": return 122
        case "f2": return 120
        case "f3": return 99
        case "f4": return 118
        case "f5": return 96
        case "f6": return 97
        case "f7": return 98
        case "f8": return 100
        case "f9": return 101
        case "f10": return 109
        case "f11": return 103
        case "f12": return 111

        // Punctuation
        case "-", "minus": return 27
        case "=", "equal", "equals": return 24
        case "[", "leftbracket": return 33
        case "]", "rightbracket": return 30
        case "\\", "backslash": return 42
        case ";", "semicolon": return 41
        case "'", "quote": return 39
        case ",", "comma": return 43
        case ".", "period": return 47
        case "/", "slash": return 44
        case "`", "grave": return 50

        // Home/End/Page
        case "home": return 115
        case "end": return 119
        case "pageup": return 116
        case "pagedown": return 121

        default: return 0
        }
    }
}
