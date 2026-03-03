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

/// Manages global hotkey registration (⌥Space) for push-to-talk and toggle-to-talk modes.
///
/// Uses `NSEvent` global and local event monitors to detect the configured hotkey combination.
/// Requires Accessibility permissions on macOS for global event monitoring.
///
/// - Note: The hotkey manager must be started via ``start()`` and stopped via ``stop()``
///   to properly register and unregister event monitors.
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

    // MARK: - Private Properties

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var globalKeyUpMonitor: Any?
    private var localKeyUpMonitor: Any?
    private var isStarted = false

    /// The key code for Space bar (Carbon virtual key code).
    private let spaceKeyCode: UInt16 = 49

    // MARK: - Lifecycle

    /// Start listening for the global hotkey (⌥Space).
    ///
    /// Registers both global and local event monitors for key-down and key-up events.
    /// In hold mode, key-down activates and key-up deactivates.
    /// In toggle mode, each key-down toggles the active state.
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

        // Also monitor flags-changed to detect Option key release in hold mode
        // (in case Space is released before Option)
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFlagsChanged(event)
            }
        }
    }

    /// Stop listening for the global hotkey and clean up all event monitors.
    func stop() {
        guard isStarted else { return }

        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = globalKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyUpMonitor = nil
        }
        if let monitor = localKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyUpMonitor = nil
        }

        if isActive {
            deactivate()
        }

        isStarted = false
    }

    // MARK: - Event Handling

    /// Check if the event matches the ⌥Space hotkey combination.
    private func isHotkeyEvent(_ event: NSEvent) -> Bool {
        // Check for Option modifier and Space key
        let hasOption = event.modifierFlags.contains(.option)
        let isSpace = event.keyCode == spaceKeyCode
        // Ensure no other modifiers (Command, Control, Shift) are pressed
        let noOtherModifiers = !event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.control)
            && !event.modifierFlags.contains(.shift)
        return hasOption && isSpace && noOtherModifiers
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard isHotkeyEvent(event) else { return }

        // Ignore key repeat events (held key sends repeated key-down)
        if event.isARepeat { return }

        switch mode {
        case .hold:
            if !isActive {
                activate()
            }
        case .toggle:
            if isActive {
                deactivate()
            } else {
                activate()
            }
        }
    }

    private func handleKeyUp(_ event: NSEvent) {
        guard event.keyCode == spaceKeyCode else { return }

        // Only deactivate on key-up in hold mode
        if mode == .hold && isActive {
            deactivate()
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        // If Option key was released while in hold mode and active, deactivate
        if mode == .hold && isActive && !event.modifierFlags.contains(.option) {
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
    ///
    /// - Parameter prompt: If `true`, shows the system prompt to grant accessibility access.
    /// - Returns: `true` if the app is a trusted accessibility client.
    static func checkAccessibilityPermissions(prompt: Bool = false) -> Bool {
        // The string value of kAXTrustedCheckOptionPrompt is "AXTrustedCheckOptionPrompt"
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
