import AppKit
import ApplicationServices
import Foundation

/// Captures the current screen context (frontmost app, window title, selected text)
/// for inclusion in Gemini prompts.
///
/// Uses `NSWorkspace` for app identification and the macOS Accessibility API (`AXUIElement`)
/// for window title and selected text extraction.
///
/// - Important: Requires Accessibility permissions to read window titles and selected text.
///   The app must be added to System Settings → Privacy & Security → Accessibility.
@MainActor
final class ScreenContextProvider {

    // MARK: - Types

    /// A snapshot of the user's current screen context.
    struct ScreenContext: Sendable {
        /// The name of the frontmost application (e.g., "Safari", "Xcode").
        let appName: String

        /// The title of the focused window, if accessible.
        let windowTitle: String?

        /// Currently selected text in the frontmost app, if any.
        let selectedText: String?

        /// A human-readable description suitable for inclusion in a prompt.
        var description: String {
            var parts: [String] = []
            if let title = windowTitle, !title.isEmpty {
                parts.append("User is currently viewing: \(appName) — \(title)")
            } else {
                parts.append("User is currently viewing: \(appName)")
            }
            if let selected = selectedText, !selected.isEmpty {
                let truncated = selected.count > 500
                    ? String(selected.prefix(500)) + "…"
                    : selected
                parts.append("Selected text: \"\(truncated)\"")
            }
            return parts.joined(separator: "\n")
        }
    }

    // MARK: - Public Methods

    /// Capture the current screen context including frontmost app, window title,
    /// and optionally selected text.
    ///
    /// - Parameter includeSelectedText: Whether to attempt reading selected text
    ///   from the frontmost application. Defaults to `true`.
    /// - Returns: A ``ScreenContext`` snapshot, or `nil` if the frontmost app
    ///   cannot be determined.
    func captureContext(includeSelectedText: Bool = true) -> ScreenContext? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appName = frontApp.localizedName ?? "Unknown App"
        let pid = frontApp.processIdentifier

        // Use Accessibility API to get window title and selected text
        let appElement = AXUIElementCreateApplication(pid)

        let windowTitle = getWindowTitle(from: appElement)
        let selectedText = includeSelectedText ? getSelectedText(from: appElement) : nil

        return ScreenContext(
            appName: appName,
            windowTitle: windowTitle,
            selectedText: selectedText
        )
    }

    /// Get just the frontmost app name without Accessibility API calls.
    /// This is a lightweight alternative when full context is not needed.
    ///
    /// - Returns: The localized name of the frontmost application, or `nil`.
    func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    // MARK: - Accessibility API Helpers

    /// Read the title of the focused window from the frontmost application.
    private func getWindowTitle(from appElement: AXUIElement) -> String? {
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard result == .success else { return nil }

        var titleValue: AnyObject?
        let titleResult = AXUIElementCopyAttributeValue(
            focusedWindow as! AXUIElement,
            kAXTitleAttribute as CFString,
            &titleValue
        )

        guard titleResult == .success,
              let title = titleValue as? String else {
            return nil
        }

        return title
    }

    /// Read the currently selected text from the frontmost application.
    private func getSelectedText(from appElement: AXUIElement) -> String? {
        // First, try to get the focused UI element
        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusResult == .success else { return nil }

        // Try to get the selected text attribute
        var selectedTextValue: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            focusedElement as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextValue
        )

        guard textResult == .success,
              let text = selectedTextValue as? String,
              !text.isEmpty else {
            return nil
        }

        return text
    }

    /// Check if the app has Accessibility permissions needed for screen context capture.
    ///
    /// - Parameter prompt: If `true`, shows the system prompt to grant accessibility access.
    /// - Returns: `true` if the app has accessibility permissions.
    static func hasAccessibilityPermissions(prompt: Bool = false) -> Bool {
        // The string value of kAXTrustedCheckOptionPrompt is "AXTrustedCheckOptionPrompt"
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
