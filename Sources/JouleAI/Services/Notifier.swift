import Foundation
import UserNotifications

/// Sends JouleAI's macOS notifications (the banners in the top-right corner):
/// - the 20-minute heads-up, with "I'll be ready" / "Push 30 min" / "Not today"
/// - the plain 5-minute reminder
///
/// macOS shows a notification's buttons when you hover it and click "Options"
/// (or always, if JouleAI's style is set to "Alerts" in System Settings →
/// Notifications). When a button is clicked, macOS calls back into this class
/// and we pass the choice to whoever set `onAction`.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {

    enum Action: String {
        case ready = "READY"
        case push = "PUSH"
        case notToday = "NOT_TODAY"
    }

    /// Called on the main thread when a heads-up button is clicked.
    var onAction: ((Action, UUID) -> Void)?

    /// Called on the main thread with whether macOS allows our notifications.
    var onPermissionChecked: ((Bool) -> Void)?

    private let center = UNUserNotificationCenter.current()

    /// Category IDs. A "category" is a named set of buttons a notification can carry.
    private enum Category {
        static let headsUp = "HEADS_UP"               // all three buttons
        static let headsUpNoPush = "HEADS_UP_NO_PUSH" // already pushed once: no Push button
    }

    /// Registers the buttons and asks permission to show notifications
    /// (macOS only asks the user once).
    func setUp() {
        center.delegate = self

        let ready = UNNotificationAction(identifier: Action.ready.rawValue, title: "I’ll be ready")
        let push = UNNotificationAction(identifier: Action.push.rawValue, title: "Push 30 min")
        let notToday = UNNotificationAction(identifier: Action.notToday.rawValue,
                                            title: "Not today", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.headsUp,
                                   actions: [ready, push, notToday], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.headsUpNoPush,
                                   actions: [ready, notToday], intentIdentifiers: []),
        ])

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { print("JouleAI: notification permission error: \(error)") }
            if !granted { print("JouleAI: notifications not allowed; the menu bar countdown still works") }
            self.checkPermission()
        }
    }

    /// Asks macOS whether notifications are currently allowed. Sending one while
    /// they're off fails silently, so this is the only way to know.
    func checkPermission() {
        center.getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            DispatchQueue.main.async { self.onPermissionChecked?(allowed) }
        }
    }

    func sendHeadsUp(for commitment: Commitment) {
        let content = UNMutableNotificationContent()
        content.title = "Coming up: \(commitment.title)"
        let minutes = max(1, Int((commitment.startTime.timeIntervalSinceNow / 60).rounded()))
        content.body = "Starts at \(Self.time(commitment.startTime)), in \(minutes) min. Start winding down."
        content.sound = .default
        content.categoryIdentifier = commitment.canReschedule ? Category.headsUp : Category.headsUpNoPush
        content.userInfo = ["commitmentId": commitment.id.uuidString]
        send(content, id: headsUpID(commitment.id))
    }

    func sendReminder(for commitment: Commitment) {
        let content = UNMutableNotificationContent()
        content.title = "Starting in 5 minutes: \(commitment.title)"
        content.body = "Finish your sentence. JouleAI takes over at \(Self.time(commitment.startTime))."
        content.sound = .default
        send(content, id: "reminder-\(commitment.id.uuidString)")
    }

    /// Clears the heads-up from Notification Center once it's been answered.
    func removeHeadsUp(for id: UUID) {
        center.removeDeliveredNotifications(withIdentifiers: [headsUpID(id)])
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners even though JouleAI counts as "the app in use".
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// A notification (or one of its buttons) was clicked.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let action = Action(rawValue: response.actionIdentifier),
           let idString = info["commitmentId"] as? String,
           let id = UUID(uuidString: idString) {
            DispatchQueue.main.async { self.onAction?(action, id) }
        }
        completionHandler()
    }

    // MARK: - Private

    private func headsUpID(_ id: UUID) -> String { "headsup-\(id.uuidString)" }

    private func send(_ content: UNNotificationContent, id: String) {
        // trigger: nil means "show it now".
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            if let error { print("JouleAI: couldn't show notification: \(error)") }
        }
    }

    private static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
