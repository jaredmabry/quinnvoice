import AppKit
import Foundation

/// Monitors and provides access to the macOS system clipboard (pasteboard).
///
/// Tracks clipboard changes by polling `NSPasteboard.general` change count,
/// and exposes `get_clipboard` / `set_clipboard` operations that can be called
/// as Gemini tools via ``GeminiToolProxy``.
///
/// - Note: Pasteboard monitoring uses a lightweight timer-based approach since
///   `NSPasteboard` does not provide native change notifications.
@MainActor
final class ClipboardManager {

    // MARK: - Public Properties

    /// The most recently captured clipboard content (text only).
    private(set) var currentContent: String?

    /// Called when clipboard content changes.
    var onClipboardChanged: ((_ newContent: String) -> Void)?

    /// Whether clipboard monitoring is active.
    private(set) var isMonitoring: Bool = false

    // MARK: - Private Properties

    private var pollTimer: Timer?
    private var lastChangeCount: Int = 0

    /// Polling interval for clipboard changes (in seconds).
    private let pollInterval: TimeInterval = 1.0

    // MARK: - Monitoring

    /// Start monitoring the clipboard for changes.
    ///
    /// Begins polling `NSPasteboard.general` at a regular interval.
    /// When the change count increments, the new text content is captured
    /// and ``onClipboardChanged`` is called.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        lastChangeCount = NSPasteboard.general.changeCount

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForChanges()
            }
        }
    }

    /// Stop monitoring the clipboard for changes.
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Clipboard Operations

    /// Read the current text content from the system clipboard.
    ///
    /// - Returns: The clipboard text content, or a message indicating
    ///   the clipboard is empty or contains non-text data.
    func getClipboard() -> String {
        if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            currentContent = text
            return text
        }

        // Check for other content types
        let types = NSPasteboard.general.types ?? []
        if types.contains(.fileURL) {
            if let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL] {
                let paths = urls.map(\.path).joined(separator: "\n")
                return "Clipboard contains file(s):\n\(paths)"
            }
        }

        if types.contains(.png) || types.contains(.tiff) {
            return "Clipboard contains an image (non-text content)."
        }

        return "Clipboard is empty or contains unsupported content."
    }

    /// Write text content to the system clipboard.
    ///
    /// - Parameter text: The text to place on the clipboard.
    /// - Returns: A confirmation message.
    func setClipboard(_ text: String) -> String {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        currentContent = text
        lastChangeCount = NSPasteboard.general.changeCount
        return "Clipboard updated successfully."
    }

    // MARK: - Private

    private func checkForChanges() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            currentContent = text
            onClipboardChanged?(text)
        }
    }
}
