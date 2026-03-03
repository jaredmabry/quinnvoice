import AppKit
import Foundation
import UserNotifications

/// Manages native macOS notifications for surfacing important tool results.
///
/// Uses `UNUserNotificationCenter` to deliver notifications when Gemini tool calls
/// return results that warrant user attention (calendar conflicts, security alerts,
/// reminders, etc.).
///
/// Supports notification categories with custom actions (e.g., "Open Calendar", "Dismiss")
/// and handles user interaction with those actions.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    // MARK: - Types

    /// Categories of notifications with associated actions.
    enum NotificationCategory: String, Sendable {
        case calendar = "CALENDAR_CATEGORY"
        case reminder = "REMINDER_CATEGORY"
        case security = "SECURITY_CATEGORY"
        case general = "GENERAL_CATEGORY"
    }

    /// Actions available on notifications.
    enum NotificationAction: String, Sendable {
        case openCalendar = "OPEN_CALENDAR"
        case openReminders = "OPEN_REMINDERS"
        case dismiss = "DISMISS"
        case viewDetails = "VIEW_DETAILS"
    }

    // MARK: - Public Properties

    /// Whether notifications are authorized by the user.
    private(set) var isAuthorized: Bool = false

    /// Called when the user taps a notification action.
    var onActionPerformed: ((_ action: NotificationAction, _ notificationId: String) -> Void)?

    // MARK: - Private Properties

    private let center = UNUserNotificationCenter.current()

    // MARK: - Init

    override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Setup

    /// Request notification permissions and register notification categories with actions.
    ///
    /// Call this on first launch or when notifications are enabled in settings.
    /// Registers categories for calendar, reminder, security, and general notifications.
    func requestPermission() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            if granted {
                registerCategories()
            }
        } catch {
            print("[NotificationManager] Permission request failed: \(error.localizedDescription)")
            isAuthorized = false
        }
    }

    /// Check current notification authorization status without prompting.
    func checkAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Sending Notifications

    /// Evaluate a tool result and send a notification if it warrants user attention.
    ///
    /// Analyzes the tool name and result content to determine if a notification
    /// should be shown, and which category/priority to use.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool that was executed.
    ///   - result: The result string from the tool execution.
    func evaluateAndNotify(toolName: String, result: String) async {
        guard isAuthorized else { return }

        let lowered = result.lowercased()

        switch toolName {
        case "create_reminder":
            await sendNotification(
                title: "Reminder Created",
                body: truncateBody(result),
                category: .reminder
            )

        case "search_web" where lowered.contains("alert") || lowered.contains("warning"):
            await sendNotification(
                title: "Search Alert",
                body: truncateBody(result),
                category: .general
            )

        case "control_lights":
            // Light control confirmations are low priority, skip notification
            break

        default:
            // Check for keywords that indicate important results
            if lowered.contains("conflict") || lowered.contains("overlap") {
                await sendNotification(
                    title: "Calendar Conflict",
                    body: truncateBody(result),
                    category: .calendar
                )
            } else if lowered.contains("security") || lowered.contains("breach")
                        || lowered.contains("unauthorized") {
                await sendNotification(
                    title: "⚠️ Security Alert",
                    body: truncateBody(result),
                    category: .security
                )
            }
        }
    }

    /// Send a notification directly with the specified content.
    ///
    /// - Parameters:
    ///   - title: The notification title.
    ///   - body: The notification body text.
    ///   - category: The notification category for action buttons.
    ///   - identifier: A unique identifier for the notification. Defaults to a UUID.
    func sendNotification(
        title: String,
        body: String,
        category: NotificationCategory,
        identifier: String = UUID().uuidString
    ) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category.rawValue

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await center.add(request)
        } catch {
            print("[NotificationManager] Failed to send notification: \(error.localizedDescription)")
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionId = response.actionIdentifier
        let notificationId = response.notification.request.identifier

        await MainActor.run {
            if let action = NotificationAction(rawValue: actionId) {
                handleAction(action)
                onActionPerformed?(action, notificationId)
            } else if actionId == UNNotificationDefaultActionIdentifier {
                // User tapped the notification itself
                onActionPerformed?(.viewDetails, notificationId)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show notifications even when app is in foreground
        return [.banner, .sound]
    }

    // MARK: - Private

    private func registerCategories() {
        let openCalendarAction = UNNotificationAction(
            identifier: NotificationAction.openCalendar.rawValue,
            title: "Open Calendar",
            options: .foreground
        )

        let openRemindersAction = UNNotificationAction(
            identifier: NotificationAction.openReminders.rawValue,
            title: "Open Reminders",
            options: .foreground
        )

        let dismissAction = UNNotificationAction(
            identifier: NotificationAction.dismiss.rawValue,
            title: "Dismiss",
            options: .destructive
        )

        let viewDetailsAction = UNNotificationAction(
            identifier: NotificationAction.viewDetails.rawValue,
            title: "View Details",
            options: .foreground
        )

        let calendarCategory = UNNotificationCategory(
            identifier: NotificationCategory.calendar.rawValue,
            actions: [openCalendarAction, dismissAction],
            intentIdentifiers: []
        )

        let reminderCategory = UNNotificationCategory(
            identifier: NotificationCategory.reminder.rawValue,
            actions: [openRemindersAction, dismissAction],
            intentIdentifiers: []
        )

        let securityCategory = UNNotificationCategory(
            identifier: NotificationCategory.security.rawValue,
            actions: [viewDetailsAction, dismissAction],
            intentIdentifiers: []
        )

        let generalCategory = UNNotificationCategory(
            identifier: NotificationCategory.general.rawValue,
            actions: [viewDetailsAction, dismissAction],
            intentIdentifiers: []
        )

        center.setNotificationCategories([
            calendarCategory,
            reminderCategory,
            securityCategory,
            generalCategory
        ])
    }

    private func handleAction(_ action: NotificationAction) {
        switch action {
        case .openCalendar:
            NSWorkspace.shared.open(URL(string: "ical://")!)

        case .openReminders:
            NSWorkspace.shared.open(URL(string: "x-apple-reminderkit://")!)

        case .viewDetails, .dismiss:
            break
        }
    }

    /// Truncate body text to a reasonable notification length.
    private func truncateBody(_ text: String) -> String {
        if text.count <= 200 {
            return text
        }
        return String(text.prefix(197)) + "…"
    }
}
