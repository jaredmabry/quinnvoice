import AppKit
import Carbon
import Foundation

/// The mode for the global hotkey behavior.
enum HotkeyMode: String, Codable, Sendable, CaseIterable {
    /// Hold the hotkey to talk; release to stop.
    case hold
    /// Press once to start, press again to stop.
    case toggle
}

/// Manages global hotkey registration for push-to-talk and toggle-to-talk modes.
///
/// Uses `NSEvent` global and local event monitors to detect the configured hotkey combination.
/// Requires Accessibility permissions on macOS for global event monitoring.
@MainActor
final class HotkeyManager {

    // MARK: - Public Properties

    /// Called when push-to-talk should begin (key down in hold mode, or toggle on).
    var onActivate: (() -> Void)?

    /// Called when push-to-talk should end (key up in hold mode, or toggle off).
    var onDeactivate: (() -> Void)?

    /// Whether the hotkey is currently in the "active" state.
    private(set) var isActive: Bool = false

    /// The current hotkey mode (hold vs toggle).
    var mode: HotkeyMode = .hold

    // MARK: - Configurable Key

    /// The key code to listen for (Carbon virtual key code). Default: 49 (Space).
    private(set) var keyCode: UInt16 = 49

    /// The required modifier flags. Default: Option key.
    private(set) var modifierFlags: NSEvent.ModifierFlags = .option

    // MARK: - Private Properties

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var globalKeyUpMonitor: Any?
    private var localKeyUpMonitor: Any?
    private var flagsMonitor: Any?
    private var isStarted = false

    // MARK: - Configuration

    /// Configure the hotkey with a custom key code and modifier flags.
    func configure(keyCode: UInt16, modifiers: UInt) {
        let wasRunning = isStarted
        if wasRunning { stop() }

        self.keyCode = keyCode
        self.modifierFlags = NSEvent.ModifierFlags(rawValue: modifiers)
            .intersection([.command, .option, .control, .shift])

        if wasRunning { start() }
    }

    // MARK: - Lifecycle

    /// Start listening for the global hotkey.
    func start() {
        guard !isStarted else { return }
        isStarted = true

        // Global monitor for key-down (events outside this app)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleKeyDown(event)
            }
        }

        // Local monitor for key-down (events inside this app)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleKeyDown(event)
            }
            return event
        }

        // Global monitor for key-up (hold mode release detection)
        globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleKeyUp(event)
            }
        }

        // Local monitor for key-up
        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleKeyUp(event)
            }
            return event
        }

        // Monitor flags-changed to detect modifier release in hold mode
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFlagsChanged(event)
            }
        }
    }

    /// Stop listening for the global hotkey and clean up all event monitors.
    func stop() {
        guard isStarted else { return }

        for monitor in [globalMonitor, localMonitor, globalKeyUpMonitor, localKeyUpMonitor, flagsMonitor] {
            if let m = monitor {
                NSEvent.removeMonitor(m)
            }
        }
        globalMonitor = nil
        localMonitor = nil
        globalKeyUpMonitor = nil
        localKeyUpMonitor = nil
        flagsMonitor = nil

        if isActive {
            deactivate()
        }

        isStarted = false
    }

    // MARK: - Event Handling

    /// Check if the event matches the configured hotkey combination.
    private func isHotkeyEvent(_ event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }

        // Check that the required modifiers are present
        let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let eventModifiers = event.modifierFlags.intersection(relevantModifiers)
        return eventModifiers == modifierFlags
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard isHotkeyEvent(event) else { return }
        if event.isARepeat { return }

        switch mode {
        case .hold:
            if !isActive { activate() }
        case .toggle:
            if isActive { deactivate() } else { activate() }
        }
    }

    private func handleKeyUp(_ event: NSEvent) {
        guard event.keyCode == keyCode else { return }
        if mode == .hold && isActive {
            deactivate()
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        // If required modifier was released while in hold mode and active, deactivate
        guard mode == .hold && isActive else { return }
        let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let currentModifiers = event.modifierFlags.intersection(relevantModifiers)
        if !currentModifiers.contains(modifierFlags) {
            deactivate()
        }
    }

    // MARK: - State Management

    private func activate() {
        isActive = true
        onActivate?()
    }

    private func deactivate() {
        isActive = false
        onDeactivate?()
    }

    /// Check if the app has Accessibility permissions needed for global event monitoring.
    static func checkAccessibilityPermissions(prompt: Bool = false) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Key Formatting

    /// Format a key code and modifier flags into a human-readable string.
    static func formatHotkey(keyCode: UInt16, modifiers: UInt) -> String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)

        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }

        parts.append(keyName(for: keyCode))
        return parts.joined()
    }

    /// Get a human-readable name for a Carbon virtual key code.
    static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Escape"
        case 76: return "Enter"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 118: return "F4"
        case 119: return "F2"
        case 120: return "F1"
        case 121: return "PageDown"
        case 122: return "F16"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key(\(keyCode))"
        }
    }
}
